package ar.skaymer.dnscryptmanager

import org.json.JSONObject

internal class DnsCryptRepository(
    private val shell: RootShell = RootShell(),
) {
    suspend fun loadSnapshot(): DashboardSnapshot {
        val statusResult = shell.run(RootShell.Command.Status)
        if (!statusResult.ok) {
            throw RootBridgeException(statusResult.output.ifBlank { "No se pudo leer el estado del módulo." })
        }

        val statusJson = JSONObject(statusResult.output)
        val activityStatus = shell.run(RootShell.Command.ActivityStatus)
        val activityJson = if (activityStatus.ok) JSONObject(activityStatus.output) else null
        val eventsResult = if (activityStatus.ok) {
            shell.run(RootShell.Command.ActivityList(100))
        } else {
            RootShell.Result(1, "La actividad DNS no está disponible en esta versión del módulo.")
        }
        val statsResult = if (activityStatus.ok) {
            shell.run(RootShell.Command.ActivityStats)
        } else {
            RootShell.Result(1, "La actividad DNS no está disponible en esta versión del módulo.")
        }

        val status = ModuleStatus(
            running = statusJson.optBoolean("running", false),
            listening = statusJson.optBoolean("listening", false),
            redirectActive = statusJson.optString("redirect") in setOf("activa", "active", "enabled"),
            server = statusJson.optString("server", ""),
            version = statusJson.optString("version", ""),
            activityEnabled = activityJson?.optBoolean("enabled", false) ?: false,
        )
        return DashboardSnapshot(
            status = status,
            activitySupported = activityStatus.ok,
            events = if (eventsResult.ok) parseEvents(eventsResult.output) else emptyList(),
            stats = if (statsResult.ok) parseStats(statsResult.output) else ActivityStats(),
        )
    }

    suspend fun loadCatalogGroups(): List<CatalogGroup> {
        val result = shell.run(RootShell.Command.CatalogGroups)
        if (!result.ok) throw ModuleOperationException(result.output.ifBlank { "No se pudo abrir el catálogo." })
        val groups = JSONObject(result.output).optJSONArray("groups") ?: return emptyList()
        return buildList(groups.length()) {
            for (index in 0 until groups.length()) {
                val item = groups.optJSONObject(index) ?: continue
                add(
                    CatalogGroup(
                        key = item.optString("key"),
                        count = item.optInt("count"),
                        active = item.optInt("active"),
                    ),
                )
            }
        }
    }

    suspend fun loadCatalogGroup(group: String): List<CatalogEntry> {
        val result = shell.run(RootShell.Command.CatalogList(group))
        if (!result.ok) throw ModuleOperationException(result.output.ifBlank { "No se pudo leer esta categoría." })
        val entries = JSONObject(result.output).optJSONArray("entries") ?: return emptyList()
        return buildList(entries.length()) {
            for (index in 0 until entries.length()) {
                val item = entries.optJSONObject(index) ?: continue
                add(
                    CatalogEntry(
                        id = item.optString("id"),
                        name = item.optString("name"),
                        sourceName = item.optString("source_name"),
                        sourceGroup = item.optString("source_group"),
                        subgroup = item.optString("source_subgroup"),
                        categories = item.optString("categories"),
                        aggressiveness = item.optString("aggressiveness"),
                        license = item.optString("license"),
                        upstreamStatus = item.optString("upstream_status"),
                        runtimeStatus = item.optString("runtime_status"),
                        recommended = item.optBoolean("recommended", false),
                        archived = item.optBoolean("archived", false),
                        enabled = item.optBoolean("enabled", false),
                        activationBlocked = item.optBoolean("activation_blocked", false),
                        domainCount = item.optString("valid_domains", "-"),
                    ),
                )
            }
        }
    }

    suspend fun loadDownloadProgress(): DownloadProgress {
        val result = shell.run(RootShell.Command.CatalogDownloadAllStatus)
        if (!result.ok) throw ModuleOperationException(result.output.ifBlank { "No se pudo consultar la descarga." })
        val item = JSONObject(result.output)
        return DownloadProgress(
            state = item.optString("state", "idle"),
            done = item.optInt("done"),
            total = item.optInt("total"),
            success = item.optInt("success"),
            failed = item.optInt("failed"),
            skipped = item.optInt("skipped"),
            current = item.optString("current"),
        )
    }

    suspend fun loadAllowlist(): List<String> {
        val result = shell.run(RootShell.Command.AllowlistList)
        if (!result.ok) throw ModuleOperationException(result.output.ifBlank { "No se pudo leer la lista de excepciones." })
        val domains = JSONObject(result.output).optJSONArray("domains") ?: return emptyList()
        return buildList(domains.length()) {
            for (index in 0 until domains.length()) {
                val domain = domains.optString(index).trim()
                if (domain.isNotBlank()) add(domain)
            }
        }
    }

    suspend fun setActivityEnabled(enabled: Boolean): RootShell.Result =
        shell.run(if (enabled) RootShell.Command.ActivityEnable else RootShell.Command.ActivityDisable)

    suspend fun clearActivity(): RootShell.Result = shell.run(RootShell.Command.ActivityClear)

    suspend fun setCatalogEnabled(entry: CatalogEntry, enabled: Boolean): RootShell.Result =
        shell.run(if (enabled) RootShell.Command.CatalogEnable(entry.id) else RootShell.Command.CatalogDisable(entry.id))

    suspend fun startDownloadAll(): RootShell.Result = shell.run(RootShell.Command.CatalogDownloadAllStart)

    suspend fun addAllowlist(domain: String): RootShell.Result = shell.run(RootShell.Command.AllowlistAdd(domain))

    suspend fun removeAllowlist(domain: String): RootShell.Result = shell.run(RootShell.Command.AllowlistRemove(domain))

    suspend fun setProvider(provider: String, nextDnsId: String = ""): RootShell.Result {
        val configured = if (provider == "nextdns") {
            shell.run(RootShell.Command.SetNextDns(nextDnsId))
        } else {
            shell.run(RootShell.Command.SetProvider(provider))
        }
        if (!configured.ok) return configured

        val restarted = shell.run(RootShell.Command.Restart)
        if (!restarted.ok) {
            return restarted.copy(output = listOf(configured.output, restarted.output).filter { it.isNotBlank() }.joinToString("\n"))
        }
        return restarted
    }

    private fun parseEvents(raw: String): List<ActivityEvent> {
        val root = JSONObject(raw)
        val array = root.optJSONArray("events") ?: return emptyList()
        return buildList(array.length()) {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                add(
                    ActivityEvent(
                        time = item.optString("time"),
                        domain = item.optString("domain"),
                        status = item.optString("status", "allowed"),
                        rule = item.optString("rule"),
                        category = item.optString("category"),
                        returnCode = item.optString("return_code"),
                        duration = item.optString("duration"),
                    ),
                )
            }
        }
    }

    private fun parseStats(raw: String): ActivityStats {
        val item = JSONObject(raw)
        return ActivityStats(
            total = item.optInt("total"),
            blocked = item.optInt("blocked"),
            allowed = item.optInt("allowed"),
            allowlisted = item.optInt("allowlisted"),
            errors = item.optInt("errors"),
        )
    }
}

internal class RootBridgeException(message: String) : Exception(message)
internal class ModuleOperationException(message: String) : Exception(message)

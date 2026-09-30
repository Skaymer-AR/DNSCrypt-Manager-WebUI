package ar.skaymer.dnscryptmanager

import android.content.Context
import org.json.JSONObject
import java.net.InetAddress

internal class DnsCryptRepository(
    private val context: Context,
    private val shell: RootShell,
) {
    suspend fun loadSnapshot(): DashboardSnapshot {
        val statusResult = shell.run(RootShell.Command.Status)
        if (!statusResult.ok) {
            throw RootBridgeException(statusResult.output.ifBlank { context.getString(R.string.repo_module_state_error) })
        }

        val statusJson = JSONObject(statusResult.output)
        val activityStatus = shell.run(RootShell.Command.ActivityStatus)
        val activityJson = if (activityStatus.ok) JSONObject(activityStatus.output) else null
        val status = ModuleStatus(
            running = statusJson.optBoolean("running", false),
            listening = statusJson.optBoolean("listening", false),
            redirectActive = statusJson.optString("redirect") in setOf("activa", "active", "enabled"),
            moduleEnabled = !statusJson.optBoolean("disabled", false),
            server = statusJson.optString("server", ""),
            version = statusJson.optString("version", ""),
            activityEnabled = activityJson?.optBoolean("enabled", false) ?: false,
        )
        return DashboardSnapshot(
            status = status,
            activitySupported = activityStatus.ok,
            events = emptyList(),
            stats = ActivityStats(),
            activityRetentionDays = activityJson?.optInt("days", 1) ?: 1,
            activityMaxEntries = activityJson?.optInt("max_entries", 2000) ?: 2000,
        )
    }

    suspend fun testDns(): RootShell.Result = shell.run(RootShell.Command.TestDns)

    suspend fun loadActivitySnapshot(): ActivitySnapshotData {
        val result = shell.run(RootShell.Command.ActivitySnapshot(200))
        return ActivitySnapshotParser.parse(
            result,
            ActivitySnapshotMessages(
                invalidSuccess = context.getString(R.string.activity_snapshot_invalid_success),
                invalidFailure = context.getString(R.string.activity_snapshot_invalid_failure),
                timedOut = context.getString(R.string.activity_snapshot_timed_out),
            ),
        )
    }

    suspend fun runDiagnostics(): List<DiagnosticCheck> {
        val snapshot = loadSnapshot()
        val status = snapshot.status
        val checks = mutableListOf(
            DiagnosticCheck(
                context.getString(R.string.diag_root_module),
                if (status.moduleEnabled) "ok" else "attention",
                if (status.moduleEnabled) context.getString(R.string.diag_module_enabled, status.version.ifBlank { context.getString(R.string.common_not_available) })
                else context.getString(R.string.diag_module_disabled),
            ),
            DiagnosticCheck(
                context.getString(R.string.diag_proxy),
                if (status.running && status.listening) "ok" else "attention",
                if (status.running && status.listening) context.getString(R.string.diag_proxy_running)
                else context.getString(R.string.diag_proxy_not_ready),
            ),
            DiagnosticCheck(
                context.getString(R.string.diag_system_redirect),
                if (status.redirectActive) "ok" else "info",
                if (status.redirectActive) context.getString(R.string.diag_redirect_active)
                else context.getString(R.string.diag_redirect_inactive),
            ),
        )

        val dnsResult = testDns()
        checks += DiagnosticCheck(
            context.getString(R.string.diag_real_dns),
            if (dnsResult.ok) "ok" else "attention",
            if (dnsResult.ok) dnsResult.output.ifBlank { context.getString(R.string.diag_dns_success) }
            else dnsResult.output.ifBlank { context.getString(R.string.diag_dns_failed) },
        )

        val groups = try { loadCatalogGroups() } catch (_: Exception) { null }
        checks += if (groups == null) {
            DiagnosticCheck(context.getString(R.string.diag_dns_lists), "info", context.getString(R.string.diag_catalog_read_failed))
        } else {
            val active = groups.sumOf { it.active }
            val total = groups.sumOf { it.count }
            DiagnosticCheck(
                context.getString(R.string.diag_dns_lists),
                if (active > 0) "ok" else "info",
                if (active > 0) context.getString(R.string.diag_active_sources, active, total)
                else context.getString(R.string.diag_no_sources),
            )
        }

        val firewall = loadFirewallData()
        val support = firewall.support
        checks += when {
            support == null -> DiagnosticCheck(context.getString(R.string.diag_firewall_app), "info", firewall.error ?: context.getString(R.string.vmodel_firewall_support_error))
            support.supported -> DiagnosticCheck(context.getString(R.string.diag_firewall_app), "ok", context.getString(R.string.diag_firewall_supported))
            else -> DiagnosticCheck(
                context.getString(R.string.diag_firewall_app),
                "unsupported",
                context.getString(
                    R.string.diag_firewall_unsupported,
                    context.getString(if (support.ipv4Owner) R.string.common_yes else R.string.common_no),
                    context.getString(if (support.ipv6Owner) R.string.common_yes else R.string.common_no),
                ),
            )
        }
        return checks
    }

    suspend fun loadActivityStats(): ActivityStats {
        val result = shell.run(RootShell.Command.ActivityStats)
        if (!result.ok) throw ModuleOperationException(result.output.ifBlank { context.getString(R.string.activity_stats_read_error) })
        return parseStats(result.output)
    }

    suspend fun loadActivityEvents(): List<ActivityEvent> {
        val result = shell.run(RootShell.Command.ActivityList(200))
        if (!result.ok) throw ModuleOperationException(result.output.ifBlank { context.getString(R.string.activity_list_read_error) })
        return parseEvents(result.output)
    }

    suspend fun loadFirewallData(): FirewallData {
        val supportResult = shell.run(RootShell.Command.AppPolicySupport)
        val support = supportResult.output.takeIf { it.isNotBlank() }
            ?.let { raw -> runCatching { parseFirewallSupport(raw) }.getOrNull() }
        val policiesResult = shell.run(RootShell.Command.AppPolicyList)
        val blockedUids = if (policiesResult.ok) {
            runCatching { parseBlockedUids(policiesResult.output) }.getOrNull()
        } else null
        val temporaryRules = if (policiesResult.ok) {
            runCatching { parseTemporaryRules(policiesResult.output) }.getOrNull()
        } else null
        val profilesResult = shell.run(RootShell.Command.AppPolicyProfileList)
        val profiles = profilesResult.takeIf { it.ok }
            ?.let { raw -> runCatching { parseProfiles(raw.output) }.getOrNull() }
        val errors = listOfNotNull(
            supportResult.takeIf { support == null }?.output?.ifBlank { context.getString(R.string.firewall_verify_error) },
            policiesResult.takeIf { blockedUids == null }?.output?.ifBlank { context.getString(R.string.firewall_read_rules_error) },
            profilesResult.takeIf { profiles == null }?.output?.ifBlank { context.getString(R.string.firewall_read_profiles_error) },
        ).distinct()
        return FirewallData(
            support = support,
            blockedUids = blockedUids.orEmpty(),
            temporaryRules = temporaryRules.orEmpty(),
            profiles = profiles.orEmpty(),
            error = errors.takeIf { it.isNotEmpty() }?.joinToString("\n"),
        )
    }

    suspend fun blockApp(packageName: String): RootShell.Result =
        shell.run(RootShell.Command.AppPolicySet(packageName))

    suspend fun allowApp(packageName: String): RootShell.Result =
        shell.run(RootShell.Command.AppPolicyClear(packageName))

    suspend fun allowApps(packageNames: List<String>): RootShell.Result {
        var result = RootShell.Result(0, "")
        for (packageName in packageNames.distinct()) {
            result = shell.run(RootShell.Command.AppPolicyClear(packageName))
            if (!result.ok) return result
        }
        return result
    }

    suspend fun clearAllAppBlocks(): RootShell.Result = shell.run(RootShell.Command.AppPolicyClearAll)

    suspend fun blockAppTemporarily(packageName: String, duration: String): RootShell.Result =
        shell.run(RootShell.Command.AppPolicyTempBlock(packageName, duration))

    suspend fun saveFirewallProfile(name: String, packageNames: List<String>): RootShell.Result =
        shell.run(RootShell.Command.AppPolicyProfileSave(name, packageNames))

    suspend fun removeFirewallProfile(name: String): RootShell.Result =
        shell.run(RootShell.Command.AppPolicyProfileRemove(name))

    suspend fun loadConnections(): List<ConnectionEvent> {
        val result = shell.run(RootShell.Command.Connections)
        if (!result.ok) throw ModuleOperationException(result.output.ifBlank { context.getString(R.string.connections_read_error) })
        return parseConnections(result.output)
    }

    suspend fun setActivityRetention(days: Int, maxEntries: Int): RootShell.Result {
        val daysResult = shell.run(RootShell.Command.ActivityRetentionDays(days))
        if (!daysResult.ok) return daysResult
        val maxResult = shell.run(RootShell.Command.ActivityRetentionMax(maxEntries))
        if (!maxResult.ok) return maxResult
        return shell.run(RootShell.Command.ActivityPrune)
    }

    suspend fun createBackup(path: String): RootShell.Result = shell.run(RootShell.Command.BackupExport(path))

    suspend fun restoreBackup(path: String): RootShell.Result = shell.run(RootShell.Command.BackupRestore(path))

    suspend fun inspectBackup(path: String): BackupPreview {
        val result = shell.run(RootShell.Command.BackupInspect(path))
        if (!result.ok) throw ModuleOperationException(result.output.ifBlank { context.getString(R.string.backup_validate_file_error) })
        val item = JSONObject(result.output)
        if (!item.optBoolean("valid", false)) throw ModuleOperationException(context.getString(R.string.repo_backup_invalid))
        return BackupPreview(
            entryCount = item.optInt("entry_count"),
            savedSourceCount = item.optInt("saved_source_count"),
            hasDnsConfig = item.optBoolean("dns_config"),
            hasAllowlist = item.optBoolean("allowlist"),
            hasEnabledLists = item.optBoolean("enabled_lists"),
            hasCustomSources = item.optBoolean("custom_sources"),
            hasFirewallRules = item.optBoolean("firewall_rules"),
            hasFirewallProfiles = item.optBoolean("firewall_profiles"),
            includesActivity = item.optBoolean("activity_included", false),
        )
    }

    suspend fun loadCatalogGroups(): List<CatalogGroup> {
        val result = shell.run(RootShell.Command.CatalogGroups)
        if (!result.ok) throw ModuleOperationException(result.output.ifBlank { context.getString(R.string.catalog_open_error) })
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
        if (!result.ok) throw ModuleOperationException(result.output.ifBlank { context.getString(R.string.catalog_category_read_error) })
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
        if (!result.ok) throw ModuleOperationException(result.output.ifBlank { context.getString(R.string.download_progress_read_error) })
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
        if (!result.ok) throw ModuleOperationException(result.output.ifBlank { context.getString(R.string.allowlist_read_error) })
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

    suspend fun setCatalogGroupEnabled(group: String, enabled: Boolean): RootShell.Result =
        shell.run(RootShell.Command.CatalogGroupApply(group, enabled))

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
        return parseEvents(JSONObject(raw))
    }

    private fun parseEvents(root: JSONObject): List<ActivityEvent> {
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

    private fun parseStats(raw: String): ActivityStats = parseStats(JSONObject(raw))

    private fun parseStats(item: JSONObject): ActivityStats {
        return ActivityStats(
            total = item.optInt("total"),
            blocked = item.optInt("blocked"),
            allowed = item.optInt("allowed"),
            allowlisted = item.optInt("allowlisted"),
            errors = item.optInt("errors"),
            available = true,
        )
    }

    private fun parseFirewallSupport(raw: String): FirewallSupport {
        val item = JSONObject(raw)
        return FirewallSupport(
            supported = item.optBoolean("supported", false),
            active = item.optBoolean("active", false),
            ipv4Owner = item.optBoolean("ipv4_owner", false),
            ipv6Owner = item.optBoolean("ipv6_owner", false),
        )
    }

    private fun parseBlockedUids(raw: String): Set<Int> {
        val policies = JSONObject(raw).optJSONArray("policies") ?: return emptySet()
        return buildSet {
            for (index in 0 until policies.length()) {
                val item = policies.optJSONObject(index) ?: continue
                if (item.optString("policy") == "block-internet") {
                    val uid = item.optInt("uid", -1)
                    if (uid >= 10_000) add(uid)
                }
            }
        }
    }

    private fun parseTemporaryRules(raw: String): Map<String, Long> {
        val policies = JSONObject(raw).optJSONArray("policies") ?: return emptyMap()
        return buildMap {
            for (index in 0 until policies.length()) {
                val item = policies.optJSONObject(index) ?: continue
                val expires = item.optLong("expires_at", 0L)
                val packageName = item.optString("package")
                if (expires > 0L && packageName.isNotBlank()) put(packageName, expires)
            }
        }
    }

    private fun parseProfiles(raw: String): List<FirewallProfile> {
        val profiles = JSONObject(raw).optJSONArray("profiles") ?: return emptyList()
        return buildList(profiles.length()) {
            for (index in 0 until profiles.length()) {
                val item = profiles.optJSONObject(index) ?: continue
                val packages = item.optJSONArray("packages") ?: continue
                add(
                    FirewallProfile(
                        name = item.optString("name"),
                        packages = buildList(packages.length()) {
                            for (packageIndex in 0 until packages.length()) {
                                packages.optString(packageIndex).takeIf { it.isNotBlank() }?.let(::add)
                            }
                        },
                    ),
                )
            }
        }
    }

    private fun parseConnections(raw: String): List<ConnectionEvent> = raw.lineSequence()
        .mapNotNull { line ->
            val fields = line.trim().split('|')
            if (fields.size != 5) return@mapNotNull null
            val address = decodeProcAddress(fields[0], fields[1]) ?: return@mapNotNull null
            val port = fields[2].toIntOrNull(16) ?: return@mapNotNull null
            val uid = fields[3].toIntOrNull() ?: return@mapNotNull null
            ConnectionEvent(fields[0], address, port, uid, connectionState(fields[4]))
        }
        .take(300)
        .toList()

    private fun decodeProcAddress(protocol: String, hex: String): String? = runCatching {
        val isV6 = protocol.endsWith("v6")
        val byteCount = if (isV6) 16 else 4
        require(hex.length == byteCount * 2)
        val bytes = ByteArray(byteCount)
        if (isV6) {
            for (word in 0 until 4) {
                for (offset in 0 until 4) {
                    val sourceByte = word * 4 + (3 - offset)
                    bytes[word * 4 + offset] = hex.substring(sourceByte * 2, sourceByte * 2 + 2).toInt(16).toByte()
                }
            }
        } else {
            for (offset in 0 until 4) {
                val sourceByte = 3 - offset
                bytes[offset] = hex.substring(sourceByte * 2, sourceByte * 2 + 2).toInt(16).toByte()
            }
        }
        InetAddress.getByAddress(bytes).hostAddress
    }.getOrNull()

    private fun connectionState(code: String): String = when (code.uppercase()) {
        "01" -> context.getString(R.string.server_connected)
        "02", "03" -> context.getString(R.string.server_connecting)
        "04", "05", "06" -> context.getString(R.string.server_closing)
        "08" -> context.getString(R.string.server_remote_close)
        "09", "0B" -> context.getString(R.string.server_close_pending)
        "07" -> context.getString(R.string.server_closed)
        else -> context.getString(R.string.server_active)
    }
}

internal class RootBridgeException(message: String) : Exception(message)
internal class ModuleOperationException(message: String) : Exception(message)

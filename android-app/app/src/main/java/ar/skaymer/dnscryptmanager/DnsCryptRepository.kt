package ar.skaymer.dnscryptmanager

import org.json.JSONObject

internal class DnsCryptRepository(
    private val shell: RootShell = RootShell(),
) {
    suspend fun loadSnapshot(): DashboardSnapshot {
        val statusResult = shell.run(RootShell.Command.Status)
        if (!statusResult.ok) throw RootBridgeException(statusResult.output.ifBlank { "No se pudo leer el estado del módulo" })

        val statusJson = JSONObject(statusResult.output)
        val activityStatus = shell.run(RootShell.Command.ActivityStatus)
        val activityEnabled = activityStatus.ok && JSONObject(activityStatus.output).optBoolean("enabled", false)

        val eventsResult = if (activityStatus.ok) {
            shell.run(RootShell.Command.ActivityList(100))
        } else {
            RootShell.Result(1, "activity no disponible")
        }
        val statsResult = if (activityStatus.ok) {
            shell.run(RootShell.Command.ActivityStats)
        } else {
            RootShell.Result(1, "activity no disponible")
        }

        val status = ModuleStatus(
            running = statusJson.optBoolean("running", false),
            listening = statusJson.optBoolean("listening", false),
            redirectActive = statusJson.optString("redirect") in setOf("activa", "active", "enabled"),
            server = statusJson.optString("server", "-"),
            version = statusJson.optString("version", "-"),
            activityEnabled = activityEnabled,
        )
        return DashboardSnapshot(
            status = status,
            activitySupported = activityStatus.ok,
            events = if (eventsResult.ok) parseEvents(eventsResult.output) else emptyList(),
            stats = if (statsResult.ok) parseStats(statsResult.output) else ActivityStats(),
        )
    }

    suspend fun setActivityEnabled(enabled: Boolean): RootShell.Result =
        shell.run(if (enabled) RootShell.Command.ActivityEnable else RootShell.Command.ActivityDisable)

    suspend fun clearActivity(): RootShell.Result = shell.run(RootShell.Command.ActivityClear)

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


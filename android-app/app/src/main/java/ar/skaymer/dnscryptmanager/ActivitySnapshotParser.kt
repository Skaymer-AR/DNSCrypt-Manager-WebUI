package ar.skaymer.dnscryptmanager

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

/**
 * Decodes the single, bounded response returned by activity snapshot.
 *
 * RootShell merges stdout and stderr, so a valid JSON object with text appended
 * to it is deliberately rejected. A non-zero exit status alone is not enough
 * to discard a complete snapshot: older module builds could print the JSON and
 * then fail while removing temporary files.
 */
internal object ActivitySnapshotParser {
    private const val MAX_EVENTS = 200

    fun parse(result: RootShell.Result, messages: ActivitySnapshotMessages): ActivitySnapshotData {
        if (result.timedOut) throw ModuleOperationException(messages.timedOut)

        val root = try {
            val tokener = JSONTokener(result.output)
            val parsed = tokener.nextValue() as? JSONObject
                ?: throw IllegalArgumentException("snapshot root is not an object")
            require(tokener.nextClean() == '\u0000') { "trailing output after snapshot" }
            parsed
        } catch (_: Exception) {
            throw ModuleOperationException(failureMessage(result, messages))
        }

        return try {
            val enabled = root.requiredBoolean("enabled")
            val rawStats = root.optJSONObject("stats")
                ?: throw IllegalArgumentException("stats is missing")
            val stats = parseStats(rawStats)
            val rawEvents = root.optJSONArray("events")
                ?: throw IllegalArgumentException("events is missing")
            val events = parseEvents(rawEvents)
            validateSnapshot(stats, events)
            ActivitySnapshotData(enabled = enabled, stats = stats, events = events)
        } catch (_: Exception) {
            throw ModuleOperationException(failureMessage(result, messages))
        }
    }

    private fun parseStats(item: JSONObject): ActivityStats {
        require(item.requiredBoolean("available")) { "stats are unavailable" }
        return ActivityStats(
            total = item.requiredCount("total"),
            blocked = item.requiredCount("blocked"),
            allowed = item.requiredCount("allowed"),
            allowlisted = item.requiredCount("allowlisted"),
            errors = item.requiredCount("errors"),
            available = true,
        )
    }

    private fun parseEvents(array: JSONArray): List<ActivityEvent> {
        require(array.length() <= MAX_EVENTS) { "too many activity events" }
        return buildList(array.length()) {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index)
                    ?: throw IllegalArgumentException("event $index is not an object")
                val time = item.requiredString("time")
                val domain = item.requiredString("domain")
                val status = item.requiredString("status")
                require(time.isNotBlank() && domain.isNotBlank()) { "event identity is missing" }
                require(status in EVENT_STATUSES) { "unknown event status" }

                // These fields are part of the module's snapshot contract even
                // though the current activity row does not display all of them.
                val rule = item.requiredString("rule")
                val category = item.requiredString("category")
                val returnCode = item.requiredString("return_code")
                val duration = item.requiredString("duration")
                item.requiredString("query_type")
                item.requiredString("server")
                item.requiredString("relay")
                add(
                    ActivityEvent(
                        time = time,
                        domain = domain,
                        status = status,
                        rule = rule,
                        category = category,
                        returnCode = returnCode,
                        duration = duration,
                    ),
                )
            }
        }
    }

    private fun validateSnapshot(stats: ActivityStats, events: List<ActivityEvent>) {
        require(stats.total.toLong() == stats.blocked.toLong() + stats.allowed + stats.allowlisted + stats.errors) {
            "activity counters do not add up"
        }
        require(events.size == minOf(stats.total, MAX_EVENTS)) { "activity event window is incomplete" }
        require(events.count { it.status == "blocked" } <= stats.blocked)
        require(events.count { it.status == "allowed" } <= stats.allowed)
        require(events.count { it.status == "allowlisted" } <= stats.allowlisted)
        require(events.count { it.status == "error" } <= stats.errors)
    }

    private fun JSONObject.requiredBoolean(key: String): Boolean =
        opt(key) as? Boolean ?: throw IllegalArgumentException("$key is missing or is not boolean")

    private fun JSONObject.requiredCount(key: String): Int {
        val number = opt(key) as? Number
            ?: throw IllegalArgumentException("$key is missing or is not numeric")
        val value = number.toDouble()
        require(value.isFinite() && value >= 0.0 && value <= Int.MAX_VALUE.toDouble() && value % 1.0 == 0.0) {
            "$key is not a non-negative integer"
        }
        return value.toInt()
    }

    private fun JSONObject.requiredString(key: String): String =
        opt(key) as? String ?: throw IllegalArgumentException("$key is missing or is not text")

    private fun failureMessage(result: RootShell.Result, messages: ActivitySnapshotMessages): String {
        val fallback = if (result.ok) messages.invalidSuccess else messages.invalidFailure
        val firstLine = result.output.lineSequence().firstOrNull().orEmpty().trim()
        if (firstLine.isBlank() || firstLine.startsWith("{") || firstLine.startsWith("[") ||
            firstLine.contains('{') || firstLine.contains('[')
        ) {
            return fallback
        }
        return firstLine.take(180).ifBlank { fallback }
    }

    private val EVENT_STATUSES = setOf("blocked", "allowed", "allowlisted", "error")
}

internal data class ActivitySnapshotMessages(
    val invalidSuccess: String,
    val invalidFailure: String,
    val timedOut: String,
)

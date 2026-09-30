package ar.skaymer.dnscryptmanager

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ActivitySnapshotParserTest {
    @Test
    fun acceptsCompleteSnapshotWithSuccessfulExit() {
        val snapshot = ActivitySnapshotParser.parse(RootShell.Result(0, VALID_RESPONSE))

        assertTrue(snapshot.enabled)
        assertTrue(snapshot.stats.available)
        assertEquals(2, snapshot.stats.total)
        assertEquals(1, snapshot.stats.blocked)
        assertEquals(2, snapshot.events.size)
        assertEquals("blocked", snapshot.events[0].status)
        assertEquals("tracker.example", snapshot.events[0].domain)
    }

    @Test
    fun acceptsCompleteSnapshotWhenCleanupReturnsNonZeroAfterJson() {
        val snapshot = ActivitySnapshotParser.parse(RootShell.Result(1, largeSnapshotResponse()))

        assertEquals(7_482, snapshot.stats.total)
        assertEquals(200, snapshot.events.size)
    }

    @Test
    fun acceptsTheFullTwoHundredEventWindowForLargeCounters() {
        val snapshot = ActivitySnapshotParser.parse(RootShell.Result(0, largeSnapshotResponse()))

        assertEquals(7_482, snapshot.stats.total)
        assertEquals(200, snapshot.events.size)
    }

    @Test
    fun rejectsTruncatedAndInvalidJsonWithShortMessage() {
        assertInvalid("{\"enabled\":true,\"stats\":{\"available\":true")
        assertInvalid("esto no es JSON")
    }

    @Test
    fun rejectsMissingCountersAndDoesNotInventZeroValues() {
        val missingCounter = VALID_RESPONSE.replace("\"errors\":2", "\"other\":2")
        assertInvalid(missingCounter)
    }

    @Test
    fun rejectsSyntacticallyValidSnapshotsWithPartialEventWindows() {
        val partialSmallWindow = JSONObject(VALID_RESPONSE).apply {
            getJSONObject("stats").put("total", 3).put("allowed", 2)
        }
        assertInvalid(partialSmallWindow.toString())

        val partialLargeWindow = JSONObject(largeSnapshotResponse()).apply {
            val fullEvents = getJSONArray("events")
            val missingLastEvent = JSONArray()
            repeat(fullEvents.length() - 1) { index -> missingLastEvent.put(fullEvents.getJSONObject(index)) }
            put("events", missingLastEvent)
        }
        assertInvalid(partialLargeWindow.toString())
    }

    @Test
    fun rejectsMissingRequiredSnapshotOrEventFields() {
        assertInvalid(VALID_RESPONSE.replace("\"events\":[", "\"items\":["))
        assertInvalid(VALID_RESPONSE.replace(",\"server\":\"cloudflare\"", ""))
    }

    @Test
    fun rejectsInconsistentCountersAndAppendedStderrText() {
        assertInvalid(VALID_RESPONSE.replace("\"total\":2", "\"total\":0"))
        assertInvalid("$VALID_RESPONSE\nrm: cannot remove temporary file")
    }

    @Test
    fun doesNotAcceptAValidLookingSnapshotAfterTimeout() {
        assertInvalid(VALID_RESPONSE, timedOut = true)
    }

    private fun assertInvalid(
        output: String,
        timedOut: Boolean = false,
    ) {
        val error = try {
            ActivitySnapshotParser.parse(RootShell.Result(1, output, timedOut))
            throw AssertionError("Invalid snapshot was accepted")
        } catch (expected: ModuleOperationException) {
            expected
        }
        val message = error.message ?: throw AssertionError("The parser returned an empty error")
        assertTrue(message.length < 200)
        assertFalse(message.contains("{"))
        assertFalse(message.contains("tracker.example"))
    }

    private fun largeSnapshotResponse(): String {
        val root = JSONObject(VALID_RESPONSE)
        root.getJSONObject("stats")
            .put("total", 7_482)
            .put("blocked", 7_200)
            .put("allowed", 270)
            .put("allowlisted", 10)
            .put("errors", 2)
        val events = JSONArray()
        repeat(200) { index ->
            val status = if (index % 2 == 0) "blocked" else "allowed"
            events.put(
                JSONObject()
                    .put("time", "[2026-09-29 18:00:00]")
                    .put("domain", "query-$index.example")
                    .put("status", status)
                    .put("rule", if (status == "blocked") "query-$index.example" else "")
                    .put("category", "")
                    .put("query_type", "A")
                    .put("return_code", "NOERROR")
                    .put("duration", "1ms")
                    .put("server", "cloudflare")
                    .put("relay", "-"),
            )
        }
        root.put("events", events)
        return root.toString()
    }

    private companion object {
        val VALID_RESPONSE = """{"enabled":true,"stats":{"available":true,"total":2,"blocked":1,"allowed":1,"allowlisted":0,"errors":0},"events":[{"time":"[2026-09-29 18:00:00]","domain":"tracker.example","status":"blocked","rule":"tracker.example","category":"","query_type":"A","return_code":"NOERROR","duration":"1ms","server":"cloudflare","relay":"-"},{"time":"[2026-09-29 17:59:59]","domain":"clear.example","status":"allowed","rule":"","category":"","query_type":"AAAA","return_code":"NOERROR","duration":"2ms","server":"cloudflare","relay":"-"}]}"""
    }
}

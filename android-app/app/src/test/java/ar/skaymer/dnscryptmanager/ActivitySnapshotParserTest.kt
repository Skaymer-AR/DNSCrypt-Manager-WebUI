package ar.skaymer.dnscryptmanager

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
        assertEquals(7_482, snapshot.stats.total)
        assertEquals(7_200, snapshot.stats.blocked)
        assertEquals(2, snapshot.events.size)
        assertEquals("blocked", snapshot.events[0].status)
        assertEquals("tracker.example", snapshot.events[0].domain)
    }

    @Test
    fun acceptsCompleteSnapshotWhenCleanupReturnsNonZeroAfterJson() {
        val snapshot = ActivitySnapshotParser.parse(RootShell.Result(1, VALID_RESPONSE))

        assertEquals(7_482, snapshot.stats.total)
        assertEquals(2, snapshot.events.size)
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
    fun rejectsMissingRequiredSnapshotOrEventFields() {
        assertInvalid(VALID_RESPONSE.replace("\"events\":[", "\"items\":["))
        assertInvalid(VALID_RESPONSE.replace(",\"server\":\"cloudflare\"", ""))
    }

    @Test
    fun rejectsInconsistentCountersAndAppendedStderrText() {
        assertInvalid(VALID_RESPONSE.replace("\"total\":7482", "\"total\":0"))
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

    private companion object {
        val VALID_RESPONSE = """{"enabled":true,"stats":{"available":true,"total":7482,"blocked":7200,"allowed":270,"allowlisted":10,"errors":2},"events":[{"time":"[2026-09-29 18:00:00]","domain":"tracker.example","status":"blocked","rule":"tracker.example","category":"","query_type":"A","return_code":"NOERROR","duration":"1ms","server":"cloudflare","relay":"-"},{"time":"[2026-09-29 17:59:59]","domain":"clear.example","status":"allowed","rule":"","category":"","query_type":"AAAA","return_code":"NOERROR","duration":"2ms","server":"cloudflare","relay":"-"}]}"""
    }
}

package ar.skaymer.dnscryptmanager

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNotSame
import org.junit.Test

class BackgroundParsingTest {
    @Test
    fun parserWorkRunsAwayFromTheCallingUiThread() {
        val callingThread = Thread.currentThread()
        val parsingThread = runBlocking {
            parseOffMain { Thread.currentThread() }
        }

        assertNotSame(callingThread, parsingThread)
    }
}

package ar.skaymer.dnscryptmanager

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Run CPU-heavy response decoding away from Compose's main thread. */
internal suspend fun <T> parseOffMain(block: () -> T): T =
    withContext(Dispatchers.Default) { block() }

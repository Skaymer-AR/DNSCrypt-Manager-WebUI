package ar.skaymer.dnscryptmanager

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

/**
 * Root bridge deliberately limited to the module CLI.
 *
 * The app never accepts a free-form shell command. Every operation below is a
 * fixed verb/argument tuple, and the CLI path list is fixed as well. This is
 * the native equivalent of the WebUI command allowlist.
 */
internal class RootShell {
    data class Result(
        val exitCode: Int,
        val output: String,
        val timedOut: Boolean = false,
    ) {
        val ok: Boolean get() = exitCode == 0 && !timedOut
    }

    sealed interface Command {
        val args: List<String>

        data object Status : Command { override val args = listOf("status", "--json") }
        data object ActivityStatus : Command { override val args = listOf("activity", "status", "--json") }
        data class ActivityList(val limit: Int = 100) : Command {
            init { require(limit in 1..200) }
            override val args = listOf("activity", "list", "--limit", limit.toString(), "--json")
        }
        data object ActivityStats : Command { override val args = listOf("activity", "stats", "--json") }
        data object ActivityEnable : Command { override val args = listOf("activity", "enable") }
        data object ActivityDisable : Command { override val args = listOf("activity", "disable") }
        data object ActivityClear : Command { override val args = listOf("activity", "clear") }
        data object CatalogList : Command { override val args = listOf("catalog", "list", "--json") }
        data object BlocklistsStatus : Command { override val args = listOf("blocklists", "status", "--json") }
        data object AllowlistList : Command { override val args = listOf("allowlist", "list", "--json") }
        data object Restart : Command { override val args = listOf("restart") }
    }

    suspend fun run(command: Command): Result = withContext(Dispatchers.IO) {
        val script = buildScript(command.args)
        val process = try {
            ProcessBuilder("su", "-c", script)
                .redirectErrorStream(true)
                .start()
        } catch (error: Exception) {
            return@withContext Result(127, error.message ?: "No se pudo iniciar su")
        }

        val finished = process.waitFor(15, TimeUnit.SECONDS)
        if (!finished) {
            process.destroyForcibly()
            return@withContext Result(-1, "Tiempo de espera agotado", timedOut = true)
        }
        val output = process.inputStream.bufferedReader().use { it.readText() }.trim()
        Result(process.exitValue(), output)
    }

    private fun buildScript(args: List<String>): String {
        val paths = listOf(
            "/system/bin/dnscrypt-manager",
            "/data/adb/modules/dnscrypt_manager/system/bin/dnscrypt-manager",
            "/data/adb/modules_update/dnscrypt_manager/system/bin/dnscrypt-manager",
        )
        val pathList = paths.joinToString(" ") { shellQuote(it) }
        val quotedArgs = args.joinToString(" ") { shellQuote(it) }
        return "for p in $pathList; do [ -x \"\$p\" ] && exec \"\$p\" $quotedArgs; done; exit 127"
    }

    private fun shellQuote(value: String): String =
        "'${value.replace("'", "'\"'\"'")}'"
}


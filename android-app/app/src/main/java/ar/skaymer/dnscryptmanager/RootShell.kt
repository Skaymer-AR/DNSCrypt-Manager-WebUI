package ar.skaymer.dnscryptmanager

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.util.concurrent.TimeUnit

/**
 * Puente root cerrado a operaciones concretas del CLI del módulo.
 * No acepta comandos libres ni construye shell con texto escrito por el usuario.
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
        val timeoutSeconds: Long get() = 30

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

        data object CatalogGroups : Command { override val args = listOf("catalog", "groups", "--json") }
        data class CatalogList(val group: String) : Command {
            init { require(group in CATALOG_GROUPS) }
            override val args = listOf("catalog", "list", "--json", "--source-group", group)
            override val timeoutSeconds = 60L
        }
        data class CatalogEnable(val id: String) : Command {
            init { require(validCatalogId(id)) }
            override val args = listOf("catalog", "enable", id)
            override val timeoutSeconds = 180L
        }
        data class CatalogDisable(val id: String) : Command {
            init { require(validCatalogId(id)) }
            override val args = listOf("catalog", "disable", id)
            override val timeoutSeconds = 180L
        }
        data object CatalogDownloadAllStart : Command {
            override val args = listOf("catalog", "download-all", "--confirmed")
            override val timeoutSeconds = 30L
        }
        data object CatalogDownloadAllStatus : Command {
            override val args = listOf("catalog", "download-all", "status", "--json")
        }

        data object AllowlistList : Command { override val args = listOf("allowlist", "list", "--json") }
        data class AllowlistAdd(val domain: String) : Command {
            init { require(validDomain(domain)) }
            override val args = listOf("allowlist", "add", domain.lowercase())
            override val timeoutSeconds = 45L
        }
        data class AllowlistRemove(val domain: String) : Command {
            init { require(validDomain(domain)) }
            override val args = listOf("allowlist", "remove", domain.lowercase())
            override val timeoutSeconds = 45L
        }

        data class SetProvider(val provider: String) : Command {
            init { require(provider in PROVIDERS) }
            override val args = listOf("provider", provider)
        }
        data class SetNextDns(val id: String) : Command {
            init { require(NEXTDNS_ID.matches(id)) }
            override val args = listOf("nextdns", id.lowercase())
        }
        data object Restart : Command {
            override val args = listOf("restart")
            override val timeoutSeconds = 50L
        }
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

        // Consumir stdout mientras corre el proceso evita bloquear el CLI si el JSON
        // supera el buffer de la tubería. El timeout sigue limitando cada comando.
        val outputReader = async(Dispatchers.IO) {
            process.inputStream.bufferedReader().use { it.readText() }.trim()
        }
        val finished = process.waitFor(command.timeoutSeconds, TimeUnit.SECONDS)
        if (!finished) {
            process.destroyForcibly()
            val partialOutput = runCatching { withTimeout(3_000) { outputReader.await() } }.getOrDefault("")
            return@withContext Result(
                -1,
                listOf(partialOutput, "Se agotó el tiempo de espera.").filter { it.isNotBlank() }.joinToString("\n"),
                timedOut = true,
            )
        }
        val output = runCatching { outputReader.await() }.getOrElse { "No se pudo leer la respuesta del módulo." }
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

    private companion object {
        val CATALOG_GROUPS = setOf("Security", "Privacy", "ParentalControl", "dcm", "RethinkUnassigned")
        val PROVIDERS = setOf("cloudflare", "quad9", "adguard", "mullvad")
        val NEXTDNS_ID = Regex("^[0-9a-fA-F]{4,12}$")
        val CATALOG_ID = Regex("^[a-z0-9][a-z0-9_-]{0,127}$")
        val DOMAIN = Regex("^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")

        fun validCatalogId(id: String): Boolean = CATALOG_ID.matches(id)

        fun validDomain(domain: String): Boolean = DOMAIN.matches(domain.lowercase()) &&
            !Regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$").matches(domain)
    }
}

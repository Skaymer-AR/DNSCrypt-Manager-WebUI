package ar.skaymer.dnscryptmanager

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Puente root cerrado a operaciones concretas del CLI del módulo.
 * No acepta comandos libres ni construye shell con texto escrito por el usuario.
 */
internal class RootShell(private val context: Context, private val tempDirectory: File) {
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

        data object Status : Command {
            override val args = listOf("status", "--json")
            override val timeoutSeconds = 20L
        }
        data object TestDns : Command {
            override val args = listOf("test-dns")
            override val timeoutSeconds = 120L
        }
        data object ActivityStatus : Command {
            override val args = listOf("activity", "status", "--json")
            override val timeoutSeconds = 10L
        }
        data class ActivityList(val limit: Int = 200) : Command {
            init { require(limit in 1..200) }
            override val args = listOf("activity", "list", "--limit", limit.toString(), "--json")
            override val timeoutSeconds = 45L
        }
        data object ActivityStats : Command {
            override val args = listOf("activity", "stats", "--json")
            override val timeoutSeconds = 45L
        }
        data class ActivitySnapshot(val limit: Int = 200) : Command {
            init { require(limit in 1..200) }
            override val args = listOf("activity", "snapshot", "--limit", limit.toString(), "--json")
            override val timeoutSeconds = 30L
        }
        data object ActivityEnable : Command { override val args = listOf("activity", "enable") }
        data object ActivityDisable : Command { override val args = listOf("activity", "disable") }
        data object ActivityClear : Command { override val args = listOf("activity", "clear") }
        data class ActivityRetentionDays(val days: Int) : Command {
            init { require(days in setOf(1, 3, 7)) }
            override val args = listOf("set-flag", "query_days", days.toString())
        }
        data class ActivityRetentionMax(val entries: Int) : Command {
            init { require(entries in 50..10_000) }
            override val args = listOf("set-flag", "query_max", entries.toString())
        }
        data object ActivityPrune : Command { override val args = listOf("activity", "prune") }

        data object AppPolicySupport : Command {
            override val args = listOf("app-policy", "support", "--json")
            override val timeoutSeconds = 20L
        }
        data object AppPolicyList : Command {
            override val args = listOf("app-policy", "list", "--json")
            override val timeoutSeconds = 20L
        }
        data class AppPolicySet(val packageName: String) : Command {
            init { require(validPackageName(packageName)) }
            override val args = listOf("app-policy", "set", packageName, "block-internet")
            override val timeoutSeconds = 30L
        }
        data class AppPolicyClear(val packageName: String) : Command {
            init { require(validPackageName(packageName)) }
            override val args = listOf("app-policy", "clear", packageName)
            override val timeoutSeconds = 30L
        }
        data object AppPolicyClearAll : Command {
            override val args = listOf("app-policy", "clear-all")
            override val timeoutSeconds = 30L
        }
        data class AppPolicyTempBlock(val packageName: String, val duration: String) : Command {
            init { require(validPackageName(packageName)); require(duration in setOf("15m", "1h", "8h")) }
            override val args = listOf("app-policy", "temp-block", packageName, duration)
            override val timeoutSeconds = 30L
        }
        data object AppPolicyProfileList : Command {
            override val args = listOf("app-policy", "profile", "list", "--json")
        }
        data class AppPolicyProfileSave(val name: String, val packageNames: List<String>) : Command {
            init {
                require(name.matches(Regex("^[A-Za-z0-9][A-Za-z0-9 _-]{0,31}$")))
                require(!name.endsWith(" ") && !name.contains("  "))
                require(packageNames.size <= 200 && packageNames.all(::validPackageName))
            }
            override val args = listOf("app-policy", "profile", "save", name, packageNames.distinct().joinToString(","))
        }
        data class AppPolicyProfileRemove(val name: String) : Command {
            init { require(name.matches(Regex("^[A-Za-z0-9][A-Za-z0-9 _-]{0,31}$"))); require(!name.endsWith(" ") && !name.contains("  ")) }
            override val args = listOf("app-policy", "profile", "remove", name)
        }
        data object Connections : Command {
            override val args = listOf("connections")
            override val timeoutSeconds = 15L
        }
        data class BackupExport(val outputPath: String) : Command {
            init { require(isAppCacheName(outputPath)) }
            override val args = listOf("backup", "--output", outputPath)
            override val timeoutSeconds = 120L
        }
        data class BackupRestore(val inputPath: String) : Command {
            init { require(isAppCacheName(inputPath)) }
            override val args = listOf("restore-app-backup", inputPath)
            override val timeoutSeconds = 180L
        }
        data class BackupInspect(val inputPath: String) : Command {
            init { require(isAppCacheName(inputPath)) }
            override val args = listOf("backup", "inspect", "--input", inputPath)
            override val timeoutSeconds = 60L
        }

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
        data class CatalogGroupApply(val group: String, val enabled: Boolean) : Command {
            init { require(group in CATALOG_GROUPS) }
            override val args = listOf("catalog", "group", if (enabled) "enable" else "disable", group)
            override val timeoutSeconds = 600L
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
        data class DomainRule(val domain: String, val allow: Boolean) : Command {
            init { require(validDomain(domain)) }
            override val args = listOf("catalog", "domain-rule", if (allow) "allow" else "block", domain.lowercase())
            override val timeoutSeconds = 600L
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
        val artifactPath = when (command) {
            is Command.BackupExport -> command.outputPath
            is Command.BackupRestore -> command.inputPath
            is Command.BackupInspect -> command.inputPath
            else -> null
        }
        if (artifactPath != null && !isAppCacheArtifact(artifactPath)) {
            return@withContext Result(2, context.getString(R.string.root_backup_path_invalid))
        }
        val script = buildScript(command.args)
        val outputFile = try {
            File.createTempFile("dcm-root-", ".out", tempDirectory)
        } catch (error: Exception) {
            return@withContext Result(126, error.message ?: context.getString(R.string.root_temp_create_failed))
        }
        val process = try {
            ProcessBuilder("su", "-c", script)
                .redirectErrorStream(true)
                .redirectOutput(outputFile)
                .start()
        } catch (error: Exception) {
            outputFile.delete()
            return@withContext Result(127, error.message ?: context.getString(R.string.root_shell_start_failed))
        }
        runCatching { process.outputStream.close() }
        try {
            val finished = process.waitFor(command.timeoutSeconds, TimeUnit.SECONDS)
            if (!finished) {
                process.destroyForcibly()
                runCatching { process.waitFor(2, TimeUnit.SECONDS) }
                val partialOutput = readOutput(outputFile)
                return@withContext Result(
                    -1,
                    listOf(partialOutput.orEmpty(), context.getString(R.string.root_command_timed_out))
                        .filter { it.isNotBlank() }
                        .joinToString("\n"),
                    timedOut = true,
                )
            }
            if (outputFile.length() > MAX_OUTPUT_BYTES) {
                return@withContext Result(-1, context.getString(R.string.root_output_too_large))
            }
            Result(process.exitValue(), readOutput(outputFile))
        } catch (cancelled: CancellationException) {
            process.destroyForcibly()
            throw cancelled
        } catch (interrupted: InterruptedException) {
            process.destroyForcibly()
            currentCoroutineContext().ensureActive()
            Result(-1, context.getString(R.string.root_command_interrupted), timedOut = true)
        } catch (error: Exception) {
            process.destroyForcibly()
            Result(-1, error.message ?: context.getString(R.string.root_output_read_failed))
        } finally {
            outputFile.delete()
        }
    }

    private fun readOutput(file: File): String {
        if (file.length() > MAX_OUTPUT_BYTES) return context.getString(R.string.root_output_too_large)
        return runCatching { file.readText(Charsets.UTF_8).trim() }
            .getOrElse { context.getString(R.string.root_output_read_error, it.message.orEmpty()) }
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

    private fun isAppCacheArtifact(path: String): Boolean = runCatching {
        val file = File(path)
        isAppCacheName(path) &&
            file.parentFile?.canonicalFile == tempDirectory.canonicalFile
    }.getOrDefault(false)

    private companion object {
        val CATALOG_GROUPS = setOf("Security", "Privacy", "ParentalControl", "dcm", "RethinkUnassigned")
        val PROVIDERS = setOf("cloudflare", "quad9", "adguard", "mullvad")
        val NEXTDNS_ID = Regex("^[0-9a-fA-F]{4,12}$")
        val PACKAGE_NAME = Regex("^[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+$")
        const val MAX_OUTPUT_BYTES = 16L * 1024L * 1024L
        fun isAppCacheName(path: String): Boolean = File(path).name.matches(Regex("^dcm-backup-[A-Za-z0-9-]+\\.tar\\.gz$"))
        val CATALOG_ID = Regex("^[a-z0-9][a-z0-9_-]{0,127}$")
        val DOMAIN = Regex("^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")

        fun validCatalogId(id: String): Boolean = CATALOG_ID.matches(id)

        fun validPackageName(value: String): Boolean = PACKAGE_NAME.matches(value)

        fun validDomain(domain: String): Boolean = DOMAIN.matches(domain.lowercase()) &&
            !Regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$").matches(domain)
    }
}

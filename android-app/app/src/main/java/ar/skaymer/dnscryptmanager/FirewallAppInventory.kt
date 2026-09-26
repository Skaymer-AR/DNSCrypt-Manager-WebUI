package ar.skaymer.dnscryptmanager

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager

/**
 * Lists launchable user apps by Linux UID. Shared-UID packages are grouped because
 * the kernel firewall blocks a UID, so one switch can affect every package in it.
 */
internal object FirewallAppInventory {
    fun load(context: Context): List<FirewallApp> {
        val packageManager = context.packageManager
        val applications = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
        return applications
            .asSequence()
            .filter { it.uid >= 10_000 }
            .groupBy { it.uid }
            .mapNotNull { (uid, group) ->
                // Do not expose a toggle if it could also affect a system package or this app.
                if (group.any { it.packageName == context.packageName || it.isSystemPackage() }) return@mapNotNull null
                val launchable = group.filter { packageManager.getLaunchIntentForPackage(it.packageName) != null }
                if (launchable.isEmpty()) return@mapNotNull null
                val names = group.map { appInfo ->
                    appInfo.packageName to runCatching { appInfo.loadLabel(packageManager).toString().trim() }
                        .getOrNull()
                        .orEmpty()
                        .ifBlank { appInfo.packageName }
                }.distinctBy { it.first }.sortedBy { it.second.lowercase() }
                val selectedPackage = launchable.minByOrNull { it.packageName } ?: return@mapNotNull null
                val primaryName = names.firstOrNull { it.first == selectedPackage.packageName }?.second
                    ?: selectedPackage.packageName
                FirewallApp(
                    uid = uid,
                    packageName = selectedPackage.packageName,
                    label = primaryName,
                    packageNames = names.map { it.first },
                    sharedLabels = names.filterNot { it.first == selectedPackage.packageName }.map { it.second },
                )
            }
            .sortedBy { it.label.lowercase() }
    }

    private fun ApplicationInfo.isSystemPackage(): Boolean {
        val systemFlags = ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP
        return flags and systemFlags != 0
    }
}

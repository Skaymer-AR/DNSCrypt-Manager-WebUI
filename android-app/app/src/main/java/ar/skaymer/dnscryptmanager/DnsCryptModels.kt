package ar.skaymer.dnscryptmanager

data class ModuleStatus(
    val running: Boolean,
    val listening: Boolean,
    val redirectActive: Boolean,
    val moduleEnabled: Boolean,
    val server: String,
    val version: String,
    val activityEnabled: Boolean,
)

data class ActivityEvent(
    val time: String,
    val domain: String,
    val status: String,
    val rule: String,
    val category: String,
    val returnCode: String,
    val duration: String,
)

data class ActivityStats(
    val total: Int = 0,
    val blocked: Int = 0,
    val allowed: Int = 0,
    val allowlisted: Int = 0,
    val errors: Int = 0,
    val available: Boolean = false,
)

data class CatalogGroup(
    val key: String,
    val count: Int,
    val active: Int,
)

data class CatalogEntry(
    val id: String,
    val name: String,
    val sourceName: String,
    val sourceGroup: String,
    val subgroup: String,
    val categories: String,
    val aggressiveness: String,
    val license: String,
    val upstreamStatus: String,
    val runtimeStatus: String,
    val recommended: Boolean,
    val archived: Boolean,
    val enabled: Boolean,
    val activationBlocked: Boolean,
    val domainCount: String,
)

data class DownloadProgress(
    val state: String = "idle",
    val done: Int = 0,
    val total: Int = 0,
    val success: Int = 0,
    val failed: Int = 0,
    val skipped: Int = 0,
    val current: String = "",
) {
    val running: Boolean get() = state == "queued" || state == "running"
}

data class DashboardSnapshot(
    val status: ModuleStatus,
    val activitySupported: Boolean,
    val events: List<ActivityEvent>,
    val stats: ActivityStats,
)

data class FirewallSupport(
    val supported: Boolean,
    val active: Boolean,
    val ipv4Owner: Boolean,
    val ipv6Owner: Boolean,
)

data class FirewallData(
    val support: FirewallSupport?,
    val blockedUids: Set<Int>,
    val error: String? = null,
)

data class FirewallApp(
    val uid: Int,
    val packageName: String,
    val label: String,
    val packageNames: List<String> = listOf(packageName),
    val sharedLabels: List<String> = emptyList(),
)

data class DnsCryptUiState(
    val loading: Boolean = true,
    val rootAvailable: Boolean = true,
    val snapshot: DashboardSnapshot? = null,
    val activityLoading: Boolean = false,
    val activityError: String? = null,
    val error: String? = null,
    val notice: String? = null,
    val busyAction: String? = null,
    val catalogGroups: List<CatalogGroup> = emptyList(),
    val catalogEntries: List<CatalogEntry> = emptyList(),
    val selectedCatalogGroup: String = "Security",
    val catalogLoading: Boolean = false,
    val catalogLoaded: Boolean = false,
    val downloadProgress: DownloadProgress = DownloadProgress(),
    val allowlist: List<String> = emptyList(),
    val allowlistLoading: Boolean = false,
    val firewall: FirewallSupport? = null,
    val firewallBlockedUids: Set<Int> = emptySet(),
    val firewallLoading: Boolean = false,
    val firewallError: String? = null,
)

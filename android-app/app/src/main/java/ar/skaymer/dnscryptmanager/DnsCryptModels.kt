package ar.skaymer.dnscryptmanager

data class ModuleStatus(
    val running: Boolean,
    val listening: Boolean,
    val redirectActive: Boolean,
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
)

data class DashboardSnapshot(
    val status: ModuleStatus,
    val activitySupported: Boolean,
    val events: List<ActivityEvent>,
    val stats: ActivityStats,
)

data class DnsCryptUiState(
    val loading: Boolean = true,
    val rootAvailable: Boolean = true,
    val snapshot: DashboardSnapshot? = null,
    val error: String? = null,
)


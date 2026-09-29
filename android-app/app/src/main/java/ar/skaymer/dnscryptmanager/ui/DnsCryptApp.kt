package ar.skaymer.dnscryptmanager.ui

import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.List
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TriStateCheckbox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.state.ToggleableState
import androidx.lifecycle.viewmodel.compose.viewModel
import ar.skaymer.dnscryptmanager.ActivityEvent
import ar.skaymer.dnscryptmanager.CatalogEntry
import ar.skaymer.dnscryptmanager.DnsCryptUiState
import ar.skaymer.dnscryptmanager.DnsCryptViewModel
import ar.skaymer.dnscryptmanager.DiagnosticCheck
import ar.skaymer.dnscryptmanager.ConnectionEvent
import ar.skaymer.dnscryptmanager.FirewallProfile
import ar.skaymer.dnscryptmanager.FirewallApp
import ar.skaymer.dnscryptmanager.FirewallAppInventory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

private enum class Tab(val label: String) {
    HOME("Inicio"),
    ACTIVITY("Actividad"),
    FIREWALL("Firewall"),
    LISTS("Listas"),
    SETTINGS("Ajustes"),
}

@Composable
internal fun DnsCryptApp(viewModel: DnsCryptViewModel = viewModel()) {
    val state by viewModel.state.collectAsState()
    var tab by rememberSaveable { mutableStateOf(Tab.HOME.name) }
    var connectionMode by rememberSaveable { mutableStateOf(false) }
    val currentTab = Tab.valueOf(tab)
    val snackbar = remember { SnackbarHostState() }

    LaunchedEffect(state.error, state.notice, state.rootAvailable, state.snapshot) {
        val message = if (state.rootAvailable && state.snapshot != null) state.error ?: state.notice else null
        if (!message.isNullOrBlank()) {
            snackbar.showSnackbar(message)
            viewModel.clearFeedback()
        }
    }
    LaunchedEffect(currentTab) {
        when (currentTab) {
            Tab.LISTS -> {
                if (state.catalogGroups.isEmpty()) viewModel.loadCatalog() else viewModel.refreshCatalog()
                viewModel.refreshDownloadProgress()
            }
            Tab.FIREWALL -> viewModel.refreshFirewall()
            Tab.ACTIVITY -> viewModel.loadAllowlist()
            else -> Unit
        }
    }
    LaunchedEffect(currentTab, connectionMode) {
        if (currentTab == Tab.ACTIVITY && connectionMode) {
            while (true) {
                viewModel.refreshConnections()
                delay(5_000)
            }
        }
    }
    LaunchedEffect(currentTab, state.downloadProgress.running) {
        if (currentTab == Tab.LISTS && state.downloadProgress.running) {
            while (true) {
                delay(2_500)
                viewModel.refreshDownloadProgress()
            }
        }
    }

    if (!state.rootAvailable && !state.loading) {
        RootRequiredScreen(state.error, viewModel::refresh)
        return
    }

    DcmScaffold(
        tab = currentTab,
        onTabChange = { tab = it.name },
        snackbarHost = { SnackbarHost(snackbar) },
    ) {
        when {
            state.loading && state.snapshot == null -> LoadingScreen()
            state.snapshot == null -> ErrorScreen(state.error ?: "No se pudo leer el estado del módulo.", viewModel::refresh)
            else -> when (currentTab) {
                Tab.HOME -> HomeScreen(
                    state = state,
                    onRefresh = viewModel::refresh,
                    onActivityToggle = viewModel::setActivityEnabled,
                    onOpenActivity = { tab = Tab.ACTIVITY.name },
                    onTestDns = viewModel::testDns,
                    onRunDiagnostics = viewModel::runDiagnostics,
                    onRetryActivity = viewModel::retryActivity,
                )
                Tab.ACTIVITY -> ActivityScreen(
                    state = state,
                    onRefresh = viewModel::retryActivity,
                    onClear = viewModel::clearActivity,
                    onEnable = { viewModel.setActivityEnabled(true) },
                    connectionMode = connectionMode,
                    onConnectionModeChange = { connectionMode = it },
                    onRefreshConnections = viewModel::refreshConnections,
                    allowlistedDomains = state.allowlist.toSet(),
                    allowlistReady = state.allowlistLoaded,
                    onToggleDomain = { domain ->
                        if (domain.lowercase(Locale.ROOT) in state.allowlist.map { it.lowercase(Locale.ROOT) }.toSet()) viewModel.removeAllowlist(domain)
                        else viewModel.addAllowlist(domain)
                    },
                )
                Tab.FIREWALL -> FirewallScreen(
                    state = state,
                    onRefresh = viewModel::refreshFirewall,
                    onSetBlocked = viewModel::setAppBlocked,
                    onClearAll = viewModel::clearAllAppBlocks,
                    onTempBlock = viewModel::setAppBlockedTemporarily,
                    onSaveProfile = viewModel::saveFirewallProfile,
                    onApplyProfile = viewModel::applyFirewallProfile,
                    onRemoveProfile = viewModel::removeFirewallProfile,
                )
                Tab.LISTS -> ListsScreen(
                    state = state,
                    onRefresh = viewModel::refreshCatalog,
                    onSelectGroup = { viewModel.loadCatalogGroup(it) },
                    onSetEnabled = viewModel::setCatalogEnabled,
                    onStartDownloadAll = viewModel::startDownloadAll,
                    onSetGroupEnabled = viewModel::setCatalogGroupEnabled,
                    onRefreshProgress = viewModel::refreshDownloadProgress,
                    onLoadAllowlist = viewModel::loadAllowlist,
                    onAddAllowlist = viewModel::addAllowlist,
                    onRemoveAllowlist = viewModel::removeAllowlist,
                )
                Tab.SETTINGS -> SettingsScreen(
                    state = state,
                    onRefresh = viewModel::refresh,
                    onSetProvider = viewModel::setProvider,
                    onSetRetention = viewModel::setActivityRetention,
                    onBackupExport = viewModel::exportBackup,
                    onBackupInspect = viewModel::inspectBackup,
                    onConfirmBackupRestore = viewModel::confirmBackupRestore,
                    onCancelBackupRestore = viewModel::dismissBackupPreview,
                )
            }
        }
    }
}

@Composable
private fun DcmScaffold(
    tab: Tab,
    onTabChange: (Tab) -> Unit,
    snackbarHost: @Composable () -> Unit,
    content: @Composable () -> Unit,
) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        snackbarHost = snackbarHost,
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                Tab.entries.forEach { item ->
                    NavigationBarItem(
                        selected = item == tab,
                        onClick = { onTabChange(item) },
                        icon = { Icon(tabIcon(item), contentDescription = null) },
                        label = { Text(item.label) },
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) { content() }
    }
}

@Composable
private fun tabIcon(tab: Tab) = when (tab) {
    Tab.HOME -> Icons.Outlined.Home
    Tab.ACTIVITY -> Icons.Outlined.History
    Tab.FIREWALL -> Icons.Outlined.Security
    Tab.LISTS -> Icons.Outlined.List
    Tab.SETTINGS -> Icons.Outlined.Settings
}

@Composable
private fun HomeScreen(
    state: DnsCryptUiState,
    onRefresh: () -> Unit,
    onActivityToggle: (Boolean) -> Unit,
    onOpenActivity: () -> Unit,
    onTestDns: () -> Unit,
    onRunDiagnostics: () -> Unit,
    onRetryActivity: () -> Unit,
) {
    val snapshot = state.snapshot ?: return
    val status = snapshot.status
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        ScreenHeader("Tu DNS", "Protección y actividad de la red", onRefresh, state.busyAction != null || state.loading)
        StatusHero(status.running && status.listening && status.redirectActive, status.running && status.listening, status.redirectActive)
        OutlinedButton(
            onClick = onTestDns,
            modifier = Modifier.fillMaxWidth(),
            enabled = state.busyAction == null,
            shape = RoundedCornerShape(18.dp),
        ) {
            Icon(Icons.Outlined.CheckCircle, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text(if (state.busyAction?.contains("DNS", ignoreCase = true) == true) "Probando DNS…" else "Probar mi DNS")
        }
        Text(
            "Hace una prueba real de resolución y revierte la redirección si algo falla.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        DiagnosticsCard(
            checks = state.diagnostics,
            running = state.diagnosticsRunning,
            onRun = onRunDiagnostics,
        )
        ActivityStatsGrid(state)
        ResolverCard(status.server, status.version)
        ActivityControlCard(
            enabled = status.activityEnabled,
            supported = snapshot.activitySupported,
            busy = state.busyAction != null,
            onToggle = onActivityToggle,
        )
        if (!state.activityError.isNullOrBlank()) {
            ActivityErrorCard(state.activityError, state.activityLoading, onRetryActivity)
        }
        SectionHeading("Actividad reciente", "Consultas DNS de este dispositivo", onOpenActivity)
        if (state.activityLoading && snapshot.events.isEmpty()) {
            QuietCard(Icons.Outlined.History, "Leyendo actividad", "El estado del módulo ya está disponible. Los registros se están cargando aparte.")
        } else if (snapshot.events.isEmpty() && state.activityError.isNullOrBlank()) {
            QuietCard(
                icon = Icons.Outlined.History,
                title = "Todavía no hay consultas registradas",
                body = if (snapshot.activitySupported && !status.activityEnabled) {
                    "El registro está apagado. Si lo activás, la app guardará la actividad localmente por un tiempo limitado."
                } else {
                    "Cuando el registro esté activo, acá vas a ver los dominios consultados y su resultado."
                },
            )
        } else {
            snapshot.events.take(3).forEach { ActivityRow(it) }
        }
        Text(
            "El módulo DNSCrypt aplica el filtrado. La app lo administra; no crea una VPN.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(bottom = 8.dp),
        )
    }
}

@Composable
private fun DiagnosticsCard(
    checks: List<DiagnosticCheck>,
    running: Boolean,
    onRun: () -> Unit,
) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.fillMaxWidth().padding(15.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Info, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(9.dp))
                Column(Modifier.weight(1f)) {
                    Text("Diagnóstico", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text("Comprobá el módulo, DNS, listas y firewall", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (running) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                else TextButton(onClick = onRun, enabled = !running) { Text(if (checks.isEmpty()) "Revisar" else "Repetir") }
            }
            if (running) {
                LinearProgressIndicator(Modifier.fillMaxWidth())
                Text("La prueba DNS puede tardar hasta dos minutos. Si falla, el módulo intenta restaurar la red.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else if (checks.isEmpty()) {
                Text("Hace una consulta DNS real y muestra cada resultado por separado; no combina el firewall con las estadísticas DNS.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                checks.forEach { DiagnosticCheckRow(it) }
            }
        }
    }
}

@Composable
private fun DiagnosticCheckRow(check: DiagnosticCheck) {
    val tint = when (check.state) {
        "ok" -> MaterialTheme.colorScheme.primary
        "attention" -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.tertiary
    }
    val icon = when (check.state) {
        "ok" -> Icons.Outlined.CheckCircle
        "attention" -> Icons.Outlined.ErrorOutline
        else -> Icons.Outlined.Info
    }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.padding(top = 1.dp).size(18.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(check.title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
            Text(check.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ScreenHeader(title: String, subtitle: String, onRefresh: (() -> Unit)? = null, refreshing: Boolean = false) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (onRefresh != null) {
            IconButton(onClick = onRefresh, enabled = !refreshing) {
                if (refreshing) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                else Icon(Icons.Outlined.Refresh, contentDescription = "Actualizar")
            }
        }
    }
}

@Composable
private fun StatusHero(protected: Boolean, serviceRunning: Boolean, redirectActive: Boolean) {
    val accent = if (protected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.tertiary
    val title = when {
        protected -> "DNS protegido"
        serviceRunning && !redirectActive -> "Servicio en marcha"
        else -> "Protección inactiva"
    }
    val details = when {
        protected -> "Las consultas del sistema pasan por DNSCrypt."
        serviceRunning && !redirectActive -> "El proxy responde, pero la redirección DNS está apagada."
        else -> "Revisá el estado del módulo y la redirección."
    }
    Card(
        shape = RoundedCornerShape(30.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Box(
            Modifier.fillMaxWidth().background(
                Brush.linearGradient(listOf(Color(0xFF123A3A), Color(0xFF162B40), MaterialTheme.colorScheme.surface)),
            ),
        ) {
            Box(
                Modifier.align(Alignment.TopEnd).padding(top = 14.dp, end = 22.dp).size(108.dp)
                    .clip(CircleShape).background(accent.copy(alpha = 0.08f)),
            )
            Row(Modifier.fillMaxWidth().padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(58.dp).clip(CircleShape).background(accent.copy(alpha = 0.15f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Outlined.Security,
                        contentDescription = null,
                        tint = accent,
                        modifier = Modifier.size(29.dp),
                    )
                }
                Spacer(Modifier.width(15.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text(details, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Spacer(Modifier.width(8.dp))
                Box(Modifier.size(10.dp).clip(CircleShape).background(accent))
            }
        }
    }
}

@Composable
private fun ActivityStatsGrid(state: DnsCryptUiState) {
    val stats = state.snapshot?.stats ?: return
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            MetricCard("Consultas", stats.total.takeIf { stats.available }, "en el registro local", Icons.Outlined.Dns, Modifier.weight(1f))
            MetricCard("Bloqueadas", stats.blocked.takeIf { stats.available }, "por una regla DNS", Icons.Outlined.Security, Modifier.weight(1f), MaterialTheme.colorScheme.error)
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            MetricCard("Permitidas", stats.allowed.takeIf { stats.available }, "respuestas normales", Icons.Outlined.CheckCircle, Modifier.weight(1f))
            MetricCard("Excepciones", stats.allowlisted.takeIf { stats.available }, "permitidas por vos", Icons.Outlined.Info, Modifier.weight(1f), MaterialTheme.colorScheme.secondary)
        }
    }
}

@Composable
private fun MetricCard(
    label: String,
    value: Int?,
    caption: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    modifier: Modifier,
    tint: Color = MaterialTheme.colorScheme.primary,
) {
    Card(modifier, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
                Text(label, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(value?.toString() ?: "—", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            Text(caption, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun ResolverCard(server: String, version: String) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Row(Modifier.fillMaxWidth().padding(17.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(42.dp).clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
                Icon(Icons.Outlined.Dns, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            }
            Spacer(Modifier.width(13.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Servidor DNS", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(resolverLabel(server), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text("dnscrypt-proxy ${version.ifBlank { "sin versión" }}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun ActivityControlCard(enabled: Boolean, supported: Boolean, busy: Boolean, onToggle: (Boolean) -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Row(Modifier.fillMaxWidth().padding(17.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Registro de actividad", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(
                    when {
                        !supported -> "Necesita una versión del módulo con registro local."
                        enabled -> "Activo: guarda consultas en este teléfono con retención limitada."
                        else -> "Apagado. No se están guardando consultas nuevas."
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.width(8.dp))
            if (busy) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
            else Switch(checked = enabled, onCheckedChange = onToggle, enabled = supported)
        }
    }
}

@Composable
private fun ActivityErrorCard(message: String, loading: Boolean, onRetry: () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
    ) {
        Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 7.dp, top = 11.dp, bottom = 11.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            Spacer(Modifier.width(9.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("No se pudo actualizar Actividad", fontWeight = FontWeight.SemiBold)
                Text(message, style = MaterialTheme.typography.bodySmall)
                Text("Se conservan los datos anteriores; el error no se muestra como cero.", style = MaterialTheme.typography.labelSmall)
            }
            TextButton(onClick = onRetry, enabled = !loading) {
                if (loading) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                else Text("Reintentar")
            }
        }
    }
}

@Composable
private fun SectionHeading(title: String, subtitle: String, onClick: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (onClick != null) TextButton(onClick = onClick) { Text("Ver todo") }
    }
}

@Composable
private fun ActivityScreen(
    state: DnsCryptUiState,
    onRefresh: () -> Unit,
    onClear: () -> Unit,
    onEnable: () -> Unit,
    connectionMode: Boolean,
    onConnectionModeChange: (Boolean) -> Unit,
    onRefreshConnections: () -> Unit,
    allowlistedDomains: Set<String>,
    allowlistReady: Boolean,
    onToggleDomain: (String) -> Unit,
) {
    val snapshot = state.snapshot ?: return
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var filter by rememberSaveable { mutableStateOf("todas") }
    var query by rememberSaveable { mutableStateOf("") }
    var showClearDialog by remember { mutableStateOf(false) }
    var selectedEvent by remember { mutableStateOf<ActivityEvent?>(null) }
    val exportActivity = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) {
            val payload = JSONObject()
                .put("format", "dnscrypt-manager-activity-v1")
                .put("exported_at_epoch_ms", System.currentTimeMillis())
                .put("source", "registro local de DNS")
                .put("events", JSONArray().apply {
                    snapshot.events.forEach { event ->
                        put(
                            JSONObject()
                                .put("time", event.time)
                                .put("domain", event.domain)
                                .put("status", event.status)
                                .put("rule", event.rule)
                                .put("category", event.category)
                                .put("return_code", event.returnCode)
                                .put("duration", event.duration),
                        )
                    }
                }).toString(2)
            scope.launch(Dispatchers.IO) {
                val result = runCatching {
                    val output = context.contentResolver.openOutputStream(uri, "w") ?: error("No se pudo abrir el archivo elegido.")
                    output.use { it.write(payload.toByteArray(Charsets.UTF_8)) }
                }
                withContext(kotlinx.coroutines.Dispatchers.Main) {
                    Toast.makeText(context, result.fold({ "Actividad exportada (${snapshot.events.size} registros)" }, { it.message ?: "No se pudo exportar" }), Toast.LENGTH_LONG).show()
                }
            }
        }
    }
    val filtered = snapshot.events.filter { event ->
        val filterMatches = when (filter) {
            "bloqueadas" -> event.status == "blocked"
            "permitidas" -> event.status == "allowed"
            "excepciones" -> event.status == "allowlisted"
            "errores" -> event.status == "error"
            else -> true
        }
        filterMatches && (query.isBlank() || event.domain.contains(query.trim(), ignoreCase = true))
    }
    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp, vertical = 12.dp)) {
        ScreenHeader(
            "Actividad",
            if (connectionMode) "Conexiones activas por aplicación" else "Dominios consultados y resultado",
            if (connectionMode) onRefreshConnections else onRefresh,
            if (connectionMode) state.connectionsLoading || state.busyAction != null else state.activityLoading || state.busyAction != null,
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = !connectionMode, onClick = { onConnectionModeChange(false) }, label = { Text("Consultas DNS") })
            FilterChip(selected = connectionMode, onClick = { onConnectionModeChange(true) }, label = { Text("Conexiones") })
        }
        Spacer(Modifier.height(12.dp))
        if (connectionMode) {
            ConnectionsBody(state, onRefreshConnections, Modifier.weight(1f))
        } else if (!snapshot.activitySupported) {
            QuietCard(Icons.Outlined.Info, "Registro no disponible", "La versión instalada del módulo todavía no expone la actividad DNS local.")
            return@Column
        } else {
        if (!snapshot.status.activityEnabled) {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)) {
                Row(Modifier.fillMaxWidth().padding(15.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text("El registro está apagado", fontWeight = FontWeight.SemiBold)
                        Text("No se agregan consultas nuevas. Los datos anteriores pueden seguir visibles.", style = MaterialTheme.typography.bodySmall)
                    }
                    TextButton(onClick = onEnable, enabled = state.busyAction == null) { Text("Activar") }
                }
            }
            Spacer(Modifier.height(10.dp))
        }
        if (!state.activityError.isNullOrBlank()) {
            ActivityErrorCard(state.activityError, state.activityLoading, onRefresh)
            Spacer(Modifier.height(9.dp))
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            MiniMetric("Total", snapshot.stats.total.takeIf { snapshot.stats.available }, Modifier.weight(1f))
            MiniMetric("Bloqueadas", snapshot.stats.blocked.takeIf { snapshot.stats.available }, Modifier.weight(1f), MaterialTheme.colorScheme.error)
            MiniMetric("Permitidas", (snapshot.stats.allowed + snapshot.stats.allowlisted).takeIf { snapshot.stats.available }, Modifier.weight(1f))
        }
        Spacer(Modifier.height(11.dp))
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
            placeholder = { Text("Buscar un dominio") },
            shape = RoundedCornerShape(18.dp),
        )
        Spacer(Modifier.height(7.dp))
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            listOf("todas" to "Todas", "bloqueadas" to "Bloqueadas", "permitidas" to "Permitidas", "excepciones" to "Excepciones", "errores" to "Errores").forEach { (key, label) ->
                FilterChip(selected = filter == key, onClick = { filter = key }, label = { Text(label) })
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 2.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("${filtered.size} resultados", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { exportActivity.launch("actividad-dns.json") }, enabled = snapshot.events.isNotEmpty()) {
                Text("Exportar")
            }
            TextButton(onClick = { showClearDialog = true }, enabled = state.busyAction == null && snapshot.events.isNotEmpty()) {
                Icon(Icons.Outlined.Delete, contentDescription = null, modifier = Modifier.size(17.dp))
                Spacer(Modifier.width(4.dp))
                Text("Borrar")
            }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.surfaceVariant)
        if (state.activityLoading && snapshot.events.isEmpty()) {
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    CircularProgressIndicator()
                    Text("Cargando actividad DNS…", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        } else if (!state.activityError.isNullOrBlank() && snapshot.events.isEmpty()) {
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                EmptyState("Lectura pendiente", "Tocá Reintentar en el aviso de arriba. No se muestran ceros como si fueran datos reales.")
            }
        } else if (filtered.isEmpty()) {
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                EmptyState("No hay resultados", "Probá otra búsqueda o filtro.")
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f).padding(top = 9.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) { items(filtered, key = { "${it.time}-${it.domain}-${it.status}" }) {
                ActivityRow(
                    it,
                    onClick = { selectedEvent = it },
                    enabled = allowlistReady && state.busyAction == null && validDomainForForm(it.domain.lowercase(Locale.ROOT)),
                )
            } }
        }
        Text(
            "Tocá un dominio para permitirlo o quitarlo de tus excepciones. Se muestran y exportan hasta 200 consultas recientes; no se atribuyen a una app.",
            modifier = Modifier.padding(top = 9.dp, bottom = 3.dp),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        }
    }
    if (showClearDialog) {
        ConfirmDialog(
            title = "¿Borrar la actividad?",
            body = "Se borrarán del teléfono los eventos DNS guardados hasta ahora. Esta acción no se puede deshacer.",
            confirm = "Borrar actividad",
            onDismiss = { showClearDialog = false },
            onConfirm = { showClearDialog = false; onClear() },
        )
    }
    selectedEvent?.let { event ->
        val isAllowlisted = event.domain.lowercase(Locale.ROOT) in allowlistedDomains.map { it.lowercase(Locale.ROOT) }.toSet()
        ConfirmDialog(
            title = if (isAllowlisted) "¿Quitar la excepción?" else "¿Permitir ${event.domain}?",
            body = if (isAllowlisted) "${event.domain} volverá a estar sujeto a las listas DNS activas." else "${event.domain} se agregará a tus dominios permitidos. Puede dejar de bloquearse por una lista DNS.",
            confirm = if (isAllowlisted) "Quitar excepción" else "Permitir dominio",
            onDismiss = { selectedEvent = null },
            onConfirm = { selectedEvent = null; onToggleDomain(event.domain) },
        )
    }
}

@Composable
private fun ConnectionsBody(state: DnsCryptUiState, onRefresh: () -> Unit, modifier: Modifier) {
    val context = LocalContext.current
    val appResult by produceState<Result<List<FirewallApp>>?>(null, context) {
        value = try {
            Result.success(withContext(Dispatchers.IO) { FirewallAppInventory.load(context) })
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            Result.failure(error)
        }
    }
    val appsByUid = appResult?.getOrNull().orEmpty().associateBy { it.uid }
    Column(modifier.fillMaxWidth()) {
        QuietCard(
            Icons.Outlined.Info,
            "Muestra en vivo, sin historial",
            "Solo enseña sockets TCP/UDP conectados que el sistema expone. No ve conexiones muy breves ni convierte IPs en dominios.",
        )
        Spacer(Modifier.height(8.dp))
        if (state.connectionsError != null && state.connections.isEmpty()) {
            EmptyState("No se pudieron leer las conexiones", state.connectionsError)
        } else if (state.connectionsLoading && state.connections.isEmpty()) {
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        } else if (state.connections.isEmpty()) {
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                EmptyState("No hay conexiones activas", "La próxima lectura se hace automáticamente cada 5 segundos mientras mirás esta pantalla.")
            }
        } else {
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                items(state.connections.mapIndexed { index, connection -> index to connection }, key = { it.first }) { (_, connection) ->
                    ConnectionRow(connection, appsByUid[connection.uid]?.label ?: "UID ${connection.uid}")
                }
            }
        }
        if (state.connectionsError != null && state.connections.isNotEmpty()) {
            Text("No se pudo actualizar: ${state.connectionsError}", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
        TextButton(onClick = onRefresh, enabled = !state.connectionsLoading && state.busyAction == null) { Text("Actualizar ahora") }
    }
}

@Composable
private fun ConnectionRow(connection: ConnectionEvent, appLabel: String) {
    val address = if (connection.remoteAddress.contains(':')) "[${connection.remoteAddress}]:${connection.remotePort}" else "${connection.remoteAddress}:${connection.remotePort}"
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 13.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(appLabel, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(address, style = MaterialTheme.typography.bodyMedium)
            Text("${connection.protocol.replace("v4", " IPv4").replace("v6", " IPv6")} · ${connection.state}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun MiniMetric(label: String, value: Int?, modifier: Modifier, tint: Color = MaterialTheme.colorScheme.primary) {
    Card(modifier, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 11.dp, vertical = 10.dp)) {
            Text(value?.toString() ?: "—", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = tint)
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun ActivityRow(event: ActivityEvent, onClick: (() -> Unit)? = null, enabled: Boolean = false) {
    val tint = when (event.status) {
        "blocked" -> MaterialTheme.colorScheme.error
        "allowed", "allowlisted" -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.tertiary
    }
    Card(
        modifier = if (onClick != null && enabled) Modifier.clickable(onClick = onClick) else Modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(9.dp).clip(CircleShape).background(tint))
            Spacer(Modifier.width(11.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(event.domain.ifBlank { "Dominio desconocido" }, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold)
                val detail = listOfNotNull(
                    event.category.takeIf { it.isNotBlank() }?.let(::categoryLabel),
                    event.rule.takeIf { it.isNotBlank() && !it.equals(event.domain, ignoreCase = true) },
                ).joinToString(" · ")
                val fallback = if (event.status == "blocked") "Bloqueada por una regla DNS" else "Consulta DNS"
                Text(detail.ifBlank { fallback }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.width(8.dp))
            Column(horizontalAlignment = Alignment.End) {
                Text(activityLabel(event.status), color = tint, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                Text(formatTimestamp(event.time), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun FirewallScreen(
    state: DnsCryptUiState,
    onRefresh: () -> Unit,
    onSetBlocked: (List<String>, Boolean) -> Unit,
    onClearAll: () -> Unit,
    onTempBlock: (String, String) -> Unit,
    onSaveProfile: (String, List<String>) -> Unit,
    onApplyProfile: (FirewallProfile) -> Unit,
    onRemoveProfile: (String) -> Unit,
) {
    val context = LocalContext.current
    val appResult by produceState<Result<List<FirewallApp>>?>(null, context) {
        value = try {
            Result.success(withContext(Dispatchers.IO) { FirewallAppInventory.load(context) })
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            Result.failure(error)
        }
    }
    val apps = appResult?.getOrNull().orEmpty()
    val inventoryError = appResult?.exceptionOrNull()
    val support = state.firewall
    val moduleEnabled = state.snapshot?.status?.moduleEnabled == true
    var search by rememberSaveable { mutableStateOf("") }
    var pendingApp by remember { mutableStateOf<FirewallApp?>(null) }
    var confirmClearAll by remember { mutableStateOf(false) }
    var blockDuration by rememberSaveable { mutableStateOf("1h") }
    var profileName by rememberSaveable { mutableStateOf("") }
    var showSaveProfile by remember { mutableStateOf(false) }
    var pendingProfile by remember { mutableStateOf<FirewallProfile?>(null) }
    var pendingDeleteProfile by remember { mutableStateOf<FirewallProfile?>(null) }
    val filteredApps = apps.filter { app ->
        val terms = listOf(app.label, app.packageName) + app.sharedLabels
        search.isBlank() || terms.any { it.contains(search.trim(), ignoreCase = true) }
    }
    val canClear = state.busyAction == null && !state.firewallLoading
    val canBlock = support?.supported == true && moduleEnabled && canClear

    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp, vertical = 12.dp)) {
        ScreenHeader("Firewall", "Bloqueo de internet por aplicación", onRefresh, state.firewallLoading || state.busyAction != null)
        Spacer(Modifier.height(10.dp))

        when {
            support == null && state.firewallLoading -> QuietCard(
                Icons.Outlined.Security,
                "Revisando compatibilidad",
                "El módulo está comprobando reglas IPv4 e IPv6 antes de habilitar los controles.",
            )
            support == null -> QuietCard(
                Icons.Outlined.Info,
                "No se pudo verificar",
                state.firewallError ?: "Tocá actualizar para revisar el soporte del teléfono.",
            )
            !support.supported -> QuietCard(
                Icons.Outlined.Info,
                "Firewall no disponible en este teléfono",
                "IPv4: ${if (support.ipv4Owner) "compatible" else "no confirmado"}. IPv6: ${if (support.ipv6Owner) "compatible" else "no confirmado"}. Se necesitan ambos; no se aplican reglas.",
            )
            !moduleEnabled -> QuietCard(
                Icons.Outlined.Info,
                "El módulo está desactivado",
                "Las reglas guardadas no se aplican mientras DNSCrypt Manager está desactivado. Activá el módulo para volver a bloquear apps.",
            )
            state.firewallBlockedUids.isNotEmpty() && !support.active -> QuietCard(
                Icons.Outlined.Info,
                "Reglas guardadas, firewall inactivo",
                "Las preferencias están guardadas, pero el módulo no confirmó los ganchos IPv4 e IPv6. No cuentes esos bloqueos como activos.",
            )
            state.firewallBlockedUids.isNotEmpty() -> QuietCard(
                Icons.Outlined.Security,
                "Firewall activo",
                "${state.firewallBlockedUids.size} app(s) o grupos de apps sin acceso a internet por Wi‑Fi y datos móviles.",
            )
            else -> QuietCard(
                Icons.Outlined.CheckCircle,
                "Todo permitido",
                "El firewall está listo. Activá el control de una app para quitarle el acceso a internet.",
            )
        }

        if (!state.firewallError.isNullOrBlank() && support != null) {
            Text(
                "No se pudo actualizar todo: ${state.firewallError}",
                Modifier.padding(top = 7.dp, start = 3.dp, end = 3.dp),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
        Spacer(Modifier.height(8.dp))
        Text(
            "Bloquea toda la conexión de red de la app; no filtra dominios. La lista se procesa en este teléfono.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 13.dp, vertical = 9.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Perfiles rápidos", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    TextButton(onClick = { showSaveProfile = true }, enabled = canClear && canBlock) { Text("Guardar actual") }
                }
                if (state.firewallProfiles.isEmpty()) {
                    Text("Guardá un conjunto de apps bloqueadas para volver a aplicarlo cuando quieras.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), verticalAlignment = Alignment.CenterVertically) {
                        state.firewallProfiles.forEach { profile ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                FilterChip(
                                    selected = false,
                                    onClick = { pendingProfile = profile },
                                    label = { Text(profile.name) },
                                    enabled = canClear && canBlock,
                                )
                                IconButton(onClick = { pendingDeleteProfile = profile }, enabled = canClear) {
                                    Icon(Icons.Outlined.Delete, contentDescription = "Borrar perfil ${profile.name}", tint = MaterialTheme.colorScheme.error)
                                }
                            }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(9.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Aplicaciones", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            if (state.firewallBlockedUids.isNotEmpty()) {
                TextButton(
                    onClick = { confirmClearAll = true },
                    enabled = canClear,
                ) { Text("Permitir todas") }
            }
        }
        OutlinedTextField(
            value = search,
            onValueChange = { search = it },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
            placeholder = { Text("Buscar una aplicación") },
            shape = RoundedCornerShape(17.dp),
        )
        if (appResult == null) {
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else if (inventoryError != null) {
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                EmptyState("No se pudieron cargar las apps", inventoryError.message ?: "Reiniciá la app e intentá de nuevo.")
            }
        } else if (filteredApps.isEmpty()) {
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                EmptyState("No encontramos aplicaciones", "Probá con otro nombre.")
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f).padding(top = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(filteredApps, key = { it.uid }) { app ->
                    val blocked = app.uid in state.firewallBlockedUids
                    FirewallAppRow(
                        app = app,
                        blocked = blocked,
                        temporaryUntil = app.packageNames.firstNotNullOfOrNull { state.firewallTemporaryRules[it] },
                        enabled = if (blocked) canClear else canBlock,
                        onRefresh = onRefresh,
                        onToggle = { requested ->
                            if (requested) pendingApp = app else onSetBlocked(app.packageNames, false)
                        },
                    )
                }
            }
        }
    }

    pendingApp?.let { app ->
        val sharedNames = app.sharedLabels.distinct()
        AlertDialog(
            onDismissRequest = { pendingApp = null },
            title = { Text("¿Bloquear ${app.label} de internet?") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                    Text(buildString {
                        append("Va a perder el acceso a internet por Wi‑Fi y datos móviles. Puede dejar de sincronizar o conectarse.")
                        if (sharedNames.isNotEmpty()) append(" También afecta a: ${sharedNames.joinToString(", ")}.")
                    })
                    Text("Duración", style = MaterialTheme.typography.labelLarge)
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf("15m" to "15 min", "1h" to "1 hora", "8h" to "8 horas", "siempre" to "Siempre").forEach { (value, label) ->
                            FilterChip(selected = blockDuration == value, onClick = { blockDuration = value }, label = { Text(label) })
                        }
                    }
                    Text("Los bloqueos temporales vencen aunque cierres la app o reinicies el teléfono.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    Button(onClick = {
                        pendingApp = null
                        if (blockDuration == "siempre") onSetBlocked(app.packageNames, true)
                        else onTempBlock(app.packageNames.first(), blockDuration)
                    }, enabled = canBlock) { Text(if (blockDuration == "siempre") "Bloquear siempre" else "Bloquear por ${when (blockDuration) { "15m" -> "15 min"; "1h" -> "1 hora"; else -> "8 horas" }}") }
                    TextButton(onClick = { pendingApp = null }) { Text("Volver") }
                }
            },
            containerColor = MaterialTheme.colorScheme.surface,
        )
    }
    if (showSaveProfile) {
        AlertDialog(
            onDismissRequest = { showSaveProfile = false },
            title = { Text("Guardar perfil") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Se guardará qué apps están bloqueadas ahora.")
                    OutlinedTextField(
                        value = profileName,
                        onValueChange = { profileName = it.take(32) },
                        label = { Text("Nombre") },
                        singleLine = true,
                    )
                    Text("Usá letras, números, espacios, guion o guion bajo.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        val blocked = apps.filter { it.uid in state.firewallBlockedUids }.mapNotNull { it.packageNames.firstOrNull() }
                        showSaveProfile = false
                        onSaveProfile(profileName.trim(), blocked)
                    },
                    enabled = canBlock && profileName.trim().matches(Regex("^[A-Za-z0-9][A-Za-z0-9 _-]{0,31}$")) && !profileName.trim().endsWith(" ") && !profileName.contains("  "),
                ) { Text("Guardar") }
            },
            dismissButton = { TextButton(onClick = { showSaveProfile = false }) { Text("Cancelar") } },
            containerColor = MaterialTheme.colorScheme.surface,
        )
    }
    pendingProfile?.let { profile ->
        ConfirmDialog(
            title = "Aplicar ${profile.name}",
            body = "Se ajustará el firewall para que coincida con este perfil (${profile.packages.size} apps guardadas). Las apps que ya no estén instaladas se omiten.",
            confirm = "Aplicar perfil",
            onDismiss = { pendingProfile = null },
            onConfirm = { pendingProfile = null; onApplyProfile(profile) },
        )
    }
    pendingDeleteProfile?.let { profile ->
        ConfirmDialog(
            title = "¿Borrar ${profile.name}?",
            body = "Se elimina el perfil guardado; las reglas actuales del firewall no cambian.",
            confirm = "Borrar perfil",
            onDismiss = { pendingDeleteProfile = null },
            onConfirm = { pendingDeleteProfile = null; onRemoveProfile(profile.name) },
        )
    }
    if (confirmClearAll) {
        ConfirmDialog(
            title = "¿Permitir todas las apps?",
            body = "Se van a quitar todas las reglas de este firewall y las apps recuperarán internet.",
            confirm = "Permitir todas",
            onDismiss = { confirmClearAll = false },
            onConfirm = { confirmClearAll = false; onClearAll() },
        )
    }
}

@Composable
private fun FirewallAppRow(
    app: FirewallApp,
    blocked: Boolean,
    temporaryUntil: Long?,
    enabled: Boolean,
    onRefresh: () -> Unit,
    onToggle: (Boolean) -> Unit,
) {
    val nowMillis by produceState(initialValue = System.currentTimeMillis(), key1 = temporaryUntil) {
        while (temporaryUntil != null && value / 1000L < temporaryUntil) {
            delay(30_000)
            value = System.currentTimeMillis()
        }
    }
    LaunchedEffect(temporaryUntil, nowMillis) {
        if (temporaryUntil != null && nowMillis / 1000L >= temporaryUntil) onRefresh()
    }
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 13.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(39.dp).clip(RoundedCornerShape(13.dp)).background(MaterialTheme.colorScheme.primaryContainer),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Outlined.Security, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            }
            Spacer(Modifier.width(11.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(app.label, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold)
                Text(
                    if (app.sharedLabels.isEmpty()) app.packageName
                    else "Comparte red con: ${app.sharedLabels.joinToString(", ")}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                if (temporaryUntil != null) {
                    val minutes = ((temporaryUntil * 1000L - nowMillis).coerceAtLeast(0L) + 59_999L) / 60_000L
                    Text(
                        if (minutes == 0L) "Bloqueo temporal · actualizando estado…" else "Bloqueo temporal · vence en $minutes min",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                }
            }
            Spacer(Modifier.width(8.dp))
            Switch(checked = blocked, onCheckedChange = onToggle, enabled = enabled)
        }
    }
}

@Composable
private fun ListsScreen(
    state: DnsCryptUiState,
    onRefresh: () -> Unit,
    onSelectGroup: (String) -> Unit,
    onSetEnabled: (CatalogEntry, Boolean) -> Unit,
    onStartDownloadAll: () -> Unit,
    onSetGroupEnabled: (String, Boolean) -> Unit,
    onRefreshProgress: () -> Unit,
    onLoadAllowlist: () -> Unit,
    onAddAllowlist: (String) -> Unit,
    onRemoveAllowlist: (String) -> Unit,
) {
    var section by rememberSaveable { mutableStateOf("fuentes") }
    var search by rememberSaveable { mutableStateOf("") }
    var recommendedOnly by rememberSaveable { mutableStateOf(false) }
    var activeOnly by rememberSaveable { mutableStateOf(false) }
    var pendingEntry by remember { mutableStateOf<CatalogEntry?>(null) }
    var pendingEnabled by remember { mutableStateOf(false) }
    var pendingGroupAction by remember { mutableStateOf<Pair<String, Boolean>?>(null) }
    var confirmDownloadAll by remember { mutableStateOf(false) }
    var allowDomain by rememberSaveable { mutableStateOf("") }
    var allowError by rememberSaveable { mutableStateOf<String?>(null) }
    var pendingRemoval by remember { mutableStateOf<String?>(null) }

    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp, vertical = 12.dp)) {
        ScreenHeader(
            "Listas",
            "Elegí qué querés bloquear",
            if (section == "fuentes") onRefresh else onLoadAllowlist,
            (if (section == "fuentes") state.catalogLoading else state.allowlistLoading) || state.busyAction != null,
        )
        Spacer(Modifier.height(11.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = section == "fuentes", onClick = { section = "fuentes" }, label = { Text("Catálogo") }, modifier = Modifier.weight(1f))
            FilterChip(selected = section == "permitidos", onClick = { section = "permitidos"; onLoadAllowlist() }, label = { Text("Permitidos (${state.allowlist.size})") }, modifier = Modifier.weight(1f))
        }
        if (section == "fuentes") {
            CatalogPanel(
                state = state,
                search = search,
                onSearch = { search = it },
                recommendedOnly = recommendedOnly,
                onRecommendedOnly = { recommendedOnly = it },
                activeOnly = activeOnly,
                onActiveOnly = { activeOnly = it },
                onSelectGroup = onSelectGroup,
                onRequestToggle = { entry, enabled -> pendingEntry = entry; pendingEnabled = enabled },
                onRequestDownloadAll = { confirmDownloadAll = true },
                onRequestGroupToggle = { group, enabled -> pendingGroupAction = group to enabled },
                onRefreshProgress = onRefreshProgress,
            )
        } else {
            AllowlistPanel(
                domains = state.allowlist,
                loading = state.allowlistLoading,
                busy = state.busyAction != null,
                domain = allowDomain,
                error = allowError,
                onDomainChange = { allowDomain = it; allowError = null },
                onAdd = {
                    val normalized = allowDomain.trim().lowercase(Locale.ROOT)
                    if (!validDomainForForm(normalized)) {
                        allowError = "Escribí un dominio, por ejemplo: ejemplo.com. No uses URL ni comodines."
                    } else {
                        onAddAllowlist(normalized)
                        allowDomain = ""
                    }
                },
                onRemove = { pendingRemoval = it },
            )
        }
    }

    pendingEntry?.let { entry ->
        val enabling = pendingEnabled
        ConfirmDialog(
            title = if (enabling) "¿Activar esta lista?" else "¿Desactivar esta lista?",
            body = buildString {
                append(if (enabling) "Sus dominios se incorporarán al filtro DNS. " else "Sus dominios dejarán de formar parte del filtro. ")
                append("Podés cambiar esta decisión después desde acá.")
                if (enabling && entry.license.equals("LICENSE_UNKNOWN", ignoreCase = true)) {
                    append(" La licencia de esta fuente no está confirmada en el catálogo.")
                }
            },
            confirm = if (enabling) "Activar lista" else "Desactivar lista",
            onDismiss = { pendingEntry = null },
            onConfirm = { pendingEntry = null; onSetEnabled(entry, enabling) },
        )
    }
    pendingGroupAction?.let { (group, enabling) ->
        ConfirmDialog(
            title = if (enabling) "¿Activar listas preparadas de ${groupLabel(group)}?" else "¿Desactivar las listas de ${groupLabel(group)}?",
            body = if (enabling) {
                "Se activan en una sola operación las fuentes descargadas y compatibles. No se descarga nada ahora; las fuentes archivadas, incompatibles o sin caché quedan apagadas. Después se recompila el filtro una sola vez."
            } else {
                "Se desactivan todas las fuentes activas de esta categoría y se recompila el filtro. Las demás categorías no cambian."
            },
            confirm = if (enabling) "Activar disponibles" else "Desactivar categoría",
            onDismiss = { pendingGroupAction = null },
            onConfirm = { pendingGroupAction = null; onSetGroupEnabled(group, enabling) },
        )
    }
    if (confirmDownloadAll) {
        ConfirmDialog(
            title = "Preparar todas las listas",
            body = "Se descargarán copias verificadas para tenerlas listas. Esto puede usar bastantes datos y tardar. Las fuentes nuevas quedan apagadas: no cambia el bloqueo actual.",
            confirm = "Preparar cachés",
            onDismiss = { confirmDownloadAll = false },
            onConfirm = { confirmDownloadAll = false; onStartDownloadAll() },
        )
    }
    pendingRemoval?.let { domain ->
        ConfirmDialog(
            title = "¿Quitar la excepción?",
            body = "$domain dejará de estar permitido por la allowlist. Una lista de bloqueo todavía podría bloquearlo.",
            confirm = "Quitar",
            onDismiss = { pendingRemoval = null },
            onConfirm = { pendingRemoval = null; onRemoveAllowlist(domain) },
        )
    }
}

@Composable
private fun ColumnScope.CatalogPanel(
    state: DnsCryptUiState,
    search: String,
    onSearch: (String) -> Unit,
    recommendedOnly: Boolean,
    onRecommendedOnly: (Boolean) -> Unit,
    activeOnly: Boolean,
    onActiveOnly: (Boolean) -> Unit,
    onSelectGroup: (String) -> Unit,
    onRequestToggle: (CatalogEntry, Boolean) -> Unit,
    onRequestDownloadAll: () -> Unit,
    onRequestGroupToggle: (String, Boolean) -> Unit,
    onRefreshProgress: () -> Unit,
) {
    Column(Modifier.weight(1f).padding(top = 8.dp)) {
        DownloadAllCard(state, onRequestDownloadAll, onRefreshProgress)
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            state.catalogGroups.forEach { group ->
                val key = normalizedGroupKey(group.key)
                FilterChip(
                    selected = state.selectedCatalogGroup == key,
                    onClick = { onSelectGroup(key) },
                    label = { Text("${groupLabel(key)}  ${group.active}/${group.count}") },
                )
            }
        }
        state.catalogGroups.firstOrNull { normalizedGroupKey(it.key) == state.selectedCatalogGroup }?.let { group ->
            val key = normalizedGroupKey(group.key)
            val checkboxState = when {
                group.active == 0 -> ToggleableState.Off
                group.count > 0 && group.active >= group.count -> ToggleableState.On
                else -> ToggleableState.Indeterminate
            }
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f))) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 7.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    TriStateCheckbox(
                        state = checkboxState,
                        onClick = { onRequestGroupToggle(key, group.active == 0) },
                        enabled = state.busyAction == null && state.catalogLoaded,
                    )
                    Column(Modifier.weight(1f)) {
                        Text("Toda la categoría", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
                        Text("${group.active} de ${group.count} activas", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    TextButton(
                        onClick = { onRequestGroupToggle(key, true) },
                        enabled = state.busyAction == null && state.catalogLoaded && group.active < group.count,
                    ) { Text("Activar preparadas") }
                    if (group.active > 0) {
                        TextButton(
                            onClick = { onRequestGroupToggle(key, false) },
                            enabled = state.busyAction == null && state.catalogLoaded,
                        ) { Text("Apagar") }
                    }
                }
            }
        }
        Spacer(Modifier.height(7.dp))
        OutlinedTextField(
            value = search,
            onValueChange = onSearch,
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
            placeholder = { Text("Buscar una lista") },
            shape = RoundedCornerShape(17.dp),
        )
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            FilterChip(selected = recommendedOnly, onClick = { onRecommendedOnly(!recommendedOnly) }, label = { Text("Recomendadas") })
            Spacer(Modifier.weight(1f))
            FilterChip(selected = activeOnly, onClick = { onActiveOnly(!activeOnly) }, label = { Text("Activas") })
            Spacer(Modifier.weight(1f))
            Text("${state.catalogEntries.count { matchesCatalog(it, search, recommendedOnly, activeOnly) }} fuentes", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.surfaceVariant)
        when {
            state.catalogLoading -> Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            !state.catalogLoaded -> EmptyState("No se pudo abrir el catálogo", "Tocá actualizar para volver a intentarlo.")
            state.catalogEntries.none { matchesCatalog(it, search, recommendedOnly, activeOnly) } -> Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                EmptyState("No encontramos listas", "Probá otra palabra o categoría.")
            }
            else -> LazyColumn(
                modifier = Modifier.weight(1f).padding(top = 8.dp),
                verticalArrangement = Arrangement.spacedBy(9.dp),
            ) {
                items(state.catalogEntries.filter { matchesCatalog(it, search, recommendedOnly, activeOnly) }, key = { it.id }) { entry ->
                    CatalogEntryCard(entry, state.busyAction != null) { enabled -> onRequestToggle(entry, enabled) }
                }
            }
        }
    }
}

@Composable
private fun DownloadAllCard(state: DnsCryptUiState, onStart: () -> Unit, onRefresh: () -> Unit) {
    val progress = state.downloadProgress
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer), shape = RoundedCornerShape(22.dp)) {
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.CloudDownload, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(9.dp))
                Column(Modifier.weight(1f)) {
                    Text(if (progress.running) "Preparando listas…" else "Dejar listas para descargar", fontWeight = FontWeight.SemiBold)
                    Text(
                        if (progress.running) "${progress.done} de ${progress.total} · ${progress.current.ifBlank { "procesando" }}"
                        else "Prepara copias verificadas; no activa fuentes.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (progress.running) {
                    IconButton(onClick = onRefresh) { Icon(Icons.Outlined.Refresh, contentDescription = "Actualizar progreso") }
                } else {
                    OutlinedButton(onClick = onStart, enabled = state.busyAction == null) { Text("Preparar") }
                }
            }
            if (progress.running) {
                val fraction = if (progress.total > 0) (progress.done.toFloat() / progress.total).coerceIn(0f, 1f) else 0f
                LinearProgressIndicator(progress = fraction, modifier = Modifier.fillMaxWidth())
            } else if (progress.state == "done" || progress.state == "partial") {
                Text(
                    "Último resultado: ${progress.success} listas listas, ${progress.failed} con error, ${progress.skipped} omitidas.",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun CatalogEntryCard(entry: CatalogEntry, busy: Boolean, onToggle: (Boolean) -> Unit) {
    val blocked = entry.activationBlocked || entry.archived || entry.upstreamStatus.equals("broken", true)
    val status = when {
        entry.enabled -> "Activa"
        entry.archived -> "Archivada"
        entry.upstreamStatus.equals("broken", true) -> "Fuente rota"
        entry.activationBlocked -> "Revisión técnica"
        entry.recommended -> "Recomendada"
        else -> "Disponible"
    }
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface), shape = RoundedCornerShape(20.dp)) {
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(entry.displayName(), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (entry.subgroup.isNotBlank()) Text(entry.subgroup, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Spacer(Modifier.width(8.dp))
                    Switch(
                    checked = entry.enabled,
                    onCheckedChange = onToggle,
                    enabled = !busy && (entry.enabled || !blocked),
                )
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                StatusPill(status, when {
                    entry.enabled -> MaterialTheme.colorScheme.primary
                    blocked -> MaterialTheme.colorScheme.error
                    entry.recommended -> MaterialTheme.colorScheme.secondary
                    else -> MaterialTheme.colorScheme.onSurfaceVariant
                })
                Spacer(Modifier.width(8.dp))
                Text(
                    "${aggressivenessLabel(entry.aggressiveness)} · ${entry.domainCount.takeIf { it != "-" }?.let { "$it dominios" } ?: "sin caché local"}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            val categories = entry.categories.split(',').map(String::trim).filter(String::isNotBlank).take(4).joinToString(" · ") { categoryLabel(it) }
            if (categories.isNotBlank()) Text(categories, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (entry.license.equals("LICENSE_UNKNOWN", true)) {
                Text("La licencia no está identificada en el catálogo.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.tertiary)
            }
            if (entry.upstreamStatus.equals("broken", true) || entry.archived) {
                Text("El upstream figura ${if (entry.archived) "archivado" else "roto"}; no se puede activar desde acá.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun StatusPill(label: String, tint: Color) {
    Surface(color = tint.copy(alpha = 0.13f), shape = RoundedCornerShape(50)) {
        Text(label, modifier = Modifier.padding(horizontal = 9.dp, vertical = 4.dp), color = tint, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun ColumnScope.AllowlistPanel(
    domains: List<String>,
    loading: Boolean,
    busy: Boolean,
    domain: String,
    error: String?,
    onDomainChange: (String) -> Unit,
    onAdd: () -> Unit,
    onRemove: (String) -> Unit,
) {
    Column(Modifier.weight(1f).padding(top = 8.dp)) {
        QuietCard(
            Icons.Outlined.CheckCircle,
            "Permitidos por vos",
            "Estos dominios quedan exceptuados del bloqueo DNS. Las listas activas no deberían volver a bloquearlos.",
        )
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = domain,
                onValueChange = onDomainChange,
                modifier = Modifier.weight(1f),
                singleLine = true,
                label = { Text("Dominio") },
                placeholder = { Text("ejemplo.com") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                shape = RoundedCornerShape(16.dp),
            )
            Button(onClick = onAdd, enabled = domain.isNotBlank() && !busy, modifier = Modifier.padding(top = 5.dp)) {
                Icon(Icons.Outlined.Add, contentDescription = null)
            }
        }
        if (!error.isNullOrBlank()) Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(start = 4.dp, top = 3.dp))
        Spacer(Modifier.height(9.dp))
        Text("${domains.size} excepciones", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        HorizontalDivider(Modifier.padding(top = 7.dp), color = MaterialTheme.colorScheme.surfaceVariant)
        when {
            loading -> Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            domains.isEmpty() -> Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                EmptyState("Todavía no hay excepciones", "Agregá un dominio si necesitás permitirlo aunque una lista lo bloquee.")
            }
            else -> LazyColumn(Modifier.weight(1f).padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                items(domains, key = { it }) { item ->
                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                        Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 5.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(item, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.Medium)
                            IconButton(onClick = { onRemove(item) }, enabled = !busy) { Icon(Icons.Outlined.Delete, contentDescription = "Quitar $item", tint = MaterialTheme.colorScheme.error) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SettingsScreen(
    state: DnsCryptUiState,
    onRefresh: () -> Unit,
    onSetProvider: (String, String) -> Unit,
    onSetRetention: (Int, Int) -> Unit,
    onBackupExport: (Uri) -> Unit,
    onBackupInspect: (Uri) -> Unit,
    onConfirmBackupRestore: () -> Unit,
    onCancelBackupRestore: () -> Unit,
) {
    val snapshot = state.snapshot ?: return
    val current = snapshot.status.server.lowercase(Locale.ROOT).trim().removePrefix("[").removeSuffix("]")
    var pendingProvider by remember { mutableStateOf<String?>(null) }
    var nextDnsId by rememberSaveable { mutableStateOf("") }
    var pendingNextDns by remember { mutableStateOf(false) }
    val exportBackup = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/gzip")) { uri ->
        uri?.let(onBackupExport)
    }
    val importBackup = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let(onBackupInspect)
    }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(13.dp),
    ) {
        ScreenHeader("Ajustes", "Conexión con el módulo", onRefresh, state.loading || state.busyAction != null)
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Dns, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(9.dp))
                    Column {
                        Text("Servidor DNS", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        Text("Ahora: ${resolverLabel(snapshot.status.server)}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                Text("Elegí un perfil. Al aplicarlo, el proxy se reinicia; la conexión DNS puede tardar unos segundos en volver.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                listOf(
                    listOf("cloudflare" to "Cloudflare", "quad9" to "Quad9"),
                    listOf("adguard" to "AdGuard", "mullvad" to "Mullvad"),
                ).forEach { row ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEach { (key, label) ->
                            FilterChip(
                                selected = current == key,
                                onClick = { if (current != key) pendingProvider = key },
                                label = { Text(label) },
                                modifier = Modifier.weight(1f),
                                enabled = state.busyAction == null,
                            )
                        }
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.surfaceVariant)
                Text("Usar NextDNS", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Text("Ingresá el ID hexadecimal de tu perfil de NextDNS.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = nextDnsId,
                        onValueChange = { nextDnsId = it.filter(Char::isLetterOrDigit).take(12) },
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                        label = { Text("ID de NextDNS") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii),
                        shape = RoundedCornerShape(16.dp),
                    )
                    OutlinedButton(
                        onClick = { pendingNextDns = true },
                        enabled = state.busyAction == null && nextDnsId.matches(Regex("^[0-9a-fA-F]{4,12}$")),
                    ) { Text("Aplicar") }
                }
            }
        }
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
            Column(Modifier.fillMaxWidth().padding(15.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text("Retención de actividad", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Text("Se borra automáticamente lo que supere estos límites.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(1, 3, 7).forEach { days ->
                        FilterChip(
                            selected = snapshot.activityRetentionDays == days,
                            onClick = { onSetRetention(days, snapshot.activityMaxEntries) },
                            label = { Text("$days ${if (days == 1) "día" else "días"}") },
                            enabled = state.busyAction == null,
                        )
                    }
                }
                Text("Máximo de consultas", style = MaterialTheme.typography.labelLarge)
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(50, 500, 1_000, 2_000, 5_000, 10_000).forEach { entries ->
                        FilterChip(
                            selected = snapshot.activityMaxEntries == entries,
                            onClick = { onSetRetention(snapshot.activityRetentionDays, entries) },
                            label = { Text(entries.toString()) },
                            enabled = state.busyAction == null,
                        )
                    }
                }
            }
        }
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
            Column(Modifier.fillMaxWidth().padding(15.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Copia de seguridad", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Text("Guarda la configuración DNS, las listas elegidas y las reglas y perfiles del firewall. No incluye el historial DNS ni las cachés descargadas del catálogo.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { exportBackup.launch("dnscrypt-manager-backup.tar.gz") }, enabled = state.busyAction == null, modifier = Modifier.weight(1f)) { Text("Crear copia") }
                    OutlinedButton(onClick = { importBackup.launch(arrayOf("application/gzip", "application/x-gzip", "application/octet-stream")) }, enabled = state.busyAction == null, modifier = Modifier.weight(1f)) { Text("Restaurar") }
                }
                if (state.busyAction?.startsWith("Validando la copia") == true) {
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                    Text("La copia se está validando sin extraerla ni aplicarla.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text("La copia incluye el ID de NextDNS si usás ese proveedor; guardá el archivo en un lugar privado.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.tertiary)
            }
        }
        QuietCard(
            Icons.Outlined.History,
            "Actividad DNS en este teléfono",
            if (snapshot.status.activityEnabled) "El registro está activo. Se puede apagar en Inicio; la información queda guardada localmente con límites de retención." else "El registro está apagado. No se anotan consultas nuevas.",
        )
        QuietCard(
            Icons.Outlined.Info,
            "Conexiones por aplicación",
            "Actividad muestra los dominios consultados. Conexiones muestra sockets activos con UID, sin atribuir cada consulta DNS a una app ni guardar historial.",
        )
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text("Versión del módulo", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(snapshot.status.version.ifBlank { "No disponible" }, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text("La WebUI del módulo sigue disponible para diagnóstico avanzado y recuperación.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Text("La app usa root para llamar al CLI del módulo. No crea una VPN ni envía actividad a un servidor.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    pendingProvider?.let { key ->
        val label = resolverLabel(key)
        ConfirmDialog(
            title = "Cambiar a $label",
            body = "Se guardará el nuevo servidor DNS y se reiniciará dnscrypt-proxy. Puede haber una pausa breve de conectividad.",
            confirm = "Cambiar y reiniciar",
            onDismiss = { pendingProvider = null },
            onConfirm = { pendingProvider = null; onSetProvider(key, "") },
        )
    }
    if (pendingNextDns) {
        ConfirmDialog(
            title = "Aplicar NextDNS",
            body = "Se guardará este ID de perfil y se reiniciará dnscrypt-proxy. Revisá que el ID sea el tuyo.",
            confirm = "Aplicar NextDNS",
            onDismiss = { pendingNextDns = false },
            onConfirm = { pendingNextDns = false; onSetProvider("nextdns", nextDnsId) },
        )
    }
    state.backupPreview?.let { preview ->
        AlertDialog(
            onDismissRequest = { if (state.busyAction == null) onCancelBackupRestore() },
            title = { Text("Revisá antes de restaurar") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    Text("Copia válida · ${preview.entryCount} elementos", style = MaterialTheme.typography.labelLarge)
                    BackupPreviewLine("Configuración DNS", preview.hasDnsConfig)
                    BackupPreviewLine("Excepciones DNS", preview.hasAllowlist)
                    BackupPreviewLine("Selección del catálogo", preview.hasEnabledLists)
                    BackupPreviewLine("Fuentes personalizadas", preview.hasCustomSources)
                    BackupPreviewLine("Reglas del firewall", preview.hasFirewallRules)
                    BackupPreviewLine("Perfiles del firewall", preview.hasFirewallProfiles)
                    if (preview.savedSourceCount > 0) {
                        Text("También incluye ${preview.savedSourceCount} listas locales guardadas.", style = MaterialTheme.typography.bodySmall)
                    }
                    HorizontalDivider(Modifier.padding(vertical = 2.dp), color = MaterialTheme.colorScheme.surfaceVariant)
                    Text("Se guardará una copia del estado actual antes de aplicar. El módulo se reinicia al terminar.", style = MaterialTheme.typography.bodySmall)
                    Text(
                        if (preview.includesActivity) "Incluye actividad DNS." else "El historial DNS queda en este teléfono y no se reemplaza.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Text("Las cachés descargadas no viajan en la copia; si restaurás en otro teléfono, prepará de nuevo las listas que necesites.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("Si usás NextDNS, la copia puede contener el ID de tu perfil.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.tertiary)
                    if (state.busyAction?.startsWith("Restaurando la copia") == true) {
                        LinearProgressIndicator(Modifier.fillMaxWidth())
                        Text("Validando los cambios y aplicando la copia…", style = MaterialTheme.typography.bodySmall)
                    }
                }
            },
            confirmButton = {
                Button(onClick = onConfirmBackupRestore, enabled = state.busyAction == null) { Text("Restaurar copia") }
            },
            dismissButton = { TextButton(onClick = onCancelBackupRestore, enabled = state.busyAction == null) { Text("Cancelar") } },
            containerColor = MaterialTheme.colorScheme.surface,
        )
    }
}

@Composable
private fun BackupPreviewLine(label: String, included: Boolean) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Icon(
            if (included) Icons.Outlined.CheckCircle else Icons.Outlined.Info,
            contentDescription = null,
            tint = if (included) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(17.dp),
        )
        Spacer(Modifier.width(8.dp))
        Text("$label: ${if (included) "se reemplaza" else "se conserva actual"}", style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun QuietCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    body: String,
) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Row(Modifier.fillMaxWidth().padding(15.dp), verticalAlignment = Alignment.Top) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 1.dp).size(19.dp))
            Spacer(Modifier.width(11.dp))
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Text(body, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun ConfirmDialog(
    title: String,
    body: String,
    confirm: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(body) },
        confirmButton = { Button(onClick = onConfirm) { Text(confirm) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Volver") } },
        containerColor = MaterialTheme.colorScheme.surface,
    )
}

@Composable
private fun LoadingScreen() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(13.dp)) {
            CircularProgressIndicator()
            Text("Conectando con el módulo…", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                "Si KernelSU Next pide permiso root, tocá Permitir. Si la conexión no responde en unos segundos, aparecerá un mensaje para reintentar.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = 28.dp),
            )
        }
    }
}

@Composable
private fun RootRequiredScreen(message: String?, onRetry: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.background, modifier = Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(28.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(72.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
                Icon(Icons.Outlined.Security, contentDescription = null, modifier = Modifier.size(34.dp), tint = MaterialTheme.colorScheme.primary)
            }
            Spacer(Modifier.height(18.dp))
            Text("No se pudo conectar con el módulo", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(8.dp))
            Text("Comprobá que DNSCrypt Manager esté instalado y activo, y que KernelSU Next haya concedido acceso root a esta app.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (!message.isNullOrBlank()) Text(message, Modifier.padding(top = 12.dp), color = MaterialTheme.colorScheme.error)
            Spacer(Modifier.height(18.dp))
            Button(onClick = onRetry) { Text("Reintentar conexión") }
        }
    }
}

@Composable
private fun ErrorScreen(message: String, onRetry: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(38.dp))
        Spacer(Modifier.height(12.dp))
        Text("No se pudo conectar", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text(message, Modifier.padding(top = 10.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Button(onClick = onRetry, Modifier.padding(top = 18.dp)) { Text("Reintentar") }
    }
}

@Composable
private fun EmptyState(title: String, message: String) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 22.dp, vertical = 35.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
    }
}

private fun matchesCatalog(entry: CatalogEntry, query: String, recommendedOnly: Boolean, activeOnly: Boolean): Boolean {
    if (recommendedOnly && !entry.recommended) return false
    if (activeOnly && !entry.enabled) return false
    val clean = query.trim()
    if (clean.isBlank()) return true
    val translatedCategories = entry.categories.split(',').joinToString(" ") { categoryLabel(it.trim()) }
    return entry.displayName().contains(clean, true) || entry.name.contains(clean, true) || entry.id.contains(clean, true) ||
        translatedCategories.contains(clean, true) || entry.subgroup.contains(clean, true)
}

private fun CatalogEntry.displayName(): String = sourceName.ifBlank { name.ifBlank { id } }

private fun normalizedGroupKey(key: String): String = if (key == "rethink_unassigned") "RethinkUnassigned" else key

private fun groupLabel(key: String): String = when (key) {
    "Security" -> "Seguridad"
    "Privacy" -> "Privacidad"
    "ParentalControl" -> "Control parental"
    "dcm" -> "Otras fuentes"
    "RethinkUnassigned" -> "Sin categoría"
    else -> key
}

private fun categoryLabel(key: String): String = when (key.lowercase(Locale.ROOT).replace('-', '_')) {
    "ads", "advertising", "mobile_ads", "in_app_ads" -> "publicidad"
    "trackers", "tracking" -> "rastreadores"
    "malware", "threats", "badware" -> "malware"
    "phishing" -> "phishing"
    "scams", "fake_stores" -> "estafas"
    "cryptomining", "cryptomining_mining" -> "minería de criptomonedas"
    "adult", "adult_content" -> "contenido adulto"
    "parental", "parental_control" -> "control parental"
    else -> key.replace('_', ' ')
}

private fun aggressivenessLabel(value: String): String = when (value.lowercase(Locale.ROOT)) {
    "low", "low_medium" -> "Suave"
    "medium" -> "Media"
    "high" -> "Alta"
    "very_high", "extreme" -> "Muy alta"
    else -> "Sin nivel"
}

private fun activityLabel(status: String): String = when (status.lowercase(Locale.ROOT)) {
    "blocked" -> "Bloqueado"
    "allowed" -> "Permitido"
    "allowlisted" -> "Excepción"
    "error" -> "Error"
    else -> status.ifBlank { "Consulta" }
}

private fun formatTimestamp(value: String): String = value.trim().removePrefix("[").removeSuffix("]").ifBlank { "—" }

private fun resolverLabel(server: String): String {
    val clean = server.trim().removePrefix("[").removeSuffix("]")
    val lower = clean.lowercase(Locale.ROOT)
    return when {
        lower.startsWith("nextdns-") -> "NextDNS · ${clean.substringAfter('-', "").take(10)}"
        lower == "cloudflare" -> "Cloudflare"
        lower == "quad9" -> "Quad9"
        lower == "adguard" -> "AdGuard"
        lower == "mullvad" -> "Mullvad"
        lower.isBlank() || lower == "(automatico)" -> "Automático"
        else -> clean
    }
}

private fun validDomainForForm(domain: String): Boolean {
    val regex = Regex("^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
    return regex.matches(domain) && !Regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$").matches(domain)
}

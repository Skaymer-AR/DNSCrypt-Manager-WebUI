package ar.skaymer.dnscryptmanager.ui

import androidx.compose.foundation.background
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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import androidx.lifecycle.viewmodel.compose.viewModel
import ar.skaymer.dnscryptmanager.ActivityEvent
import ar.skaymer.dnscryptmanager.CatalogEntry
import ar.skaymer.dnscryptmanager.DnsCryptUiState
import ar.skaymer.dnscryptmanager.DnsCryptViewModel
import java.util.Locale
import kotlinx.coroutines.delay

private enum class Tab(val label: String) {
    HOME("Inicio"),
    ACTIVITY("Actividad"),
    LISTS("Listas"),
    SETTINGS("Ajustes"),
}

@Composable
internal fun DnsCryptApp(viewModel: DnsCryptViewModel = viewModel()) {
    val state by viewModel.state.collectAsState()
    var tab by rememberSaveable { mutableStateOf(Tab.HOME.name) }
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
            else -> Unit
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
                )
                Tab.ACTIVITY -> ActivityScreen(
                    state = state,
                    onRefresh = viewModel::refresh,
                    onClear = viewModel::clearActivity,
                    onEnable = { viewModel.setActivityEnabled(true) },
                )
                Tab.LISTS -> ListsScreen(
                    state = state,
                    onRefresh = viewModel::refreshCatalog,
                    onSelectGroup = { viewModel.loadCatalogGroup(it) },
                    onSetEnabled = viewModel::setCatalogEnabled,
                    onStartDownloadAll = viewModel::startDownloadAll,
                    onRefreshProgress = viewModel::refreshDownloadProgress,
                    onLoadAllowlist = viewModel::loadAllowlist,
                    onAddAllowlist = viewModel::addAllowlist,
                    onRemoveAllowlist = viewModel::removeAllowlist,
                )
                Tab.SETTINGS -> SettingsScreen(
                    state = state,
                    onRefresh = viewModel::refresh,
                    onSetProvider = viewModel::setProvider,
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
    Tab.LISTS -> Icons.Outlined.List
    Tab.SETTINGS -> Icons.Outlined.Settings
}

@Composable
private fun HomeScreen(
    state: DnsCryptUiState,
    onRefresh: () -> Unit,
    onActivityToggle: (Boolean) -> Unit,
    onOpenActivity: () -> Unit,
) {
    val snapshot = state.snapshot ?: return
    val status = snapshot.status
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        ScreenHeader("Tu DNS", "Protección y actividad de la red", onRefresh, state.busyAction != null || state.loading)
        StatusHero(status.running && status.listening && status.redirectActive, status.running && status.listening, status.redirectActive)
        ActivityStatsGrid(state)
        ResolverCard(status.server, status.version)
        ActivityControlCard(
            enabled = status.activityEnabled,
            supported = snapshot.activitySupported,
            busy = state.busyAction != null,
            onToggle = onActivityToggle,
        )
        SectionHeading("Actividad reciente", "Consultas DNS de este dispositivo", onOpenActivity)
        if (snapshot.events.isEmpty()) {
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
            MetricCard("Consultas", stats.total, "en el registro local", Icons.Outlined.Dns, Modifier.weight(1f))
            MetricCard("Bloqueadas", stats.blocked, "por una regla DNS", Icons.Outlined.Security, Modifier.weight(1f), MaterialTheme.colorScheme.error)
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            MetricCard("Permitidas", stats.allowed, "respuestas normales", Icons.Outlined.CheckCircle, Modifier.weight(1f))
            MetricCard("Excepciones", stats.allowlisted, "permitidas por vos", Icons.Outlined.Info, Modifier.weight(1f), MaterialTheme.colorScheme.secondary)
        }
    }
}

@Composable
private fun MetricCard(
    label: String,
    value: Int,
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
            Text(value.toString(), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
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
) {
    val snapshot = state.snapshot ?: return
    var filter by rememberSaveable { mutableStateOf("todas") }
    var query by rememberSaveable { mutableStateOf("") }
    var showClearDialog by remember { mutableStateOf(false) }
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
        ScreenHeader("Actividad", "Dominios consultados y resultado", onRefresh, state.loading || state.busyAction != null)
        Spacer(Modifier.height(12.dp))
        if (!snapshot.activitySupported) {
            QuietCard(Icons.Outlined.Info, "Registro no disponible", "La versión instalada del módulo todavía no expone la actividad DNS local.")
            return@Column
        }
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
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            MiniMetric("Total", snapshot.stats.total, Modifier.weight(1f))
            MiniMetric("Bloqueadas", snapshot.stats.blocked, Modifier.weight(1f), MaterialTheme.colorScheme.error)
            MiniMetric("Permitidas", snapshot.stats.allowed + snapshot.stats.allowlisted, Modifier.weight(1f))
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
            TextButton(onClick = { showClearDialog = true }, enabled = state.busyAction == null && snapshot.events.isNotEmpty()) {
                Icon(Icons.Outlined.Delete, contentDescription = null, modifier = Modifier.size(17.dp))
                Spacer(Modifier.width(4.dp))
                Text("Borrar")
            }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.surfaceVariant)
        if (filtered.isEmpty()) {
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                EmptyState("No hay resultados", "Probá otra búsqueda o filtro.")
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f).padding(top = 9.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) { items(filtered, key = { "${it.time}-${it.domain}-${it.status}" }) { ActivityRow(it) } }
        }
        Text(
            "La actividad muestra consultas DNS. Todavía no identifica de forma confiable qué app las inició.",
            modifier = Modifier.padding(top = 9.dp, bottom = 3.dp),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
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
}

@Composable
private fun MiniMetric(label: String, value: Int, modifier: Modifier, tint: Color = MaterialTheme.colorScheme.primary) {
    Card(modifier, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 11.dp, vertical = 10.dp)) {
            Text(value.toString(), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = tint)
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun ActivityRow(event: ActivityEvent) {
    val tint = when (event.status) {
        "blocked" -> MaterialTheme.colorScheme.error
        "allowed", "allowlisted" -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.tertiary
    }
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(9.dp).clip(CircleShape).background(tint))
            Spacer(Modifier.width(11.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(event.domain.ifBlank { "Dominio desconocido" }, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold)
                val detail = listOfNotNull(
                    event.category.takeIf { it.isNotBlank() }?.let(::categoryLabel),
                    event.rule.takeIf { it.isNotBlank() },
                ).joinToString(" · ")
                Text(detail.ifBlank { "Consulta DNS" }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
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
private fun ListsScreen(
    state: DnsCryptUiState,
    onRefresh: () -> Unit,
    onSelectGroup: (String) -> Unit,
    onSetEnabled: (CatalogEntry, Boolean) -> Unit,
    onStartDownloadAll: () -> Unit,
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
private fun SettingsScreen(state: DnsCryptUiState, onRefresh: () -> Unit, onSetProvider: (String, String) -> Unit) {
    val snapshot = state.snapshot ?: return
    val current = snapshot.status.server.lowercase(Locale.ROOT).trim().removePrefix("[").removeSuffix("]")
    var pendingProvider by remember { mutableStateOf<String?>(null) }
    var nextDnsId by rememberSaveable { mutableStateOf("") }
    var pendingNextDns by remember { mutableStateOf(false) }
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
        QuietCard(
            Icons.Outlined.History,
            "Actividad DNS en este teléfono",
            if (snapshot.status.activityEnabled) "El registro está activo. Se puede apagar en Inicio; la información queda guardada localmente con límites de retención." else "El registro está apagado. No se anotan consultas nuevas.",
        )
        QuietCard(
            Icons.Outlined.Info,
            "Todavía no identifica la aplicación",
            "La primera etapa muestra dominios y resultados DNS. No atribuye una consulta a una app sin una fuente de datos confiable.",
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
            Text("Hace falta acceso root", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(8.dp))
            Text("Esta app se conecta al módulo DNSCrypt del teléfono. Aprobá el acceso root en KernelSU y asegurate de tener instalado el módulo.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (!message.isNullOrBlank()) Text(message, Modifier.padding(top = 12.dp), color = MaterialTheme.colorScheme.error)
            Spacer(Modifier.height(18.dp))
            Button(onClick = onRetry) { Text("Volver a intentar") }
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

package ar.skaymer.dnscryptmanager.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.collectAsState
import androidx.lifecycle.viewmodel.compose.viewModel
import ar.skaymer.dnscryptmanager.ActivityEvent
import ar.skaymer.dnscryptmanager.DnsCryptViewModel
import ar.skaymer.dnscryptmanager.DnsCryptUiState

private enum class Tab(val label: String, val glyph: String) {
    HOME("Home", "⌂"),
    ACTIVITY("Activity", "≋"),
    LISTS("Lists", "▤"),
    SETTINGS("Settings", "⋯"),
}

@Composable
fun DnsCryptApp(viewModel: DnsCryptViewModel = viewModel()) {
    val state by viewModel.state.collectAsState()
    var tabIndex by rememberSaveable { mutableIntStateOf(0) }

    if (!state.rootAvailable && !state.loading) {
        RootRequiredScreen(state.error, viewModel::refresh)
        return
    }

    DcmScaffold(
        tab = Tab.entries[tabIndex],
        onTabChange = { tabIndex = it.ordinal },
    ) {
        when {
            state.loading && state.snapshot == null -> LoadingScreen()
            state.snapshot == null -> ErrorScreen(state.error ?: "No se pudo cargar el módulo", viewModel::refresh)
            else -> when (Tab.entries[tabIndex]) {
                Tab.HOME -> HomeScreen(state, viewModel::refresh, viewModel::setActivityEnabled)
                Tab.ACTIVITY -> ActivityScreen(state, viewModel::refresh, viewModel::clearActivity)
                Tab.LISTS -> ListsScreen()
                Tab.SETTINGS -> SettingsScreen(state, viewModel::refresh)
            }
        }
    }
}

@Composable
private fun DcmScaffold(
    tab: Tab,
    onTabChange: (Tab) -> Unit,
    content: @Composable () -> Unit,
) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                Tab.entries.forEach { item ->
                    NavigationBarItem(
                        selected = item == tab,
                        onClick = { onTabChange(item) },
                        icon = { Text(item.glyph, style = MaterialTheme.typography.titleMedium) },
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
private fun HomeScreen(
    state: DnsCryptUiState,
    onRefresh: () -> Unit,
    onActivityToggle: (Boolean) -> Unit,
) {
    val snapshot = state.snapshot ?: return
    val status = snapshot.status
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Header("DNSCrypt Manager", "Local DNS control")
        StatusHero(status.running && status.listening, status.redirectActive)
        MetricsRow(snapshot)
        ProviderCard(status.server, status.version, onRefresh)
        ActivityCard(
            enabled = status.activityEnabled,
            supported = snapshot.activitySupported,
            onToggle = onActivityToggle,
        )
        Text(
            "The module remains the DNS engine. This app only controls it through the root bridge.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun Header(title: String, subtitle: String) {
    Column {
        Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun StatusHero(protected: Boolean, redirectActive: Boolean) {
    val accent = if (protected) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.error
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(28.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(20.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier.size(72.dp).clip(CircleShape).background(accent.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(16.dp).clip(CircleShape).background(accent))
            }
            Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    if (protected) "Protected" else "DNS stopped",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    if (redirectActive) "System DNS redirect is active" else "Proxy is local-only",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun MetricsRow(snapshot: DnsCryptUiState) {
    val stats = snapshot.snapshot?.stats ?: return
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Metric("Queries", stats.total, Modifier.weight(1f))
        Metric("Blocked", stats.blocked, Modifier.weight(1f), MaterialTheme.colorScheme.error)
        Metric("Allowed", stats.allowed + stats.allowlisted, Modifier.weight(1f), MaterialTheme.colorScheme.secondary)
    }
}

@Composable
private fun Metric(label: String, value: Int, modifier: Modifier, accent: Color = MaterialTheme.colorScheme.primary) {
    Card(modifier, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(13.dp)) {
            Text(value.toString(), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = accent)
            Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ProviderCard(server: String, version: String, onRefresh: () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("DNS provider", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(server.ifBlank { "Unknown" }, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                }
                AssistChip(onClick = onRefresh, label = { Text("Refresh") })
            }
            Text("dnscrypt-proxy $version", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ActivityCard(enabled: Boolean, supported: Boolean, onToggle: (Boolean) -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Row(
            Modifier.fillMaxWidth().padding(18.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text("DNS activity", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(
                    when {
                        !supported -> "Update the module to enable local activity"
                        enabled -> "Queries are recorded locally for a short period"
                        else -> "Off by default; nothing new is recorded"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Switch(checked = enabled, onCheckedChange = onToggle, enabled = supported)
        }
    }
}

@Composable
private fun ActivityScreen(state: DnsCryptUiState, onRefresh: () -> Unit, onClear: () -> Unit) {
    val snapshot = state.snapshot ?: return
    var filter by rememberSaveable { mutableStateOf("All") }
    val filters = listOf("All", "Blocked", "Allowed", "Allowlist", "Errors")
    val filtered = snapshot.events.filter { event ->
        when (filter) {
            "Blocked" -> event.status == "blocked"
            "Allowed" -> event.status == "allowed"
            "Allowlist" -> event.status == "allowlisted"
            "Errors" -> event.status == "error"
            else -> true
        }
    }
    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp, vertical = 16.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Activity", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text("Only local DNS events", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            OutlinedButton(onClick = onRefresh) { Text("Refresh") }
        }
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            filters.forEach { item ->
                FilterChip(selected = filter == item, onClick = { filter = item }, label = { Text(item) })
            }
        }
        Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("${filtered.size} shown", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onClear) { Text("Clear") }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.surfaceVariant)
        if (filtered.isEmpty()) {
            EmptyState("No DNS activity yet", "Enable DNS activity from Home to populate this view.")
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 10.dp)) {
                items(filtered) { event -> ActivityRow(event) }
            }
        }
    }
}

@Composable
private fun ActivityRow(event: ActivityEvent) {
    val color = when (event.status) {
        "blocked" -> MaterialTheme.colorScheme.error
        "allowlisted", "allowed" -> MaterialTheme.colorScheme.secondary
        else -> MaterialTheme.colorScheme.tertiary
    }
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(10.dp).clip(CircleShape).background(color))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(event.domain, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold)
                Text(
                    listOfNotNull(event.category.takeIf { it.isNotBlank() }, event.rule.takeIf { it.isNotBlank() }).joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(event.status, color = color, style = MaterialTheme.typography.labelMedium)
                Text(event.time.removePrefix("[").removeSuffix("]"), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun ListsScreen() {
    val categories = listOf(
        "Malware" to "Recommended protection",
        "Phishing" to "Recommended protection",
        "Scams" to "Recommended protection",
        "Trackers" to "Optional privacy layer",
        "Ads" to "Optional privacy layer",
        "Cryptomining" to "Optional protection",
    )
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Header("Lists", "Categories and sources from the module catalog")
        Text("The native catalog surface is intentionally simple first. Downloads remain background jobs and never activate a source automatically.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        categories.forEach { (name, description) ->
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        Text(description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text("›", style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}

@Composable
private fun SettingsScreen(state: DnsCryptUiState, onRefresh: () -> Unit) {
    val snapshot = state.snapshot ?: return
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Header("Settings", "Advanced controls stay in the shared module")
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Module connection", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text("${if (snapshot.status.running) "Running" else "Stopped"} · ${snapshot.status.server}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("Root bridge: fixed CLI allowlist", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button(onClick = onRefresh) { Text("Refresh module state") }
            }
        }
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("App monitoring", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text("Per-app attribution is not claimed in the first safe stage. DNS activity can show domains, but not reliably identify the calling app without a separate measured backend.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Text("WebUI advanced panel: keep available for catalog diagnostics, rollback and rescue.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun LoadingScreen() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("Loading module…") }
}

@Composable
private fun RootRequiredScreen(message: String?, onRetry: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.background, modifier = Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(28.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Root access required", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(10.dp))
            Text("DNSCrypt Manager is controlled through KernelSU/Magisk root and the installed module. No VPN is created by this app.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (!message.isNullOrBlank()) Text(message, Modifier.padding(top = 12.dp), color = MaterialTheme.colorScheme.error)
            Spacer(Modifier.height(18.dp))
            Button(onClick = onRetry) { Text("Try again") }
        }
    }
}

@Composable
private fun ErrorScreen(message: String, onRetry: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Text("Could not load the module", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text(message, Modifier.padding(top = 10.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Button(onClick = onRetry, Modifier.padding(top = 18.dp)) { Text("Retry") }
    }
}

@Composable
private fun EmptyState(title: String, message: String) {
    Column(Modifier.fillMaxWidth().padding(vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text(message, Modifier.padding(top = 6.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

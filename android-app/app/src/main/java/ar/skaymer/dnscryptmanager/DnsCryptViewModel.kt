package ar.skaymer.dnscryptmanager

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

internal class DnsCryptViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = DnsCryptRepository(RootShell(application.cacheDir))
    private val _state = MutableStateFlow(DnsCryptUiState())
    val state: StateFlow<DnsCryptUiState> = _state.asStateFlow()

    init { refresh() }

    fun refresh() {
        if (_state.value.busyAction != null) return
        if (_state.value.loading && _state.value.snapshot != null) return
        _state.value = _state.value.copy(loading = true, error = null)
        viewModelScope.launch {
            try {
                _state.value = _state.value.copy(
                    loading = false,
                    rootAvailable = true,
                    snapshot = repository.loadSnapshot(),
                    error = null,
                )
                refreshActivityData()
            } catch (error: RootBridgeException) {
                _state.value = _state.value.copy(
                    loading = false,
                    rootAvailable = false,
                    error = error.message ?: "No se pudo conectar con el módulo.",
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    loading = false,
                    error = error.message ?: "No se pudo leer el módulo.",
                )
            }
        }
    }

    fun loadCatalog() {
        if (_state.value.catalogLoading || _state.value.busyAction != null) return
        viewModelScope.launch {
            _state.value = _state.value.copy(catalogLoading = true, error = null)
            try {
                val groups = repository.loadCatalogGroups()
                _state.value = _state.value.copy(catalogGroups = groups)
                loadCatalogGroupInternal(_state.value.selectedCatalogGroup)
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    catalogLoading = false,
                    error = error.message ?: "No se pudo cargar el catálogo.",
                )
            }
        }
    }

    fun loadCatalogGroup(group: String, force: Boolean = false) {
        if (_state.value.catalogLoading || _state.value.busyAction != null) return
        if (!force && _state.value.selectedCatalogGroup == group && _state.value.catalogLoaded) return
        viewModelScope.launch {
            _state.value = _state.value.copy(
                catalogLoading = true,
                selectedCatalogGroup = group,
                catalogEntries = emptyList(),
                catalogLoaded = false,
                error = null,
            )
            try {
                loadCatalogGroupInternal(group)
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    catalogLoading = false,
                    error = error.message ?: "No se pudo cargar esta categoría.",
                )
            }
        }
    }

    private suspend fun loadCatalogGroupInternal(group: String) {
        val entries = repository.loadCatalogGroup(group)
        _state.value = _state.value.copy(
            catalogEntries = entries,
            selectedCatalogGroup = group,
            catalogLoading = false,
            catalogLoaded = true,
        )
    }

    fun refreshCatalog() {
        if (_state.value.busyAction != null) return
        val group = _state.value.selectedCatalogGroup
        viewModelScope.launch {
            _state.value = _state.value.copy(catalogLoading = true, error = null)
            try {
                val groups = repository.loadCatalogGroups()
                _state.value = _state.value.copy(catalogGroups = groups)
                loadCatalogGroupInternal(group)
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    catalogLoading = false,
                    error = error.message ?: "No se pudo actualizar el catálogo.",
                )
            }
        }
    }

    fun refreshDownloadProgress() {
        viewModelScope.launch {
            runCatching { repository.loadDownloadProgress() }
                .onSuccess { _state.value = _state.value.copy(downloadProgress = it) }
        }
    }

    fun loadAllowlist() {
        if (_state.value.allowlistLoading || _state.value.busyAction != null) return
        viewModelScope.launch {
            _state.value = _state.value.copy(allowlistLoading = true, error = null)
            try {
                _state.value = _state.value.copy(allowlist = repository.loadAllowlist(), allowlistLoading = false)
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    allowlistLoading = false,
                    error = error.message ?: "No se pudo leer la lista de excepciones.",
                )
            }
        }
    }

    fun setActivityEnabled(enabled: Boolean) = runAction(
        action = if (enabled) "Activando el registro DNS…" else "Pausando el registro DNS…",
        success = if (enabled) "Registro local de actividad activado." else "Registro local de actividad pausado.",
        operation = { repository.setActivityEnabled(enabled) },
        afterSuccess = { refreshSnapshot() },
    )

    fun clearActivity() = runAction(
        action = "Borrando la actividad…",
        success = "La actividad DNS local se borró.",
        operation = { repository.clearActivity() },
        afterSuccess = { refreshSnapshot() },
    )

    fun setCatalogEnabled(entry: CatalogEntry, enabled: Boolean) = runAction(
        action = if (enabled) "Preparando ${entry.displayName()}…" else "Desactivando ${entry.displayName()}…",
        success = if (enabled) "Fuente activada: ${entry.displayName()}" else "Fuente desactivada: ${entry.displayName()}",
        operation = { repository.setCatalogEnabled(entry, enabled) },
        afterSuccess = {
            loadCatalogGroupInternal(_state.value.selectedCatalogGroup)
            _state.value = _state.value.copy(catalogGroups = repository.loadCatalogGroups())
            refreshSnapshot()
        },
    )

    fun startDownloadAll() = runAction(
        action = "Preparando las fuentes…",
        success = "Descarga iniciada. Las fuentes nuevas siguen apagadas.",
        operation = { repository.startDownloadAll() },
        afterSuccess = {
            _state.value = _state.value.copy(downloadProgress = repository.loadDownloadProgress())
        },
    )

    fun addAllowlist(domain: String) = runAction(
        action = "Agregando la excepción…",
        success = "Dominio agregado a la lista de permitidos.",
        operation = { repository.addAllowlist(domain) },
        afterSuccess = { _state.value = _state.value.copy(allowlist = repository.loadAllowlist()) },
    )

    fun removeAllowlist(domain: String) = runAction(
        action = "Quitando la excepción…",
        success = "Dominio eliminado de la lista de permitidos.",
        operation = { repository.removeAllowlist(domain) },
        afterSuccess = { _state.value = _state.value.copy(allowlist = repository.loadAllowlist()) },
    )

    fun setProvider(provider: String, nextDnsId: String = "") = runAction(
        action = "Cambiando el DNS y reiniciando el servicio…",
        success = "DNS actualizado. El servicio volvió a iniciarse.",
        operation = { repository.setProvider(provider, nextDnsId) },
        afterSuccess = { refreshSnapshot() },
    )

    fun refreshFirewall() {
        if (_state.value.firewallLoading || _state.value.busyAction != null) return
        viewModelScope.launch {
            _state.value = _state.value.copy(firewallLoading = true, firewallError = null)
            try {
                val data = repository.loadFirewallData()
                _state.value = _state.value.copy(
                    firewall = data.support,
                    firewallBlockedUids = data.blockedUids,
                    firewallLoading = false,
                    firewallError = data.error,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    firewallLoading = false,
                    firewallError = error.message ?: "No se pudo consultar el firewall.",
                )
            }
        }
    }

    fun setAppBlocked(packageNames: List<String>, blocked: Boolean) = runAction(
        action = if (blocked) "Bloqueando la conexión de la app…" else "Permitiendo la conexión de la app…",
        success = if (blocked) "Se bloqueó la conexión de la app." else "Se permitió la conexión de la app.",
        operation = {
            if (blocked) repository.blockApp(packageNames.first()) else repository.allowApps(packageNames)
        },
        afterSuccess = { refreshFirewall() },
    )

    fun clearAllAppBlocks() = runAction(
        action = "Quitando los bloqueos del firewall…",
        success = "Se quitaron todos los bloqueos por app.",
        operation = { repository.clearAllAppBlocks() },
        afterSuccess = { refreshFirewall() },
    )

    fun clearFeedback() {
        _state.value = _state.value.copy(error = null, notice = null)
    }

    private fun runAction(
        action: String,
        success: String,
        operation: suspend () -> RootShell.Result,
        afterSuccess: suspend () -> Unit,
    ) {
        if (_state.value.busyAction != null) return
        viewModelScope.launch {
            _state.value = _state.value.copy(busyAction = action, error = null, notice = null)
            try {
                val result = operation()
                if (!result.ok) {
                    _state.value = _state.value.copy(
                        busyAction = null,
                        error = result.output.ifBlank { "La operación no se pudo completar." },
                    )
                    return@launch
                }
                _state.value = _state.value.copy(busyAction = null, notice = success)
                afterSuccess()
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                _state.value = _state.value.copy(
                    busyAction = null,
                    error = error.message ?: "La operación no se pudo completar.",
                )
            }
        }
    }

    private suspend fun refreshSnapshot() {
        _state.value = _state.value.copy(loading = true)
        try {
            _state.value = _state.value.copy(snapshot = repository.loadSnapshot(), loading = false, rootAvailable = true)
            refreshActivityData()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            _state.value = _state.value.copy(loading = false, error = error.message ?: "No se pudo actualizar el estado.")
        }
    }

    private suspend fun refreshActivityData() {
        val snapshot = _state.value.snapshot ?: return
        if (!snapshot.activitySupported) {
            _state.value = _state.value.copy(activityLoading = false, activityError = null)
            return
        }
        if (_state.value.activityLoading) return

        _state.value = _state.value.copy(activityLoading = true, activityError = null)
        val errors = mutableListOf<String>()
        try {
            val stats = repository.loadActivityStats()
            val latestSnapshot = _state.value.snapshot ?: snapshot
            _state.value = _state.value.copy(snapshot = latestSnapshot.copy(stats = stats))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            errors += error.message ?: "No se pudieron leer los contadores DNS."
        }
        try {
            val events = repository.loadActivityEvents()
            val latestSnapshot = _state.value.snapshot ?: snapshot
            _state.value = _state.value.copy(snapshot = latestSnapshot.copy(events = events))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            errors += error.message ?: "No se pudieron leer los dominios consultados."
        }
        _state.value = _state.value.copy(
            activityLoading = false,
            activityError = errors.distinct().joinToString("\n").ifBlank { null },
        )
    }
}

private fun CatalogEntry.displayName(): String = sourceName.ifBlank { name.ifBlank { id } }

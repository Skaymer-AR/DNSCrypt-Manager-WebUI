package ar.skaymer.dnscryptmanager

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

internal class DnsCryptViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application
    private val repository = DnsCryptRepository(app, RootShell(app, application.cacheDir))
    private val _state = MutableStateFlow(DnsCryptUiState())
    val state: StateFlow<DnsCryptUiState> = _state.asStateFlow()

    init {
        app.cacheDir.listFiles { _, name -> name.startsWith("dcm-backup-import-") && name.endsWith(".tar.gz") }
            ?.forEach { it.delete() }
        refresh()
    }

    override fun onCleared() {
        _state.value.restoreBackupPath?.let { java.io.File(it).delete() }
        super.onCleared()
    }

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
                    error = error.message ?: app.getString(R.string.vmodel_module_connection_error),
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    loading = false,
                    error = error.message ?: app.getString(R.string.vmodel_module_read_error),
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
                    error = error.message ?: app.getString(R.string.vmodel_catalog_load_error),
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
                    error = error.message ?: app.getString(R.string.vmodel_category_load_error),
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
                    error = error.message ?: app.getString(R.string.vmodel_catalog_update_error),
                )
            }
        }
    }

    fun refreshLists() {
        refreshCatalog()
        refreshDownloadProgress()
    }

    fun refreshDownloadProgress() {
        if (_state.value.downloadProgressLoading) return
        _state.value = _state.value.copy(downloadProgressLoading = true)
        viewModelScope.launch {
            try {
                val progress = repository.loadDownloadProgress()
                _state.value = _state.value.copy(downloadProgress = progress, downloadProgressLoaded = true)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                // Leave the cached value visible; a later screen entry can retry.
            } finally {
                _state.value = _state.value.copy(downloadProgressLoading = false)
            }
        }
    }

    fun loadAllowlist() {
        if (_state.value.allowlistLoading || _state.value.busyAction != null) return
        viewModelScope.launch {
            _state.value = _state.value.copy(allowlistLoading = true, error = null)
            try {
                _state.value = _state.value.copy(allowlist = repository.loadAllowlist(), allowlistLoading = false, allowlistLoaded = true)
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    allowlistLoading = false,
                    error = error.message ?: app.getString(R.string.allowlist_read_error),
                )
            }
        }
    }

    fun setActivityEnabled(enabled: Boolean) = runAction(
        action = if (enabled) app.getString(R.string.vmodel_activity_enable_action) else app.getString(R.string.vmodel_activity_disable_action),
        success = if (enabled) app.getString(R.string.vmodel_activity_enabled) else app.getString(R.string.vmodel_activity_disabled),
        operation = { repository.setActivityEnabled(enabled) },
        afterSuccess = { refreshSnapshot() },
    )

    fun retryActivity() {
        if (_state.value.activityLoading || _state.value.busyAction != null) return
        viewModelScope.launch { refreshActivityData() }
    }

    fun clearActivity() = runAction(
        action = app.getString(R.string.vmodel_activity_clear_action),
        success = app.getString(R.string.vmodel_activity_cleared),
        operation = { repository.clearActivity() },
        afterSuccess = { refreshSnapshot() },
    )

    fun testDns() {
        if (_state.value.busyAction != null) return
        viewModelScope.launch {
            _state.value = _state.value.copy(busyAction = app.getString(R.string.vmodel_dns_testing), error = null, notice = null)
            try {
                val result = repository.testDns()
                _state.value = if (result.ok) {
                    _state.value.copy(busyAction = null, notice = result.output.ifBlank { app.getString(R.string.vmodel_dns_success) })
                } else {
                    _state.value.copy(busyAction = null, error = result.output.ifBlank { app.getString(R.string.vmodel_dns_failed) })
                }
                refreshSnapshot()
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                _state.value = _state.value.copy(busyAction = null, error = error.message ?: app.getString(R.string.vmodel_dns_error))
            }
        }
    }

    fun runDiagnostics() {
        if (_state.value.diagnosticsRunning || _state.value.busyAction != null) return
        viewModelScope.launch {
            _state.value = _state.value.copy(
                diagnosticsRunning = true,
                busyAction = app.getString(R.string.vmodel_diagnostics_running),
                error = null,
                notice = null,
            )
            try {
                val checks = repository.runDiagnostics()
                _state.value = _state.value.copy(diagnostics = checks, diagnosticsRunning = false, busyAction = null)
                refreshSnapshot()
                refreshFirewall()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    diagnostics = listOf(DiagnosticCheck(app.getString(R.string.vmodel_module_connection), "attention", error.message ?: app.getString(R.string.vmodel_diagnostics_error))),
                    diagnosticsRunning = false,
                    busyAction = null,
                )
            }
        }
    }

    fun setActivityRetention(days: Int, maxEntries: Int) = runAction(
        action = app.getString(R.string.vmodel_retention_action),
        success = app.getString(R.string.vmodel_retention_done),
        operation = { repository.setActivityRetention(days, maxEntries) },
        afterSuccess = { refreshSnapshot() },
        afterFailure = { refreshSnapshot() },
    )

    fun setCatalogEnabled(entry: CatalogEntry, enabled: Boolean) = runAction(
        action = if (enabled) app.getString(R.string.vmodel_catalog_enable_action, entry.displayName()) else app.getString(R.string.vmodel_catalog_disable_action, entry.displayName()),
        success = if (enabled) app.getString(R.string.vmodel_catalog_enabled, entry.displayName()) else app.getString(R.string.vmodel_catalog_disabled, entry.displayName()),
        operation = { repository.setCatalogEnabled(entry, enabled) },
        afterSuccess = {
            loadCatalogGroupInternal(_state.value.selectedCatalogGroup)
            _state.value = _state.value.copy(catalogGroups = repository.loadCatalogGroups())
            refreshSnapshot()
        },
    )

    fun setCatalogGroupEnabled(group: String, enabled: Boolean) = runAction(
        action = if (enabled) app.getString(R.string.vmodel_group_enable_action, catalogGroupLabel(app, group)) else app.getString(R.string.vmodel_group_disable_action, catalogGroupLabel(app, group)),
        success = "",
        operation = { repository.setCatalogGroupEnabled(group, enabled) },
        afterSuccess = {
            loadCatalogGroupInternal(_state.value.selectedCatalogGroup)
            _state.value = _state.value.copy(catalogGroups = repository.loadCatalogGroups())
            refreshSnapshot()
        },
        afterFailure = { refreshCatalog() },
    )

    fun startDownloadAll() = runAction(
        action = app.getString(R.string.vmodel_download_action),
        success = app.getString(R.string.vmodel_download_started),
        operation = { repository.startDownloadAll() },
        afterSuccess = {
            _state.value = _state.value.copy(
                downloadProgress = repository.loadDownloadProgress(),
                downloadProgressLoaded = true,
            )
        },
    )

    fun addAllowlist(domain: String) = runAction(
        action = app.getString(R.string.vmodel_allowlist_add_action),
        success = app.getString(R.string.vmodel_allowlist_added),
        operation = { repository.addAllowlist(domain) },
        afterSuccess = { _state.value = _state.value.copy(allowlist = repository.loadAllowlist()) },
    )

    fun removeAllowlist(domain: String) = runAction(
        action = app.getString(R.string.vmodel_allowlist_remove_action),
        success = app.getString(R.string.vmodel_allowlist_removed),
        operation = { repository.removeAllowlist(domain) },
        afterSuccess = { _state.value = _state.value.copy(allowlist = repository.loadAllowlist()) },
    )

    fun setProvider(provider: String, nextDnsId: String = "") = runAction(
        action = app.getString(R.string.vmodel_provider_action),
        success = app.getString(R.string.vmodel_provider_done),
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
                    firewallTemporaryRules = data.temporaryRules,
                    firewallProfiles = data.profiles,
                    firewallLoading = false,
                    firewallError = data.error,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    firewallLoading = false,
                    firewallError = error.message ?: app.getString(R.string.vmodel_firewall_error),
                )
            }
        }
    }

    fun setAppBlocked(packageNames: List<String>, blocked: Boolean) = runAction(
        action = if (blocked) app.getString(R.string.vmodel_app_block_action) else app.getString(R.string.vmodel_app_allow_action),
        success = if (blocked) app.getString(R.string.vmodel_app_blocked) else app.getString(R.string.vmodel_app_allowed),
        operation = {
            if (blocked) repository.blockApp(packageNames.first()) else repository.allowApps(packageNames)
        },
        afterSuccess = { refreshFirewall() },
        afterFailure = { refreshFirewall() },
    )

    fun setAppBlockedTemporarily(packageName: String, duration: String) = runAction(
        action = app.getString(R.string.vmodel_temp_block_action),
        success = app.getString(R.string.vmodel_temp_block_done),
        operation = { repository.blockAppTemporarily(packageName, duration) },
        afterSuccess = { refreshFirewall() },
    )

    fun saveFirewallProfile(name: String, packageNames: List<String>) = runAction(
        action = app.getString(R.string.vmodel_profile_save_action),
        success = app.getString(R.string.vmodel_profile_saved, name),
        operation = { repository.saveFirewallProfile(name, packageNames) },
        afterSuccess = { refreshFirewall() },
    )

    fun removeFirewallProfile(name: String) = runAction(
        action = app.getString(R.string.vmodel_profile_delete_action),
        success = app.getString(R.string.vmodel_profile_deleted, name),
        operation = { repository.removeFirewallProfile(name) },
        afterSuccess = { refreshFirewall() },
    )

    fun applyFirewallProfile(profile: FirewallProfile) = runAction(
        action = app.getString(R.string.vmodel_profile_apply_action, profile.name),
        success = app.getString(R.string.vmodel_profile_applied, profile.name),
        operation = {
            val current = repository.loadFirewallData()
            val apps = withContext(Dispatchers.IO) { FirewallAppInventory.load(app) }
            val desired = profile.packages.toSet()
            for (installed in apps) {
                val selectedPackage = installed.packageNames.firstOrNull() ?: continue
                val shouldBlock = installed.packageNames.any { it in desired }
                val isBlocked = installed.uid in current.blockedUids
                val isTemporary = installed.packageNames.any { it in current.temporaryRules }
                if (shouldBlock == isBlocked && !(shouldBlock && isTemporary)) continue
                val result = if (shouldBlock) {
                    repository.blockApp(selectedPackage)
                } else {
                    repository.allowApps(installed.packageNames)
                }
                if (!result.ok) return@runAction result
            }
            RootShell.Result(0, "")
        },
        afterSuccess = { refreshFirewall() },
        afterFailure = { refreshFirewall() },
    )

    fun clearAllAppBlocks() = runAction(
        action = app.getString(R.string.vmodel_firewall_clear_action),
        success = app.getString(R.string.vmodel_firewall_cleared),
        operation = { repository.clearAllAppBlocks() },
        afterSuccess = { refreshFirewall() },
    )

    fun refreshConnections() {
        if (_state.value.connectionsLoading || _state.value.busyAction != null) return
        viewModelScope.launch {
            _state.value = _state.value.copy(connectionsLoading = true, connectionsError = null)
            try {
                _state.value = _state.value.copy(
                    connections = repository.loadConnections(),
                    connectionsLoading = false,
                    connectionsError = null,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    connectionsLoading = false,
                    connectionsError = error.message ?: app.getString(R.string.vmodel_connections_read_error),
                )
            }
        }
    }

    fun exportBackup(uri: Uri) {
        if (_state.value.busyAction != null) return
        viewModelScope.launch {
            val file = java.io.File(app.cacheDir, "dcm-backup-${java.util.UUID.randomUUID()}.tar.gz")
            _state.value = _state.value.copy(busyAction = app.getString(R.string.vmodel_backup_create_action), error = null, notice = null)
            try {
                val result = repository.createBackup(file.absolutePath)
                if (!result.ok) {
                    _state.value = _state.value.copy(busyAction = null, error = result.output.ifBlank { app.getString(R.string.vmodel_backup_create_error) })
                    return@launch
                }
                withContext(Dispatchers.IO) {
                    require(file.isFile && file.length() in 1..MAX_BACKUP_BYTES) {
                        app.getString(R.string.vmodel_backup_size_error)
                    }
                    val output = app.contentResolver.openOutputStream(uri, "w")
                        ?: error(app.getString(R.string.vmodel_backup_open_error))
                    output.use { target -> file.inputStream().use { it.copyTo(target) } }
                }
                _state.value = _state.value.copy(busyAction = null, notice = app.getString(R.string.vmodel_backup_created))
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                _state.value = _state.value.copy(busyAction = null, error = error.message ?: app.getString(R.string.vmodel_backup_save_error))
            } finally {
                file.delete()
            }
        }
    }

    fun inspectBackup(uri: Uri) {
        if (_state.value.busyAction != null) return
        _state.value.restoreBackupPath?.let { java.io.File(it).delete() }
        viewModelScope.launch {
            val file = java.io.File(app.cacheDir, "dcm-backup-import-${java.util.UUID.randomUUID()}.tar.gz")
            _state.value = _state.value.copy(
                busyAction = app.getString(R.string.vmodel_backup_validate_action),
                error = null,
                notice = null,
                backupPreview = null,
                restoreBackupPath = null,
            )
            try {
                withContext(Dispatchers.IO) {
                    val input = app.contentResolver.openInputStream(uri) ?: error(app.getString(R.string.vmodel_backup_read_error))
                    input.use { source ->
                        file.outputStream().use { target ->
                            val buffer = ByteArray(8192)
                            var copied = 0L
                            while (true) {
                                val count = source.read(buffer)
                                if (count < 0) break
                                copied += count
                                require(copied <= MAX_BACKUP_BYTES) { app.getString(R.string.vmodel_backup_too_large) }
                                target.write(buffer, 0, count)
                            }
                        }
                    }
                }
                val preview = repository.inspectBackup(file.absolutePath)
                _state.value = _state.value.copy(
                    busyAction = null,
                    backupPreview = preview,
                    restoreBackupPath = file.absolutePath,
                )
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                _state.value = _state.value.copy(busyAction = null, error = error.message ?: app.getString(R.string.vmodel_backup_validate_error))
                file.delete()
            }
        }
    }

    fun dismissBackupPreview() {
        _state.value.restoreBackupPath?.let { java.io.File(it).delete() }
        _state.value = _state.value.copy(backupPreview = null, restoreBackupPath = null)
    }

    fun confirmBackupRestore() {
        val path = _state.value.restoreBackupPath ?: return
        if (_state.value.busyAction != null) return
        viewModelScope.launch {
            _state.value = _state.value.copy(busyAction = app.getString(R.string.vmodel_backup_restore_action), error = null, notice = null)
            try {
                val result = repository.restoreBackup(path)
                _state.value = if (result.ok) {
                    _state.value.copy(
                        busyAction = null,
                        backupPreview = null,
                        restoreBackupPath = null,
                        notice = app.getString(R.string.vmodel_backup_restored),
                    )
                } else {
                    _state.value.copy(
                        busyAction = null,
                        backupPreview = null,
                        restoreBackupPath = null,
                        error = result.output.ifBlank { app.getString(R.string.vmodel_backup_restore_error) },
                    )
                }
                refreshSnapshot()
                refreshFirewall()
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                _state.value = _state.value.copy(
                    busyAction = null,
                    backupPreview = null,
                    restoreBackupPath = null,
                    error = error.message ?: app.getString(R.string.vmodel_backup_restore_error),
                )
                refreshSnapshot()
                refreshFirewall()
            } finally {
                java.io.File(path).delete()
            }
        }
    }

    fun clearFeedback() {
        _state.value = _state.value.copy(error = null, notice = null)
    }

    private fun runAction(
        action: String,
        success: String,
        operation: suspend () -> RootShell.Result,
        afterSuccess: suspend () -> Unit,
        afterFailure: suspend () -> Unit = {},
    ) {
        if (_state.value.busyAction != null) return
        viewModelScope.launch {
            _state.value = _state.value.copy(busyAction = action, error = null, notice = null)
            try {
                val result = operation()
                if (!result.ok) {
                    _state.value = _state.value.copy(
                        busyAction = null,
                        error = result.output.ifBlank { app.getString(R.string.vmodel_operation_failed) },
                    )
                    afterFailure()
                    return@launch
                }
                _state.value = _state.value.copy(
                    busyAction = null,
                    notice = success.ifBlank { result.output.ifBlank { app.getString(R.string.vmodel_operation_done) } },
                )
                afterSuccess()
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                _state.value = _state.value.copy(
                    busyAction = null,
                    error = error.message ?: app.getString(R.string.vmodel_operation_failed),
                )
                runCatching { afterFailure() }
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
            _state.value = _state.value.copy(loading = false, error = error.message ?: app.getString(R.string.vmodel_state_update_error))
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
        try {
            val activity = repository.loadActivitySnapshot()
            val latestSnapshot = _state.value.snapshot ?: snapshot
            _state.value = _state.value.copy(
                snapshot = latestSnapshot.copy(
                    status = latestSnapshot.status.copy(activityEnabled = activity.enabled),
                    stats = activity.stats,
                    events = activity.events,
                ),
                activityLoading = false,
                activityError = null,
            )
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            _state.value = _state.value.copy(
                activityLoading = false,
                activityError = error.message ?: app.getString(R.string.vmodel_activity_read_error),
            )
        }
    }
}

private const val MAX_BACKUP_BYTES = 64L * 1024L * 1024L

private fun CatalogEntry.displayName(): String = sourceName.ifBlank { name.ifBlank { id } }

private fun catalogGroupLabel(app: Application, key: String): String = when (key) {
    "Security" -> app.getString(R.string.group_security)
    "Privacy" -> app.getString(R.string.group_privacy)
    "ParentalControl" -> app.getString(R.string.group_parental_control)
    "dcm" -> app.getString(R.string.group_other_sources)
    "RethinkUnassigned", "rethink_unassigned" -> app.getString(R.string.group_uncategorized)
    else -> key
}

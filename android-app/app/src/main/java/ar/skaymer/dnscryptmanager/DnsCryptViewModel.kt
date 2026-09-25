package ar.skaymer.dnscryptmanager

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

internal class DnsCryptViewModel : ViewModel() {
    private val repository = DnsCryptRepository()
    private val _state = MutableStateFlow(DnsCryptUiState())
    val state: StateFlow<DnsCryptUiState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        if (_state.value.loading && _state.value.snapshot != null) return
        _state.value = _state.value.copy(loading = true, error = null)
        viewModelScope.launch {
            try {
                _state.value = DnsCryptUiState(
                    loading = false,
                    rootAvailable = true,
                    snapshot = repository.loadSnapshot(),
                )
            } catch (error: RootBridgeException) {
                _state.value = DnsCryptUiState(
                    loading = false,
                    rootAvailable = false,
                    error = error.message ?: "Se requiere acceso root",
                )
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    loading = false,
                    error = error.message ?: "No se pudo leer el módulo",
                )
            }
        }
    }

    fun setActivityEnabled(enabled: Boolean) {
        viewModelScope.launch {
            val result = repository.setActivityEnabled(enabled)
            if (!result.ok) {
                _state.value = _state.value.copy(error = result.output.ifBlank { "No se pudo cambiar la actividad DNS" })
            }
            refresh()
        }
    }

    fun clearActivity() {
        viewModelScope.launch {
            val result = repository.clearActivity()
            if (!result.ok) {
                _state.value = _state.value.copy(error = result.output.ifBlank { "No se pudo borrar la actividad" })
            }
            refresh()
        }
    }
}


package ar.skaymer.dnscryptmanager.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DcmColors = darkColorScheme(
    primary = Color(0xFFB9C7FF),
    onPrimary = Color(0xFF172B61),
    secondary = Color(0xFF9DE6D2),
    onSecondary = Color(0xFF00382F),
    tertiary = Color(0xFFFFB59D),
    background = Color(0xFF090D13),
    surface = Color(0xFF111720),
    surfaceVariant = Color(0xFF202936),
    onSurface = Color(0xFFE7ECF5),
    onSurfaceVariant = Color(0xFFB8C2D2),
    error = Color(0xFFFFB4AB),
)

@Composable
fun DcmTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DcmColors,
        content = content,
    )
}


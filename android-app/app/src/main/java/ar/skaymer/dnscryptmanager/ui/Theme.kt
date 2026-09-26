package ar.skaymer.dnscryptmanager.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DcmColors = darkColorScheme(
    primary = Color(0xFF8DE4CD),
    onPrimary = Color(0xFF062C28),
    primaryContainer = Color(0xFF16463F),
    onPrimaryContainer = Color(0xFFB8F4E5),
    secondary = Color(0xFFB5C7FF),
    onSecondary = Color(0xFF172B61),
    secondaryContainer = Color(0xFF283B70),
    onSecondaryContainer = Color(0xFFDDE3FF),
    tertiary = Color(0xFFFFC897),
    background = Color(0xFF081116),
    surface = Color(0xFF111D24),
    surfaceVariant = Color(0xFF1A2A32),
    onSurface = Color(0xFFE8F2F2),
    onSurfaceVariant = Color(0xFFA8BCBF),
    outline = Color(0xFF53696C),
    error = Color(0xFFFFB4AB),
)

@Composable
fun DcmTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DcmColors,
        content = content,
    )
}

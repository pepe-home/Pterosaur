// 主题：默认深色，与 Web 端的令牌同一基调（首页 / 列表 / 播放条）。
package im.xrl.pterosaur.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val Ink = Color(0xFF1C1C1E)
private val Surface = Color(0xFF2C2C2E)
private val Accent = Color(0xFFFA2D48)
private val AccentSoft = Color(0x33FA2D48)

private val DarkColors = darkColorScheme(
    primary = Accent,
    onPrimary = Color.White,
    primaryContainer = AccentSoft,
    onPrimaryContainer = Color.White,
    background = Ink,
    onBackground = Color(0xFFF5F5F7),
    surface = Surface,
    onSurface = Color(0xFFF5F5F7),
    surfaceVariant = Color(0xFF3A3A3C),
    onSurfaceVariant = Color(0xFFB0B0B5),
)

private val LightColors = lightColorScheme(
    primary = Accent,
    onPrimary = Color.White,
    primaryContainer = AccentSoft,
    background = Color(0xFFFAFAFA),
    onBackground = Color(0xFF1C1C1E),
    surface = Color.White,
    onSurface = Color(0xFF1C1C1E),
    surfaceVariant = Color(0xFFF0F0F2),
    onSurfaceVariant = Color(0xFF6C6C70),
)

@Composable
fun PterosaurTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(colorScheme = if (darkTheme) DarkColors else LightColors, content = content)
}
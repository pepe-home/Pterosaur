// 应用入口：Compose 的 MainActivity（ADR-064：原生端自带内核，无 server 也能用）。
package im.xrl.pterosaur

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import im.xrl.pterosaur.ui.PterosaurApp
import im.xrl.pterosaur.ui.theme.PterosaurTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            PterosaurTheme {
                PterosaurApp()
            }
        }
    }
}
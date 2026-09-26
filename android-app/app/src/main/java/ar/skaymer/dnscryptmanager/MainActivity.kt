package ar.skaymer.dnscryptmanager

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import ar.skaymer.dnscryptmanager.ui.DcmTheme
import ar.skaymer.dnscryptmanager.ui.DnsCryptApp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            DcmTheme {
                DnsCryptApp()
            }
        }
    }
}


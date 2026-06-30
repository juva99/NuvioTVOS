package com.nuvio.app.features.updater

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier

class AppUpdaterController internal constructor() {
    fun startAutoCheck() {
    }

    fun checkForUpdates(
        force: Boolean = false,
        showNoUpdateFeedback: Boolean = false,
    ) {
        @Suppress("UNUSED_VARIABLE")
        val ignored = force to showNoUpdateFeedback
    }
}

@Composable
fun rememberAppUpdaterController(): AppUpdaterController {
    return remember { AppUpdaterController() }
}

@Composable
fun AppUpdaterHost(
    controller: AppUpdaterController,
    modifier: Modifier = Modifier,
) {
    @Suppress("UNUSED_VARIABLE")
    val ignored = controller to modifier
}

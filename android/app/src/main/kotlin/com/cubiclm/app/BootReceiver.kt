package com.cubiclm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Reboot recovery for model downloads.
 *
 * Never launches the UI from the background (blocked since Android 10 and a
 * Play-policy risk). Instead, wakes [ModelDownloadService] only when it has
 * unfinished jobs — its START_STICKY redelivery resumes interrupted
 * `.part` files via HTTP Range automatically.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON") {
            if (!hasUnfinishedJobs(context)) return
            val svc = Intent(context, ModelDownloadService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(svc)
                } else {
                    context.startService(svc)
                }
            } catch (_: Exception) {
                // Background-start denied — user opens the app and the
                // Dart side reconciles paused downloads instead.
            }
        }
    }

    private fun hasUnfinishedJobs(context: Context): Boolean {
        return try {
            // Only "Running" (killed mid-download by the reboot) — the
            // service auto-resumes those. Paused jobs wait for the user;
            // waking the FGS for them would idle a notification for nothing.
            ModelDownloadService.persistedSnapshot(context).any {
                it["status"] == "Running"
            }
        } catch (_: Exception) {
            false
        }
    }
}

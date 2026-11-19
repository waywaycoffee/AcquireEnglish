package com.acquire.english

import android.app.Application
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.work.WorkManager

class AcquireEnglishApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val preferences = getSharedPreferences("background_work_migrations", MODE_PRIVATE)
        val migration = "coalesce_subtitle_nudges_v1"
        if (preferences.getBoolean(migration, false)) return

        // Older versions enqueued one Flutter worker per nudge. Clear the
        // legacy plugin schedule as the process starts, before Dart registers
        // the daily reminder again. The subtitle queue is stored separately.
        val result = WorkManager.getInstance(this)
            .cancelAllWorkByTag("dev.fluttercommunity.workmanager.BackgroundWorker")
            .result
        result.addListener({
            try {
                result.get()
                preferences.edit().putBoolean(migration, true).apply()
            } catch (error: Exception) {
                Log.w("AcquireEnglish", "Could not migrate background reminders", error)
            }
        }, ContextCompat.getMainExecutor(this))
    }
}

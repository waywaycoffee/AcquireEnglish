package com.acquire.english

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject

/**
 * Posts an ongoing notification for the 5-minute micro-review session.
 * On HyperOS devices with 超级岛 permission, [miui.focus.param] upgrades it
 * into an island with local countdown via timerInfo.
 */
object MicroReviewIslandNotifier {
    const val CHANNEL_ID = "micro_review_island"
    const val NOTIFICATION_ID = 5205
    const val ACTION_PREFIX = "com.acquire.english.MICRO_REVIEW_"

    private var actionReceiver: BroadcastReceiver? = null
    private var actionCallback: ((String) -> Unit)? = null

    fun setActionCallback(cb: ((String) -> Unit)?) {
        actionCallback = cb
    }

    fun ensureReceiver(context: Context) {
        if (actionReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                val action = intent?.action ?: return
                val kind = when (action) {
                    ACTION_PREFIX + "KNOW" -> "know"
                    ACTION_PREFIX + "FUZZY" -> "fuzzy"
                    ACTION_PREFIX + "FORGET" -> "forget"
                    ACTION_PREFIX + "OPEN" -> "open"
                    ACTION_PREFIX + "END" -> "end"
                    else -> return
                }
                actionCallback?.invoke(kind)
            }
        }
        val filter = IntentFilter().apply {
            addAction(ACTION_PREFIX + "KNOW")
            addAction(ACTION_PREFIX + "FUZZY")
            addAction(ACTION_PREFIX + "FORGET")
            addAction(ACTION_PREFIX + "OPEN")
            addAction(ACTION_PREFIX + "END")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.applicationContext.registerReceiver(
                receiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.applicationContext.registerReceiver(receiver, filter)
        }
        actionReceiver = receiver
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = context.getSystemService(NotificationManager::class.java) ?: return
        val existing = mgr.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "碎片记忆",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "5 分钟单词碎片记忆（灵动岛 / 常驻通知）"
            setShowBadge(false)
        }
        mgr.createNotificationChannel(channel)
    }

    fun showOrUpdate(
        context: Context,
        word: String,
        gloss: String,
        remainingSec: Int,
        ratedCount: Int,
        total: Int,
        endsAtMs: Long,
    ) {
        ensureChannel(context)
        ensureReceiver(context)

        val openApp = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        openApp.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val contentPi = PendingIntent.getActivity(
            context,
            0,
            openApp,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(word.ifBlank { "碎片记忆" })
            .setContentText(
                buildString {
                    append(formatClock(remainingSec))
                    append(" · 已记 ")
                    append(ratedCount)
                    if (gloss.isNotBlank()) {
                        append(" · ")
                        append(gloss.take(40))
                    }
                },
            )
            .setSubText("acquire · 碎片")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(contentPi)
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "$word\n${gloss.ifBlank { "轻点评分或打开 App" }}\n剩余 ${formatClock(remainingSec)} · 已记 $ratedCount / $total",
                ),
            )
            .addAction(0, "认识", actionPi(context, "KNOW", 11))
            .addAction(0, "模糊", actionPi(context, "FUZZY", 12))
            .addAction(0, "忘记", actionPi(context, "FORGET", 13))
            .addAction(0, "结束", actionPi(context, "END", 14))

        val notification = builder.build()
        attachMiuiFocusParam(
            notification,
            word = word,
            gloss = gloss,
            remainingSec = remainingSec,
            ratedCount = ratedCount,
            total = total,
            endsAtMs = endsAtMs,
        )
        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }

    fun cancel(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    private fun actionPi(context: Context, suffix: String, req: Int): PendingIntent {
        val intent = Intent(ACTION_PREFIX + suffix).setPackage(context.packageName)
        return PendingIntent.getBroadcast(
            context,
            req,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun formatClock(remainingSec: Int): String {
        val sec = remainingSec.coerceAtLeast(0)
        val m = sec / 60
        val s = sec % 60
        return "%02d:%02d".format(m, s)
    }

    /**
     * HyperOS 超级岛 / 焦点通知 extras. Without OEM permission this is ignored
     * and the standard ongoing notification still works.
     */
    private fun attachMiuiFocusParam(
        notification: Notification,
        word: String,
        gloss: String,
        remainingSec: Int,
        ratedCount: Int,
        total: Int,
        endsAtMs: Long,
    ) {
        try {
            val now = System.currentTimeMillis()
            val paramIsland = JSONObject()
                .put(
                    "bigIslandArea",
                    JSONObject()
                        .put(
                            "imageTextInfoLeft",
                            JSONObject()
                                .put("titleInfo", JSONObject().put("title", word.take(28)))
                                .put(
                                    "picInfo",
                                    JSONObject().put("type", 1),
                                ),
                        )
                        .put(
                            "textInfo",
                            JSONObject().put(
                                "titleInfo",
                                JSONObject().put("title", "已记 $ratedCount"),
                            ),
                        )
                        .put(
                            "sameWidthDigitInfo",
                            JSONObject()
                                .put(
                                    "timerInfo",
                                    JSONObject()
                                        .put("timerType", -1)
                                        .put("timerWhen", endsAtMs)
                                        .put("timerSystemCurrent", now),
                                ),
                        ),
                )
                .put(
                    "smallIslandArea",
                    JSONObject()
                        .put(
                            "sameWidthDigitInfo",
                            JSONObject()
                                .put(
                                    "timerInfo",
                                    JSONObject()
                                        .put("timerType", -1)
                                        .put("timerWhen", endsAtMs)
                                        .put("timerSystemCurrent", now),
                                ),
                        ),
                )

            val paramV2 = JSONObject()
                .put("business", "micro_review_session")
                .put("updatable", true)
                .put("timeout", 12)
                .put("islandFirstFloat", true)
                .put("enableFloat", false)
                .put("param_island", paramIsland)
                .put(
                    "protocol",
                    JSONObject()
                        .put("title", "碎片记忆")
                        .put("desc", gloss.ifBlank { word })
                        .put(
                            "timerInfo",
                            JSONObject()
                                .put("timerType", -1)
                                .put("timerWhen", endsAtMs)
                                .put("timerSystemCurrent", now),
                        ),
                )

            val root = JSONObject().put("param_v2", paramV2)
            val extras: Bundle = notification.extras
            extras.putString("miui.focus.param", root.toString())
            // Keep a human-readable countdown for non-island OEMs.
            extras.putString(
                "android.substName",
                "碎片 · ${formatClock(remainingSec)} · $total",
            )
        } catch (_: Throwable) {
            // OEM extras are best-effort.
        }
    }
}

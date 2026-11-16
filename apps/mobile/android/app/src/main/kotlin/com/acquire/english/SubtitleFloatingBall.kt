package com.acquire.english

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import kotlin.math.roundToInt

/**
 * Native SYSTEM_ALERT_WINDOW floating pill for subtitle-completion progress.
 * Matches the in-app「继续播放 / 补字幕」stadium FAB so it stays visible off-app.
 */
class SubtitleFloatingBall(private val context: Context) {
    private val windowManager =
        context.applicationContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var root: LinearLayout? = null
    private var percentView: TextView? = null
    private var captionView: TextView? = null
    private var ring: ProgressBar? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var lastProgress = 0.08f

    val isShowing: Boolean
        get() = root != null

    fun canDrawOverlays(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        if (Settings.canDrawOverlays(context)) {
            return true
        }
        // Xiaomi sometimes reports Settings=false while AppOps is already allow.
        return try {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = appOps.checkOpNoThrow(
                "android:system_alert_window",
                Process.myUid(),
                context.packageName,
            )
            mode == AppOpsManager.MODE_ALLOWED
        } catch (_: Exception) {
            false
        }
    }

    fun openOverlaySettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return
        }
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    fun show(progress: Double, label: String) {
        if (!canDrawOverlays()) {
            Toast.makeText(
                context,
                "请开启「悬浮窗」权限以显示补字幕进度",
                Toast.LENGTH_LONG,
            ).show()
            openOverlaySettings()
            return
        }
        val frac = progress.toFloat().coerceIn(0f, 1f)
        lastProgress = frac
        val existing = root
        if (existing != null) {
            update(frac.toDouble(), label)
            return
        }
        val density = context.resources.displayMetrics.density
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.END
            x = (16 * density).roundToInt()
            y = (120 * density).roundToInt()
        }

        val container = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(
                (16 * density).roundToInt(),
                (12 * density).roundToInt(),
                (18 * density).roundToInt(),
                (12 * density).roundToInt(),
            )
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 999 * density
                colors = intArrayOf(Color.parseColor("#3B7CFF"), Color.parseColor("#1B4FD8"))
                orientation = GradientDrawable.Orientation.LEFT_RIGHT
            }
            elevation = 10 * density
        }

        val progressBar = ProgressBar(context).apply {
            isIndeterminate = true
            layoutParams = LinearLayout.LayoutParams(
                (22 * density).roundToInt(),
                (22 * density).roundToInt(),
            )
        }

        val percent = TextView(context).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            paint.isFakeBoldText = true
            text = "补字幕 ${(frac * 100).roundToInt()}%"
            setPadding((10 * density).roundToInt(), 0, 0, 0)
        }

        // Keep a short live caption under contentDescription for a11y / future use.
        val caption = TextView(context).apply {
            visibility = View.GONE
            text = label
        }

        container.addView(progressBar)
        container.addView(percent)
        container.addView(caption)
        attachDrag(container, params)
        container.setOnClickListener {
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                context.startActivity(launch)
            }
        }

        try {
            windowManager.addView(container, params)
            root = container
            percentView = percent
            captionView = caption
            ring = progressBar
            layoutParams = params
        } catch (error: Exception) {
            root = null
            Toast.makeText(
                context,
                "悬浮窗显示失败：${error.message ?: "请检查悬浮窗权限"}",
                Toast.LENGTH_LONG,
            ).show()
        }
    }

    fun update(progress: Double, label: String) {
        val frac = progress.toFloat().coerceIn(0f, 1f)
        lastProgress = frac
        val view = root ?: run {
            show(progress, label)
            return
        }
        percentView?.text = if (frac >= 0.99f) {
            "补字幕完成"
        } else {
            "补字幕 ${(frac * 100).roundToInt()}%"
        }
        ring?.isIndeterminate = frac < 0.99f
        captionView?.text = label
        view.contentDescription = label
    }

    fun hide() {
        val view = root ?: return
        try {
            windowManager.removeView(view)
        } catch (_: Exception) {
        }
        root = null
        percentView = null
        captionView = null
        ring = null
        layoutParams = null
    }

    private fun attachDrag(view: View, params: WindowManager.LayoutParams) {
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var moved = false
        view.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = params.x
                    startY = params.y
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downX).roundToInt()
                    val dy = (event.rawY - downY).roundToInt()
                    if (kotlin.math.abs(dx) > 4 || kotlin.math.abs(dy) > 4) {
                        moved = true
                    }
                    // BOTTOM|END: x grows leftward from the right edge; y up from bottom.
                    params.x = (startX - dx).coerceAtLeast(0)
                    params.y = (startY - dy).coerceAtLeast(0)
                    try {
                        windowManager.updateViewLayout(v, params)
                    } catch (_: Exception) {
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        v.performClick()
                    }
                    true
                }
                else -> false
            }
        }
    }
}

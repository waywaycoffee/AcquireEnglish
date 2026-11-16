package com.acquire.english

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import kotlin.math.roundToInt

/**
 * Native SYSTEM_ALERT_WINDOW floating ball for subtitle-completion progress.
 * Avoids flutter_overlay_window's second Flutter engine (broken with flavor `-t`).
 */
class SubtitleFloatingBall(private val context: Context) {
    private val windowManager =
        context.applicationContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var root: FrameLayout? = null
    private var percentView: TextView? = null
    private var captionView: TextView? = null
    private var ring: ProgressBar? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var lastProgress = 0.08f

    val isShowing: Boolean
        get() = root != null

    fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
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
                "请开启「悬浮窗」权限以显示补字幕进度球",
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
        val size = (84 * density).roundToInt()
        val params = WindowManager.LayoutParams(
            size,
            size,
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
            gravity = Gravity.TOP or Gravity.END
            x = (12 * density).roundToInt()
            y = (180 * density).roundToInt()
        }

        val container = FrameLayout(context).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                colors = intArrayOf(Color.parseColor("#3B7CFF"), Color.parseColor("#1B4FD8"))
                orientation = GradientDrawable.Orientation.TL_BR
                setStroke((2 * density).roundToInt(), Color.WHITE)
            }
            elevation = 12 * density
        }

        val progressBar = ProgressBar(
            context,
            null,
            android.R.attr.progressBarStyleHorizontal,
        ).apply {
            isIndeterminate = false
            setMax(1000)
            setProgress((frac * 1000).roundToInt().coerceIn(50, 1000))
            layoutParams = FrameLayout.LayoutParams(
                (58 * density).roundToInt(),
                (58 * density).roundToInt(),
                Gravity.CENTER,
            )
            // Text is the primary signal; bar is a light cue.
            alpha = 0.35f
        }

        val percent = TextView(context).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            paint.isFakeBoldText = true
            gravity = Gravity.CENTER
            text = "${(frac * 100).roundToInt()}%"
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ).apply { bottomMargin = (8 * density).roundToInt() }
        }

        val caption = TextView(context).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 9f)
            paint.isFakeBoldText = true
            gravity = Gravity.CENTER
            text = "字幕"
            alpha = 0.92f
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ).apply { topMargin = (14 * density).roundToInt() }
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
                "悬浮球显示失败：${error.message ?: "请检查悬浮窗权限"}",
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
        percentView?.text = "${(frac * 100).roundToInt()}%"
        ring?.setProgress((frac * 1000).roundToInt().coerceIn(50, 1000))
        captionView?.text = if (frac >= 0.99f) "完成" else "字幕"
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
                    // TOP|END: x grows leftward from the right edge.
                    params.x = (startX - dx).coerceAtLeast(0)
                    params.y = (startY + dy).coerceAtLeast(0)
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

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
 * Process-wide singleton SYSTEM_ALERT_WINDOW pill.
 * Must be a singleton: Activity recreate otherwise leaves orphan WindowManager
 * views → multiple floating balls on screen.
 *
 * User can tap × to hide. Dismissal is persisted so the ball stays hidden while
 * the user does other things; re-enable via [setUserDismissed]/false) from App.
 */
class SubtitleFloatingBall private constructor(private val context: Context) {
    private val windowManager =
        context.applicationContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val prefs =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private var root: LinearLayout? = null
    private var percentView: TextView? = null
    private var captionView: TextView? = null
    private var closeView: TextView? = null
    private var ring: ProgressBar? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var lastProgress = 0.08f

    @Volatile
    private var userDismissed: Boolean = prefs.getBoolean(KEY_DISMISSED, false)

    val isShowing: Boolean
        get() = root != null

    val isUserDismissed: Boolean
        get() = userDismissed

    fun setUserDismissed(dismissed: Boolean) {
        userDismissed = dismissed
        prefs.edit().putBoolean(KEY_DISMISSED, dismissed).apply()
        if (dismissed) {
            hide()
        }
    }

    /** Clear a previous × dismissal so the next background session can show. */
    fun resetDismissal() {
        setUserDismissed(false)
    }

    /** The × button: hide the pill; FGS keeps filling subtitles. */
    private fun dismissByUser() {
        setUserDismissed(true)
        Toast.makeText(
            context,
            "已隐藏悬浮球，下载仍在后台进行",
            Toast.LENGTH_SHORT,
        ).show()
    }

    fun canDrawOverlays(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        if (Settings.canDrawOverlays(context)) {
            return true
        }
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
        if (userDismissed) {
            return
        }
        // Never mount a system overlay while MainActivity is resumed —
        // the in-app FAB already shows progress (avoids 2–3 balls).
        if (MainActivity.isActivityResumed) {
            hide()
            return
        }
        if (!canDrawOverlays()) {
            Toast.makeText(
                context,
                "请开启「悬浮窗」权限以显示下载进度",
                Toast.LENGTH_LONG,
            ).show()
            openOverlaySettings()
            return
        }
        val frac = progress.toFloat().coerceIn(0f, 1f)
        lastProgress = frac
        if (root != null) {
            update(frac.toDouble(), label)
            return
        }
        hide()

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
            tag = VIEW_TAG
            setPadding(
                (16 * density).roundToInt(),
                (12 * density).roundToInt(),
                (10 * density).roundToInt(),
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
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            paint.isFakeBoldText = true
            text = displayLabel(label, frac)
            setPadding((10 * density).roundToInt(), 0, 0, 0)
        }

        val caption = TextView(context).apply {
            visibility = View.GONE
            text = label
        }

        val divider = View(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                (1 * density).roundToInt(),
                (16 * density).roundToInt(),
            ).apply {
                gravity = Gravity.CENTER_VERTICAL
                setMargins((10 * density).roundToInt(), 0, 0, 0)
            }
            setBackgroundColor(Color.parseColor("#66FFFFFF"))
        }

        val close = TextView(context).apply {
            text = "×"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            gravity = Gravity.CENTER
            isClickable = true
            isFocusable = true
            contentDescription = "关闭悬浮球"
            // Large tap target so × is easy to hit while dragging the pill.
            setPadding(
                (14 * density).roundToInt(),
                (10 * density).roundToInt(),
                (12 * density).roundToInt(),
                (10 * density).roundToInt(),
            )
            // Consume touch here so the container drag listener never steals ×.
            setOnTouchListener { _, event ->
                if (event.action == MotionEvent.ACTION_UP) {
                    dismissByUser()
                }
                true
            }
        }

        container.addView(progressBar)
        container.addView(percent)
        container.addView(caption)
        container.addView(divider)
        container.addView(close)
        attachDrag(container, params, close)
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
            closeView = close
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
        if (userDismissed) {
            return
        }
        if (MainActivity.isActivityResumed) {
            hide()
            return
        }
        val frac = progress.toFloat().coerceIn(0f, 1f)
        lastProgress = frac
        val view = root ?: run {
            show(progress, label)
            return
        }
        percentView?.text = displayLabel(label, frac)
        ring?.isIndeterminate = frac < 0.99f
        captionView?.text = label
        view.contentDescription = label
    }

    fun hide() {
        val view = root
        root = null
        percentView = null
        captionView = null
        closeView = null
        ring = null
        layoutParams = null
        if (view != null) {
            try {
                windowManager.removeView(view)
            } catch (_: Exception) {
                try {
                    windowManager.removeViewImmediate(view)
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun displayLabel(label: String, frac: Float): String {
        val trimmed = label.trim()
        if (trimmed.isNotEmpty()) {
            return trimmed
        }
        return if (frac >= 0.99f) {
            "下载完成"
        } else {
            "下载 ${(frac * 100).roundToInt()}%"
        }
    }

    private fun attachDrag(
        view: View,
        params: WindowManager.LayoutParams,
        close: View,
    ) {
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var moved = false
        view.setOnTouchListener { v, event ->
            // Never start a drag from the close control.
            if (event.action == MotionEvent.ACTION_DOWN && isInView(close, event.rawX, event.rawY)) {
                return@setOnTouchListener false
            }
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

    private fun isInView(target: View, rawX: Float, rawY: Float): Boolean {
        val loc = IntArray(2)
        target.getLocationOnScreen(loc)
        val left = loc[0]
        val top = loc[1]
        val right = left + target.width
        val bottom = top + target.height
        return rawX >= left && rawX <= right && rawY >= top && rawY <= bottom
    }

    companion object {
        private const val VIEW_TAG = "acquire_subtitle_floating_ball"
        private const val PREFS = "acquire_subtitle_overlay"
        private const val KEY_DISMISSED = "user_dismissed"

        @Volatile
        private var instance: SubtitleFloatingBall? = null

        fun get(context: Context): SubtitleFloatingBall {
            val existing = instance
            if (existing != null) {
                return existing
            }
            return synchronized(this) {
                instance ?: SubtitleFloatingBall(context.applicationContext).also {
                    instance = it
                }
            }
        }
    }
}

package com.letou.letou_app

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var splashCover: View? = null

    /// Surface 会推迟第一帧，Android 12+ 就会一直停在纯色启动层。
    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        VpnCheck.start(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flyroom/security")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isVpnActive" -> result.success(VpnCheck.isActive(applicationContext))
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "flyroom/security/vpn")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    VpnCheck.onChanged = { active ->
                        runOnUiThread {
                            try {
                                sink.success(active)
                            } catch (_: Exception) {
                            }
                        }
                    }
                    sink.success(VpnCheck.isActive(applicationContext))
                }

                override fun onCancel(arguments: Any?) {
                    VpnCheck.onChanged = null
                }
            })
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { it.remove() }
        }
        super.onCreate(savedInstanceState)
        showSplashCover()
        wakeDisplay()
    }

    override fun onResume() {
        super.onResume()
        wakeDisplay()
    }

    override fun onFlutterUiDisplayed() {
        removeSplashCover()
        super.onFlutterUiDisplayed()
    }

    override fun onDestroy() {
        removeSplashCover()
        super.onDestroy()
    }

    private fun showSplashCover() {
        if (splashCover != null) return
        val content = findViewById<ViewGroup>(android.R.id.content) ?: return
        val root = FrameLayout(this)
        root.isClickable = true

        val image = ImageView(this)
        image.setImageResource(R.drawable.splash)
        image.scaleType = ImageView.ScaleType.CENTER_CROP
        root.addView(
            image,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )

        val bar = SplashProgressBar(this)
        val barWidth = (resources.displayMetrics.widthPixels * 0.48f).toInt()
        val barHeight = dp(6)
        val barParams = FrameLayout.LayoutParams(barWidth, barHeight, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL)
        barParams.bottomMargin = dp(48)
        root.addView(bar, barParams)

        content.addView(
            root,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        splashCover = root
    }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics,
        ).toInt()

    private fun removeSplashCover() {
        val cover = splashCover ?: return
        splashCover = null
        (cover.parent as? ViewGroup)?.removeView(cover)
    }

    private fun wakeDisplay() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setTurnScreenOn(true)
            setShowWhenLocked(true)
        }
    }
}

/** 圆角加载条：从中间向两边填满，再重来。 */
private class SplashProgressBar(context: Context) : View(context) {
    private val track = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x59FFFFFF }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    private var fraction = 0.15f

    private val animator = ValueAnimator.ofFloat(0.12f, 1f).apply {
        duration = 1200L
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener {
            fraction = it.animatedValue as Float
            invalidate()
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        animator.start()
    }

    override fun onDetachedFromWindow() {
        animator.cancel()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        val radius = h / 2f
        canvas.drawRoundRect(0f, 0f, w, h, radius, radius, track)
        val half = w / 2f * fraction
        val center = w / 2f
        canvas.drawRoundRect(center - half, 0f, center + half, h, radius, radius, fill)
    }
}

package com.kemenag.examgo

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.examgo/locktask"
    private var isLockTaskActive = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Prevent screenshots (Android)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )

        // Keep screen on during exam
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Disable pull-down notification shade
        window.setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN
        )

        // ── FIX: Render process crash — Android 8+ (API 26+) ──────────
        // webview_flutter_android tidak expose onRenderProcessGone ke Dart.
        // Tanpa ini: FATAL crashpad → app force close di Android 16 Beta (SDK 36).
        // Inject WebViewClient custom SETELAH Flutter inflate view-nya.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            window.decorView.post { injectRenderProcessGoneHandler() }
        }
    }

    /**
     * Rekursif inject custom WebViewClient ke semua WebView
     * yang sudah di-inflate oleh Flutter. Juga dipanggil ulang
     * saat onResume karena WebView bisa recreate setelah crash.
     *
     * PENTING: Kita WRAP existing webViewClient, bukan replace-nya,
     * agar callback Flutter (onPageFinished, onWebResourceError, dll)
     * tetap berfungsi. Replace langsung adalah bug yang menyebabkan
     * exam_load_error tidak ter-handle atau ter-trigger berulang.
     */
    private fun injectRenderProcessGoneHandler() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            findWebViews(window.decorView).forEach { webView ->
                val existing = webView.webViewClient
                // Jangan wrap ulang kalau sudah di-wrap
                if (existing is RenderProcessSafeClient) return@forEach
                webView.webViewClient = RenderProcessSafeClient(existing)
            }
        } catch (e: Exception) {
            println("⚠️ injectRenderProcessGoneHandler error: ${e.message}")
        }
    }

    /**
     * Wrapper WebViewClient yang hanya override onRenderProcessGone,
     * dan mendelegasikan semua metode lain ke delegate asli.
     * Ini mencegah Flutter kehilangan callback-nya.
     */
    private inner class RenderProcessSafeClient(
        private val delegate: WebViewClient
    ) : WebViewClient() {

        override fun onRenderProcessGone(
            view: WebView?,
            detail: RenderProcessGoneDetail?
        ): Boolean {
            println("⚠️ Render process gone — didCrash=${detail?.didCrash()}")
            return true // handle sendiri, app tidak crash
        }

        // Delegasi semua method lain ke original Flutter client
        override fun shouldOverrideUrlLoading(view: WebView?, request: android.webkit.WebResourceRequest?) =
            delegate.shouldOverrideUrlLoading(view, request)

        override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) =
            delegate.onPageStarted(view, url, favicon)

        override fun onPageFinished(view: WebView?, url: String?) =
            delegate.onPageFinished(view, url)

        override fun onReceivedError(view: WebView?, request: android.webkit.WebResourceRequest?, error: android.webkit.WebResourceError?) =
            delegate.onReceivedError(view, request, error)

        override fun onReceivedHttpError(view: WebView?, request: android.webkit.WebResourceRequest?, errorResponse: android.webkit.WebResourceResponse?) =
            delegate.onReceivedHttpError(view, request, errorResponse)

        override fun onReceivedSslError(view: WebView?, handler: android.webkit.SslErrorHandler?, error: android.net.http.SslError?) =
            delegate.onReceivedSslError(view, handler, error)

        override fun doUpdateVisitedHistory(view: WebView?, url: String?, isReload: Boolean) =
            delegate.doUpdateVisitedHistory(view, url, isReload)
    }

    private fun findWebViews(view: android.view.View): List<WebView> {
        if (view is WebView) return listOf(view)
        if (view !is ViewGroup) return emptyList()
        return (0 until view.childCount).flatMap { findWebViews(view.getChildAt(it)) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startLockTask" -> startLockTask(result)
                "stopLockTask" -> stopLockTask(result)
                "bringToForeground" -> bringToForeground(result)
                "isLockTaskActive" -> result.success(isLockTaskActive)
                else -> result.notImplemented()
            }
        }
    }

    private fun startLockTask(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val lockTaskMode = activityManager.lockTaskModeState
                    if (lockTaskMode == ActivityManager.LOCK_TASK_MODE_LOCKED ||
                        lockTaskMode == ActivityManager.LOCK_TASK_MODE_PINNED) {
                        result.success(true)
                        return
                    }
                }

                startLockTask()
                isLockTaskActive = true
                println("✅ Lock Task Mode Started (App Pinning)")
                result.success(true)
            } else {
                println("⚠️ Lock Task Mode not supported on this Android version")
                result.success(false)
            }
        } catch (e: Exception) {
            println("❌ Error starting lock task: ${e.message}")
            result.success(false)
        }
    }

    private fun stopLockTask(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && isLockTaskActive) {
                stopLockTask()
                isLockTaskActive = false
                println("✅ Lock Task Mode Stopped")
                result.success(true)
            } else {
                result.success(false)
            }
        } catch (e: Exception) {
            println("❌ Error stopping lock task: ${e.message}")
            result.success(false)
        }
    }

    private fun bringToForeground(result: MethodChannel.Result) {
        try {
            val intent = Intent(this, MainActivity::class.java)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            startActivity(intent)
            println("✅ Brought app to foreground")
            result.success(true)
        } catch (e: Exception) {
            println("❌ Error bringing to foreground: ${e.message}")
            result.success(false)
        }
    }

    override fun onBackPressed() {
        if (isLockTaskActive) {
            println("🚫 Back button blocked (Lock Task Active)")
            return
        }
        super.onBackPressed()
    }

    override fun onPause() {
        super.onPause()
        if (isLockTaskActive) println("⚠️ App paused while Lock Task active")
    }

    override fun onResume() {
        super.onResume()
        if (isLockTaskActive) {
            println("✅ App resumed in Lock Task mode")
            // Re-inject: WebView bisa recreate setelah render crash
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                window.decorView.post { injectRenderProcessGoneHandler() }
            }
        }
    }

    override fun onDestroy() {
        if (isLockTaskActive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try { stopLockTask() } catch (e: Exception) {
                println("Error cleaning up lock task: ${e.message}")
            }
        }
        super.onDestroy()
    }
}
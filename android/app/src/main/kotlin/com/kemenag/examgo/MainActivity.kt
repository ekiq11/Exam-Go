package com.kemenag.examgo

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Bundle
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    override fun getRenderMode(): RenderMode {
        return RenderMode.texture
    }

    private val CHANNEL = "com.examgo/locktask"
    private var isLockTaskActive = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyWindowFlags()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            window.decorView.post { injectRenderProcessGoneHandler() }
        }
    }

    // ════════════════════════════════════════════════════════════════
    // FIX #1 — gralloc4 MALI BAD ALLOC + GPUAUX Null anb
    // Paksa RGBA_8888 sebelum FLAG_SECURE diset, agar gralloc tidak
    // mencoba format 10-bit (0x38/0x3b) yang tidak didukung chipset ini.
    // ════════════════════════════════════════════════════════════════
    private fun applyWindowFlags() {
        window.setFormat(PixelFormat.RGBA_8888)
        window.addFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // FIX BUG-02: FLAG_FULLSCREEN deprecated sejak API 30 (Android 11).
        // Beberapa OEM ROM (Xiaomi MIUI 14, Samsung One UI 6+) melempar
        // WindowManager$BadTokenException saat FLAG_FULLSCREEN diset setelah
        // window sudah attach. Gunakan WindowInsetsController untuk API 30+.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.apply {
                hide(android.view.WindowInsets.Type.statusBars())
                hide(android.view.WindowInsets.Type.navigationBars())
                systemBarsBehavior =
                    android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        }

        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION)
    }

    // ════════════════════════════════════════════════════════════════
    // FIX #5 — Back button di Android 13+ (API 33+)
    //
    // Catatan: onBackPressed() memang @Deprecated sejak API 33, TAPI:
    //  - Bukan compile error — hanya warning
    //  - Tetap berfungsi PENUH selama manifest TIDAK ada:
    //    android:enableOnBackInvokedCallback="true"
    //  - App ini tidak mengaktifkan flag tersebut → safe digunakan
    //
    // Menggunakan OnBackPressedDispatcher (cara baru) butuh dependency
    // androidx.activity yang TIDAK ada di build.gradle.kts dan berisiko
    // conflict dengan Flutter embedding. Suppress + override ini adalah
    // solusi paling stabil tanpa mengubah dependency.
    // ════════════════════════════════════════════════════════════════
    @Suppress("DEPRECATION", "MissingSuperCall")
    override fun onBackPressed() {
        if (isLockTaskActive) return  // blokir back saat ujian
        super.onBackPressed()         // Flutter handle normal navigation
    }

    // ════════════════════════════════════════════════════════════════
    // RenderProcessGone Handler — cegah crash saat WebView renderer mati
    // Wajib di Android 8+ (API 26+), terutama Galaxy Tab A11+ 5G / Android 16
    // ════════════════════════════════════════════════════════════════
    private fun injectRenderProcessGoneHandler() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            findWebViews(window.decorView).forEach { webView ->
                val existing = webView.webViewClient
                if (existing is RenderProcessSafeClient) return@forEach
                webView.webViewClient = RenderProcessSafeClient(existing)
            }
        } catch (e: Exception) {
            println("⚠️ injectRenderProcessGoneHandler error: ${e.message}")
        }
    }

    private inner class RenderProcessSafeClient(
        private val delegate: WebViewClient
    ) : WebViewClient() {

        override fun onRenderProcessGone(
            view: WebView?,
            detail: RenderProcessGoneDetail?
        ): Boolean {
            println("⚠️ Render process gone — didCrash=${detail?.didCrash()}")
            // Return true = kita handle sendiri, app tidak ikut crash
            return true
        }

        override fun shouldOverrideUrlLoading(
            view: WebView?,
            request: android.webkit.WebResourceRequest?
        ) = delegate.shouldOverrideUrlLoading(view, request)

        override fun onPageStarted(
            view: WebView?,
            url: String?,
            favicon: android.graphics.Bitmap?
        ) = delegate.onPageStarted(view, url, favicon)

        override fun onPageFinished(view: WebView?, url: String?) =
            delegate.onPageFinished(view, url)

        override fun onReceivedError(
            view: WebView?,
            request: android.webkit.WebResourceRequest?,
            error: android.webkit.WebResourceError?
        ) = delegate.onReceivedError(view, request, error)

        override fun onReceivedHttpError(
            view: WebView?,
            request: android.webkit.WebResourceRequest?,
            errorResponse: android.webkit.WebResourceResponse?
        ) = delegate.onReceivedHttpError(view, request, errorResponse)

        override fun onReceivedSslError(
            view: WebView?,
            handler: android.webkit.SslErrorHandler?,
            error: android.net.http.SslError?
        ) = delegate.onReceivedSslError(view, handler, error)

        override fun doUpdateVisitedHistory(
            view: WebView?,
            url: String?,
            isReload: Boolean
        ) = delegate.doUpdateVisitedHistory(view, url, isReload)
    }

    private fun findWebViews(view: android.view.View): List<WebView> {
        if (view is WebView) return listOf(view)
        if (view !is ViewGroup) return emptyList()
        return (0 until view.childCount).flatMap { findWebViews(view.getChildAt(it)) }
    }

    // ════════════════════════════════════════════════════════════════
    // Flutter Engine — Method Channel
    // ════════════════════════════════════════════════════════════════
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // [FIX T-2] Instantiate KioskMethodChannel agar channel com.examgo/kiosk
        // terdaftar dan aktif. Sebelumnya class ini tidak pernah diinisialisasi
        // sehingga semua call ke enableKioskMode, checkBlockedApps, dll.
        // selalu return FlutterMethodNotImplemented.
        KioskMethodChannel(this, flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startLockTask"     -> startLockTask(result)
                "stopLockTask"      -> stopLockTask(result)
                "bringToForeground" -> bringToForeground(result)
                "isLockTaskActive"  -> result.success(isLockTaskActive)
                "isScreenOn"        -> isScreenOn(result)
                else                -> result.notImplemented()
            }
        }
    }

    // ════════════════════════════════════════════════════════════════
    // Lock Task
    // ════════════════════════════════════════════════════════════════
    private fun startLockTask(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val mode = am.lockTaskModeState
                    if (mode == ActivityManager.LOCK_TASK_MODE_LOCKED ||
                        mode == ActivityManager.LOCK_TASK_MODE_PINNED) {
                        result.success(true)
                        return
                    }
                }
                startLockTask()
                isLockTaskActive = true
                result.success(true)
            } else {
                result.success(false)
            }
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun stopLockTask(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && isLockTaskActive) {
                stopLockTask()
                isLockTaskActive = false
                result.success(true)
            } else {
                result.success(false)
            }
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun bringToForeground(result: MethodChannel.Result) {
        try {
            startActivity(Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            })
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun isScreenOn(result: MethodChannel.Result) {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
            result.success(pm.isInteractive)
        } catch (e: Exception) {
            result.success(true)
        }
    }

    // ════════════════════════════════════════════════════════════════
    // Lifecycle
    // ════════════════════════════════════════════════════════════════
    override fun onResume() {
        super.onResume()
        if (isLockTaskActive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            window.decorView.post { injectRenderProcessGoneHandler() }
        }
    }

    override fun onDestroy() {
        if (isLockTaskActive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try { stopLockTask() } catch (_: Exception) {}
        }
        super.onDestroy()
    }
}
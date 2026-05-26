package com.kemenag.examgo

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
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
import android.util.Log

class MainActivity : FlutterFragmentActivity() {

    override fun getRenderMode(): RenderMode {
        return RenderMode.texture
    }

    private val CHANNEL = "com.examgo/locktask"
    private var isLockTaskActive = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyWindowFlags()
        createNotificationChannels() // FIX FCM-3: Buat channel sebelum notifikasi pertama
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            window.decorView.post { injectRenderProcessGoneHandler() }
        }
    }

    // FIX FCM-3: Android 8+ (API 26+) wajib punya NotificationChannel sebelum
    // menampilkan notifikasi. FCM dari GAS menggunakan channelId 'exam_violations'.
    // Tanpa channel ini, sound/vibration settings diabaikan sistem.
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "exam_violations",
                "Pelanggaran Ujian",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifikasi saat siswa melanggar aturan ujian"
                enableVibration(true)
                enableLights(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500)
            }
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
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

        // Untuk API < 30: FLAG_FULLSCREEN masih aman dan cukup
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        }
        // Catatan: WindowInsetsController (API 30+) dipanggil di
        // onWindowFocusChanged() agar insetsController tidak null.

        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION)
    }

    // ════════════════════════════════════════════════════════════════
    // ANTI SPLIT SCREEN — Lapisan 1: onMultiWindowModeChanged()
    //
    // resizeableActivity="false" di manifest TIDAK cukup di Android 7.x
    // (API 24-25). User masih bisa masuk split screen via gesture.
    // Fix: override callback ini dan langsung finishAndRemoveTask() +
    // restart Activity dalam mode fullscreen.
    //
    // Lapisan 2: Jika sedang dalam Lock Task mode (ujian aktif),
    // finishAndRemoveTask akan gagal — fallback ke moveTaskToBack()
    // agar app tetap di foreground.
    // ════════════════════════════════════════════════════════════════
    @Suppress("DEPRECATION")
    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean) {
        super.onMultiWindowModeChanged(isInMultiWindowMode)
        if (isInMultiWindowMode) {
            Log.w("ExamGO", "⚠️ Split screen detected! Forcing fullscreen...")
            if (isLockTaskActive) {
                // Saat ujian aktif: jangan destroy activity, cukup paksa fullscreen kembali
                // dengan membawa task ke foreground. Lock Task mode akan mengambil alih.
                moveTaskToBack(false)
                startActivity(Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                })
            } else {
                // Di luar ujian: keluar dari split screen dengan restart activity
                // Restart tanpa animasi agar perpindahan tidak terlihat oleh user
                val intent = Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                startActivity(intent)
                overridePendingTransition(0, 0) // tanpa animasi
                finish()
            }
        }
    }

    // ANTI SPLIT SCREEN — Lapisan 2: override isInMultiWindowMode()
    // Mengembalikan false selalu agar Flutter engine dan plugin tidak
    // melakukan adaptasi layout untuk mode multi-window.
    override fun isInMultiWindowMode(): Boolean = false

    // ANTI SPLIT SCREEN — Lapisan 3: override onPictureInPictureModeChanged()
    // Blokir Picture-in-Picture mode juga (celah serupa split screen).
    @Suppress("DEPRECATION")
    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode)
        if (isInPictureInPictureMode) {
            Log.w("ExamGO", "⚠️ PiP mode detected! Forcing exit...")
            // Keluar dari PiP mode dengan memindahkan task kembali ke foreground
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            startActivity(intent)
        }
    }

    // FIX INFINIX/TRANSSION: insetsController adalah null di onCreate() pada
    // beberapa device Infinix X6855 (MediaTek Helio G88) karena window belum
    // sepenuhnya attached ke WindowManager saat onCreate dipanggil.
    // onWindowFocusChanged(true) dipanggil saat window sudah visible dan
    // insetsController sudah terjamin non-null.
    // Ini juga mengurangi startup jank (366 frames skipped) karena tidak ada
    // layout pass tambahan sebelum first frame.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.apply {
                hide(android.view.WindowInsets.Type.statusBars())
                hide(android.view.WindowInsets.Type.navigationBars())
                systemBarsBehavior =
                    android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        }
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
                "startLockTask"         -> startLockTask(result)
                "stopLockTask"          -> stopLockTask(result)
                "bringToForeground"     -> bringToForeground(result)
                "isLockTaskActive"      -> result.success(isLockTaskActive)
                "isScreenOn"            -> isScreenOn(result)
                // FIX CAMERA-CRASH: Pre-flight check sebelum CameraX diinisialisasi.
                // Device Advan (dan beberapa brand lokal) melaporkan 0 kamera tersedia
                // saat Camera HAL bermasalah, menyebabkan CameraUnavailableException
                // yang crash di level Java (RuntimeException tidak tertangkap Flutter).
                // Solusi: cek FEATURE_CAMERA_ANY lewat PackageManager sebelum
                // MobileScannerController.start() pernah dipanggil di Dart.
                "checkCameraAvailable"  -> checkCameraAvailable(result)
                else                    -> result.notImplemented()
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

    // FIX CAMERA-CRASH: Cek ketersediaan kamera sebelum CameraX diinisialisasi.
    // Menggunakan FEATURE_CAMERA_ANY (bukan FEATURE_CAMERA) karena lebih reliable:
    // FEATURE_CAMERA_ANY mendeteksi kamera manapun (depan/belakang/eksternal).
    // Beberapa device lokal (Advan, dll) gagal melaporkan FEATURE_CAMERA padahal
    // punya kamera depan, atau Camera HAL sementara tidak responsif.
    // Return value: Map dengan 'available' (bool) dan 'reason' (String).
    private fun checkCameraAvailable(result: MethodChannel.Result) {
        try {
            val pm = packageManager
            val hasAnyCam = pm.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
            val hasBackCam = pm.hasSystemFeature(PackageManager.FEATURE_CAMERA)

            // Cek tambahan: coba enum kamera via CameraManager (API 21+)
            // Lebih akurat dari PackageManager karena cek HAL langsung.
            var cameraCount = 0
            try {
                val camManager = getSystemService(Context.CAMERA_SERVICE) as android.hardware.camera2.CameraManager
                cameraCount = camManager.cameraIdList.size
            } catch (_: Exception) {}

            val available = hasAnyCam || hasBackCam || cameraCount > 0
            result.success(mapOf(
                "available" to available,
                "hasAnyCam" to hasAnyCam,
                "hasBackCam" to hasBackCam,
                "cameraCount" to cameraCount,
                "reason" to if (!available)
                    "Device melaporkan 0 kamera tersedia (HAL issue atau kamera sedang dipakai app lain)"
                else "OK"
            ))
        } catch (e: Exception) {
            // Jika pengecekan sendiri error, asumsikan kamera ada agar tidak
            // memblokir pengguna yang sebenarnya punya kamera berfungsi.
            result.success(mapOf(
                "available" to true,
                "reason" to "check_failed: ${e.message}"
            ))
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
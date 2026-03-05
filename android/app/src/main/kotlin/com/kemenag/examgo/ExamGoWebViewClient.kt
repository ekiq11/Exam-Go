package com.kemenag.examgo

import android.webkit.RenderProcessGoneDetail
import android.webkit.WebView
import android.webkit.WebViewClient
import android.util.Log

/**
 * Custom WebViewClient yang handle onRenderProcessGone.
 *
 * Wajib di Android 8+ (API 26+) — tanpa ini, render process crash
 * = FATAL crashpad error = app force close.
 *
 * Khususnya diperlukan di:
 *   - Android 16 Beta (SDK 36) — Galaxy Tab A11+ 5G
 *   - Chromium terbaru dengan strict process isolation
 *
 * Cara pakai: lihat MainActivity.kt
 */
class ExamGoWebViewClient : WebViewClient() {

    companion object {
        private const val TAG = "ExamGoWebViewClient"
    }

    /**
     * Dipanggil saat render process crash atau di-kill oleh sistem.
     * Return TRUE = kita handle sendiri, app tidak crash.
     * Return FALSE = sistem terminate app (default perilaku lama).
     */
    override fun onRenderProcessGone(
        view: WebView?,
        detail: RenderProcessGoneDetail?
    ): Boolean {
        val didCrash = detail?.didCrash() ?: true
        Log.w(TAG, "Render process gone — didCrash=$didCrash")

        if (view == null) return true

        return try {
            // WebView yang crash tidak bisa dipakai lagi —
            // flutter webview_flutter akan reload via onWebResourceError
            // yang sudah dihandle di sisi Dart.
            // Kita cukup return true agar app tidak ikut crash.
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error handling render process gone: ${e.message}")
            true // tetap return true, jangan crash app
        }
    }
}
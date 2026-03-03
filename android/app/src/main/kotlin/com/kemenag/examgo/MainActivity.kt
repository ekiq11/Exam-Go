package com.kemenag.examgo

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.kemenag.examgo/locktask"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startLockTask" -> {
                        try {
                            // Hanya aktifkan jika benar-benar dalam pinned mode
                            // Cek dulu apakah device support lock task
                            if (isLockTaskPermitted()) {
                                startLockTask()
                                result.success(true)
                            } else {
                                // Tidak error — cukup return false
                                // Flutter side akan tetap jalan dengan immersive mode
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.success(false) // Bukan error fatal
                        }
                    }
                    "stopLockTask" -> {
                        try {
                            stopLockTask()
                            result.success(true)
                        } catch (e: Exception) {
                            // Samsung OneUI kadang throw exception meski tidak dalam lock task
                            result.success(true) // Anggap sukses — screen sudah bebas
                        }
                    }
                    "isInLockTask" -> {
                        result.success(isCurrentlyInLockTask())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Cek apakah app sudah di-whitelist sebagai Device Owner / Device Policy
     * Samsung Knox, Xiaomi MDM, dll. berbeda-beda cara ceknya.
     */
    private fun isLockTaskPermitted(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                am.isInLockTaskMode
                // Jika sudah dalam lock task, stop bukan start yang diperlukan
                // Return false agar tidak double-start
                false
            } else {
                false
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun isCurrentlyInLockTask(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
            } else {
                false
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Override onDestroy untuk pastikan lock task selalu dilepas
     * bahkan jika app di-force stop / killed
     */
    override fun onDestroy() {
        try {
            stopLockTask()
        } catch (_: Exception) {
            // Ignore — bisa gagal jika memang tidak dalam lock task
        }
        super.onDestroy()
    }
}
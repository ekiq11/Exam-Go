package com.kemenag.examgo

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
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

    /**
     * Start Lock Task Mode (App Pinning)
     * Ini akan mencegah user keluar dari aplikasi
     */
    private fun startLockTask(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                // Check if already in lock task mode
                val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val lockTaskMode = activityManager.lockTaskModeState
                    if (lockTaskMode == ActivityManager.LOCK_TASK_MODE_LOCKED ||
                        lockTaskMode == ActivityManager.LOCK_TASK_MODE_PINNED) {
                        result.success(true)
                        return
                    }
                }
                
                // Start lock task mode (App Pinning)
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

    /**
     * Stop Lock Task Mode
     */
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

    /**
     * Force bring app to foreground
     */
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
        // Block back button when lock task is active
        if (isLockTaskActive) {
            println("🚫 Back button blocked (Lock Task Active)")
            // Do nothing - prevent back navigation
            return
        }
        super.onBackPressed()
    }

    override fun onPause() {
        super.onPause()
        if (isLockTaskActive) {
            println("⚠️ App paused while Lock Task active")
        }
    }

    override fun onResume() {
        super.onResume()
        if (isLockTaskActive) {
            println("✅ App resumed in Lock Task mode")
        }
    }

    override fun onDestroy() {
        // Clean up lock task if still active
        if (isLockTaskActive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                stopLockTask()
            } catch (e: Exception) {
                println("Error cleaning up lock task: ${e.message}")
            }
        }
        super.onDestroy()
    }
}
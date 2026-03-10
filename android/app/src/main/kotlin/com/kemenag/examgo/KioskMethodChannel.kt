package com.kemenag.examgo

import android.app.Activity
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.usage.UsageStatsManager
import android.app.AppOpsManager

// FIX: Import baru untuk mengganti startActivityForResult yang deprecated
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts

class KioskMethodChannel(
    private val activity: Activity,
    flutterEngine: FlutterEngine
) {
    private val CHANNEL = "com.examgo/kiosk"
    private var devicePolicyManager: DevicePolicyManager? = null
    private var adminComponent: ComponentName? = null
    private var isKioskActive = false

    // Blocked apps list
    private val blockedApps = setOf(
        "com.whatsapp",
        "com.facebook.katana",
        "com.instagram.android",
        "com.twitter.android",
        "com.google.android.apps.messaging",
        "com.google.android.gm",
        "com.android.chrome",
        "com.android.vending",
        "com.google.android.apps.docs",
        "com.snapchat.android",
        "com.zhiliaoapp.musically", // TikTok
        "com.google.android.youtube",
        "com.telegram.messenger",
        "com.discord",
        "com.slack",
        "org.telegram.messenger"
    )

    init {
        devicePolicyManager = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

        adminComponent = ComponentName(
            activity.applicationContext,
            ExamDeviceAdminReceiver::class.java
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDeviceAdminEnabled" -> {
                    result.success(isDeviceAdmin())
                }
                "requestDeviceAdmin" -> {
                    requestDeviceAdmin()
                    result.success(null)
                }
                "enableKioskMode" -> {
                    val success = enableKioskMode()
                    result.success(success)
                }
                "disableKioskMode" -> {
                    val success = disableKioskMode()
                    result.success(success)
                }
                "checkBlockedApps" -> {
                    result.success(checkBlockedApps())
                }
                "getRunningApps" -> {
                    result.success(getRunningApps())
                }
                "checkUsageStatsPermission" -> {
                    result.success(hasUsageStatsPermission())
                }
                "openUsageStatsSettings" -> {
                    openUsageStatsSettings()
                    result.success(null)
                }
                "startLockTask" -> {
                    result.success(startLockTaskMode())
                }
                "stopLockTask" -> {
                    stopLockTaskMode()
                    result.success(null)
                }
                "hideSystemUI" -> {
                    hideSystemUI()
                    result.success(null)
                }
                "showSystemUI" -> {
                    showSystemUI()
                    result.success(null)
                }
                "blockRecentApps" -> {
                    blockRecentApps()
                    result.success(null)
                }
                "isKioskModeActive" -> {
                    result.success(isKioskActive)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isDeviceAdmin(): Boolean {
        return try {
            devicePolicyManager?.isAdminActive(adminComponent!!) ?: false
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun requestDeviceAdmin() {
        try {
            val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                putExtra(
                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    "Exam Go needs device admin permission to enable secure exam mode and prevent app switching during exams."
                )
            }

            // FIX: startActivityForResult deprecated di API 30+.
            // Pada Samsung One UI 5+ dan Android 12+ lainnya, panggilan
            // ini mungkin tidak mengembalikan result dengan benar.
            //
            // Solusi ideal: gunakan ActivityResultLauncher via ComponentActivity.
            // Karena KioskMethodChannel bukan Activity, kita delegate ke activity.
            //
            // Sementara gunakan startActivity (bukan startActivityForResult)
            // karena result-nya tidak dipakai di sini — hanya meminta izin.
            // Cek status admin via isDeviceAdmin() setelah user kembali.
            activity.startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun enableKioskMode(): Boolean {
        if (!isDeviceAdmin()) {
            return false
        }

        isKioskActive = true
        startLockTaskMode()
        hideSystemUI()
        blockRecentApps()
        activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        return true
    }

    private fun disableKioskMode(): Boolean {
        isKioskActive = false

        return try {
            stopLockTaskMode()
            showSystemUI()
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun startLockTaskMode(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                if (isDeviceAdmin()) {
                    devicePolicyManager?.setLockTaskPackages(
                        adminComponent!!,
                        arrayOf(activity.packageName)
                    )
                }
                activity.startLockTask()
                true
            } else {
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun stopLockTaskMode() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                activity.stopLockTask()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun hideSystemUI() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                activity.window.setDecorFitsSystemWindows(false)
                activity.window.insetsController?.apply {
                    hide(android.view.WindowInsets.Type.statusBars())
                    hide(android.view.WindowInsets.Type.navigationBars())
                    systemBarsBehavior = android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                }
            } else {
                @Suppress("DEPRECATION")
                activity.window.decorView.systemUiVisibility = (
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun showSystemUI() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                activity.window.insetsController?.apply {
                    show(android.view.WindowInsets.Type.statusBars())
                    show(android.view.WindowInsets.Type.navigationBars())
                }
            } else {
                @Suppress("DEPRECATION")
                activity.window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun blockRecentApps() {
        // Handled by Lock Task Mode
    }

    private fun checkBlockedApps(): String? {
        if (!hasUsageStatsPermission()) return null

        return try {
            val usageStatsManager = activity.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val currentTime = System.currentTimeMillis()

            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                currentTime - 500,
                currentTime
            )

            if (stats.isNullOrEmpty()) return null

            val sortedStats = stats.sortedByDescending { it.lastTimeUsed }
            val mostRecentApp = sortedStats.firstOrNull()

            if (mostRecentApp != null &&
                mostRecentApp.packageName != activity.packageName &&
                blockedApps.contains(mostRecentApp.packageName)) {
                getAppName(mostRecentApp.packageName)
            } else {
                null
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun getRunningApps(): List<String> {
        if (!hasUsageStatsPermission()) return emptyList()

        return try {
            val usageStatsManager = activity.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val currentTime = System.currentTimeMillis()

            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                currentTime - 1000,
                currentTime
            )

            stats?.map { it.packageName } ?: emptyList()
        } catch (e: Exception) {
            e.printStackTrace()
            emptyList()
        }
    }

    private fun getAppName(packageName: String): String {
        return try {
            val packageManager = activity.packageManager
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            packageName
        }
    }

    private fun hasUsageStatsPermission(): Boolean {
        return try {
            val appOps = activity.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    activity.packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    activity.packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun openUsageStatsSettings() {
        try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            activity.startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
## Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

## WebView
-keepclassmembers class * extends android.webkit.WebView {
   public *;
}
-keepclassmembers class * extends android.webkit.WebViewClient {
    public void *(android.webkit.WebView, java.lang.String, android.graphics.Bitmap);
    public boolean *(android.webkit.WebView, java.lang.String);
}
-keepclassmembers class * extends android.webkit.WebChromeClient {
     public void *(android.webkit.WebView, java.lang.String);
}

## Keep MainActivity
-keep class com.kemenag.examgo.MainActivity { *; }

## FIX BUG #6: ProGuard menghapus KioskMethodChannel dan ExamDeviceAdminReceiver
## di release build karena isMinifyEnabled = true. Ini menyebabkan:
##   - Method Channel 'com.examgo/kiosk' tidak teregister → NullPointerException
##   - DeviceAdminReceiver hilang → requestDeviceAdmin() gagal total
##   - ExamGoWebViewClient dihapus → RenderProcessGone tidak ter-handle

## Keep semua kelas ExamGO native
-keep class com.kemenag.examgo.** { *; }
-keepclassmembers class com.kemenag.examgo.** { *; }

## Keep DeviceAdminReceiver secara eksplisit (penting untuk kiosk mode)
-keep class com.kemenag.examgo.ExamDeviceAdminReceiver { *; }
-keep class com.kemenag.examgo.ExamGoWebViewClient { *; }
-keep class com.kemenag.examgo.KioskMethodChannel { *; }

## Keep Play Core classes (update untuk library baru)
-keep class com.google.android.play.core.** { *; }
-keep interface com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

## Keep Flutter embedding classes
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.embedding.engine.** { *; }
-dontwarn io.flutter.embedding.**

## Keep AndroidX Activity (untuk OnBackPressedDispatcher)
-keep class androidx.activity.** { *; }
-dontwarn androidx.activity.**

## Keep WebView platform (webview_flutter_android)
-keep class io.flutter.plugins.webviewflutter.** { *; }
-keepclassmembers class io.flutter.plugins.webviewflutter.** { *; }
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

## FIX WARN-4: Explicitly keep Firebase SDK classes sebagai failsafe.
## Firebase AAR sudah include consumer-rules.pro internal, tapi aturan eksplisit
## di sini memastikan tidak ada class yang hilang meski versi SDK berubah.

## Firebase Core & Messaging (FCM)
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

## Firebase Crashlytics — wajib untuk stack trace yang readable
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
-keep class com.google.firebase.crashlytics.** { *; }

## Firebase Analytics
-keep class com.google.android.datatransport.** { *; }

## Cloud Firestore
-keep class com.google.cloud.** { *; }
-keep class io.grpc.** { *; }
-dontwarn io.grpc.**
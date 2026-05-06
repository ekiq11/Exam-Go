// AppDelegate.swift
// ExamGO — iOS Native Layer
//
// Equivalent mapping dari Android:
//   MainActivity.kt           → AppDelegate + KioskViewController
//   KioskMethodChannel.kt     → KioskChannelHandler
//   ExamGoWebViewClient.kt    → WKNavigationDelegate di ExamGoWebViewProxy
//   ExamGoDeviceAdminReceiver → GuidedAccessController (iOS equivalent)
//
// Permission equivalents (Info.plist + runtime):
//   FLAG_SECURE               → UIScreen.isCaptured check + blur overlay
//   FLAG_KEEP_SCREEN_ON       → isIdleTimerDisabled = true
//   FLAG_FULLSCREEN           → prefersStatusBarHidden
//   WAKE_LOCK                 → isIdleTimerDisabled
//   CAMERA                    → NSCameraUsageDescription (Info.plist)
//   READ_EXTERNAL_STORAGE     → NSPhotoLibraryUsageDescription (Info.plist)

import UIKit
import Flutter
import WebKit

// ══════════════════════════════════════════════════════════════════
// MARK: - AppDelegate
// Equivalent: MainActivity.kt — setup, method channels, lifecycle
// ══════════════════════════════════════════════════════════════════

@main
@objc class AppDelegate: FlutterAppDelegate {

    private var isKioskActive = false
    private var flutterEngine = FlutterEngine(name: "main")

    // Screenshot-block overlay (setara FLAG_SECURE)
    private var secureOverlay: UIView?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // ── 1. Jalankan Flutter engine ──────────────────────────
        flutterEngine.run()
        GeneratedPluginRegistrant.register(with: flutterEngine)

        // ── 2. Root view controller: KioskViewController ────────
        //    Setara: android:launchMode="singleTop" + kiosk setup
        let kioskVC = KioskViewController(engine: flutterEngine, nibName: nil, bundle: nil)
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = kioskVC
        window?.makeKeyAndVisible()

        // ── 3. Daftarkan semua Method Channel ───────────────────
        //    Setara: configureFlutterEngine() di MainActivity.kt
        KioskChannelHandler.register(
            messenger: flutterEngine.binaryMessenger,
            delegate: self
        )

        // ── 4. Observe screenshot/screen recording ──────────────
        //    Setara: FLAG_SECURE di Android
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onScreenCaptureChanged),
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ══════════════════════════════════════════════════════════
    // MARK: FLAG_SECURE equivalent — blur saat screen recording
    // Setara: window.setFlags(FLAG_SECURE, FLAG_SECURE) di MainActivity
    // ══════════════════════════════════════════════════════════

    @objc private func onScreenCaptureChanged() {
        guard isKioskActive else { return }
        if UIScreen.main.isCaptured {
            showSecureOverlay()
        } else {
            hideSecureOverlay()
        }
    }

    private func showSecureOverlay() {
        guard secureOverlay == nil else { return }
        let overlay = UIView(frame: UIScreen.main.bounds)
        overlay.backgroundColor = .black
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let label = UILabel()
        label.text = "🔒 Rekaman layar tidak diizinkan saat ujian berlangsung"
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -32),
        ])

        window?.addSubview(overlay)
        secureOverlay = overlay
    }

    private func hideSecureOverlay() {
        secureOverlay?.removeFromSuperview()
        secureOverlay = nil
    }

    // ══════════════════════════════════════════════════════════
    // MARK: Kiosk Control
    // Setara: startLockTask() / stopLockTask() di MainActivity.kt
    // ══════════════════════════════════════════════════════════

    func enableKiosk() {
        isKioskActive = true

        // WAKE_LOCK equivalent — layar tidak mati
        UIApplication.shared.isIdleTimerDisabled = true

        // FLAG_FULLSCREEN equivalent — sembunyikan status bar & home indicator
        applyImmersive()

        // Device Admin equivalent — Guided Access prompt
        GuidedAccessController.requestIfNeeded(from: window?.rootViewController)
    }

    func disableKiosk() {
        isKioskActive = false
        UIApplication.shared.isIdleTimerDisabled = false
        hideSecureOverlay()
        NotificationCenter.default.post(name: .kioskModeChanged, object: false)
        window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
    }

    func applyImmersive() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .kioskModeChanged, object: true)
            self.window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: App Lifecycle
    // Setara: onResume() / onPause() / onDestroy() di MainActivity.kt
    // ══════════════════════════════════════════════════════════

    override func applicationDidBecomeActive(_ application: UIApplication) {
        if isKioskActive {
            // Re-apply immersive saat resume (setara onResume re-inject handler)
            applyImmersive()
            hideSecureOverlay()
        }
    }

    override func applicationWillResignActive(_ application: UIApplication) {
        if isKioskActive {
            // Blur content saat app di-background (tambahan keamanan)
            showSecureOverlay()
        }
    }

    override func applicationDidEnterBackground(_ application: UIApplication) {
        if isKioskActive {
            print("⚠️ App entered background while kiosk active")
        }
    }
}

// ══════════════════════════════════════════════════════════════════
// MARK: - KioskChannelHandler
// Equivalent: KioskMethodChannel.kt — semua method channel handler
// ══════════════════════════════════════════════════════════════════

class KioskChannelHandler {

    static func register(messenger: FlutterBinaryMessenger, delegate: AppDelegate) {
        // Channel utama kiosk
        FlutterMethodChannel(
            name: "com.kemenag.examgo/kiosk",
            binaryMessenger: messenger
        ).setMethodCallHandler { call, result in
            KioskChannelHandler.handleKiosk(call: call, result: result, delegate: delegate)
        }

        // Channel locktask (setara com.examgo/locktask di MainActivity.kt)
        FlutterMethodChannel(
            name: "com.examgo/locktask",
            binaryMessenger: messenger
        ).setMethodCallHandler { call, result in
            KioskChannelHandler.handleLockTask(call: call, result: result, delegate: delegate)
        }
    }

    // ── Kiosk channel handler ───────────────────────────────────
    private static func handleKiosk(
        call: FlutterMethodCall,
        result: @escaping FlutterResult,
        delegate: AppDelegate
    ) {
        switch call.method {
        case "enableKioskMode":
            delegate.enableKiosk()
            result(true)

        case "disableKioskMode":
            delegate.disableKiosk()
            result(true)

        case "startLockTask":
            // Setara: startLockTask() di MainActivity.kt
            delegate.enableKiosk()
            result(true)

        case "stopLockTask":
            // Setara: stopLockTask() di MainActivity.kt
            delegate.disableKiosk()
            result(nil)

        case "isKioskModeActive":
            result(delegate.isKioskActive)

        case "isLockTaskActive":
            // Compat alias
            result(delegate.isKioskActive)

        case "hideSystemUI":
            // Setara: FLAG_FULLSCREEN
            delegate.applyImmersive()
            result(nil)

        case "showSystemUI":
            result(nil)

        case "bringToForeground":
            // No-op di iOS — app selalu di foreground saat aktif
            result("brought_to_front")

        // ── Android-only methods — kembalikan nilai aman ───────
        // Setara: ExamGoDeviceAdminReceiver.kt capabilities
        case "isDeviceAdminEnabled":
            // iOS: Guided Access = closest equivalent
            result(UIAccessibility.isGuidedAccessEnabled)

        case "requestDeviceAdmin":
            // iOS: tidak bisa request secara programmatic, arahkan ke Settings
            GuidedAccessController.requestIfNeeded(
                from: UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first { $0.isKeyWindow }?.rootViewController
            )
            result(nil)

        case "checkBlockedApps":
            result(nil)

        case "getRunningApps":
            // iOS sandbox tidak bisa lihat app lain
            result([String]())

        case "checkUsageStatsPermission":
            result(true)

        case "openUsageStatsSettings":
            result(nil)

        case "blockRecentApps":
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ── LockTask channel handler ────────────────────────────────
    private static func handleLockTask(
        call: FlutterMethodCall,
        result: @escaping FlutterResult,
        delegate: AppDelegate
    ) {
        switch call.method {
        case "startLockTask":
            delegate.enableKiosk()
            result("lock_started")

        case "stopLockTask":
            delegate.disableKiosk()
            result("lock_stopped")

        case "bringToForeground":
            result("brought_to_front")

        case "isLockTaskActive":
            result(delegate.isKioskActive)

        case "isScreenOn":
            DispatchQueue.main.async {
                result(UIScreen.main.brightness > 0.0)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// ══════════════════════════════════════════════════════════════════
// MARK: - GuidedAccessController
// Equivalent: ExamGoDeviceAdminReceiver.kt
// Android Device Admin → iOS Guided Access (closest equivalent)
// ══════════════════════════════════════════════════════════════════

class GuidedAccessController {

    /// Tampilkan prompt Guided Access jika belum aktif.
    /// Setara: ExamGoDeviceAdminReceiver onEnabled / onDisabled.
    static func requestIfNeeded(from viewController: UIViewController?) {
        guard !UIAccessibility.isGuidedAccessEnabled else {
            print("✅ Guided Access sudah aktif")
            return
        }

        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "Aktifkan Kunci Ujian",
                message: """
                    Untuk keamanan ujian, aktifkan Guided Access agar aplikasi \
                    tidak bisa ditinggalkan selama ujian berlangsung.

                    Cara aktifkan:
                    1. Buka Pengaturan → Aksesibilitas → Guided Access → ON
                    2. Saat ujian dimulai, klik 3× tombol Home/Side
                    3. Pilih "Mulai"

                    Setara dengan Kiosk Mode di Android.
                    """,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Buka Pengaturan", style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            })
            alert.addAction(UIAlertAction(title: "Mengerti", style: .cancel))
            viewController?.present(alert, animated: true)
        }
    }

    /// Log status Guided Access (setara onReceive di DeviceAdminReceiver)
    static func logStatus() {
        let status = UIAccessibility.isGuidedAccessEnabled ? "AKTIF" : "TIDAK AKTIF"
        print("📱 Guided Access: \(status)")
    }
}

// ══════════════════════════════════════════════════════════════════
// MARK: - ExamGoWebViewProxy
// Equivalent: ExamGoWebViewClient.kt
// onRenderProcessGone → WKWebView navigationDelegate + didFailProvisionalNavigation
// ══════════════════════════════════════════════════════════════════

/// Proxy WKNavigationDelegate untuk menangani crash/error WebView.
/// Setara: ExamGoWebViewClient.onRenderProcessGone() di Android.
///
/// Cara pakai: inject ke WKWebView setelah Flutter inflate view-nya.
/// Flutter webview_flutter_wkwebview sudah handle ini secara internal,
/// tapi class ini tersedia jika ada WKWebView native yang perlu di-wrap.
class ExamGoWebViewProxy: NSObject, WKNavigationDelegate {

    private weak var originalDelegate: WKNavigationDelegate?

    init(wrapping delegate: WKNavigationDelegate?) {
        self.originalDelegate = delegate
        super.init()
    }

    // ── Setara: onRenderProcessGone — handle crash WebView ─────
    // Di iOS, WKWebView crash = webViewWebContentProcessDidTerminate
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        print("⚠️ WKWebView content process terminated — reloading")
        // Reload otomatis, setara return true di onRenderProcessGone
        webView.reload()
        // Teruskan ke delegate asli jika ada
        originalDelegate?.webViewWebContentProcessDidTerminate?(webView)
    }

    // ── Delegasi semua method lain ke original delegate ─────────
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        originalDelegate?.webView?(webView, didStartProvisionalNavigation: navigation)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        originalDelegate?.webView?(webView, didFinish: navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        originalDelegate?.webView?(webView, didFail: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        // NSURLErrorCancelled (-999) = navigasi dibatalkan, bukan error nyata
        // Setara: errorCode -3 (ERR_ABORTED) filter di qris_web_view.dart
        if nsError.code == NSURLErrorCancelled {
            return
        }
        print("⚠️ WKWebView provisional navigation failed: \(error.localizedDescription)")
        originalDelegate?.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let method = originalDelegate?.webView?(_:decidePolicyFor:decisionHandler:) {
            method(webView, navigationAction, decisionHandler)
        } else {
            decisionHandler(.allow)
        }
    }
}

// ══════════════════════════════════════════════════════════════════
// MARK: - KioskViewController
// Equivalent: bagian kiosk di MainActivity.kt
// Sembunyikan status bar, home indicator, blok swipe gesture
// ══════════════════════════════════════════════════════════════════

class KioskViewController: FlutterViewController {

    private var kioskActive = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // Blok swipe back (setara onBackPressed di MainActivity)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onKioskChanged(_:)),
            name: .kioskModeChanged,
            object: nil
        )
    }

    @objc private func onKioskChanged(_ notification: Notification) {
        kioskActive = notification.object as? Bool ?? false
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    // Sembunyikan status bar — setara FLAG_FULLSCREEN
    override var prefersStatusBarHidden: Bool { kioskActive }

    // Sembunyikan home indicator iPhone X+
    override var prefersHomeIndicatorAutoHidden: Bool { kioskActive }

    // Tahan swipe dari semua tepi layar — setara kiosk lock
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        kioskActive ? .all : []
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// ══════════════════════════════════════════════════════════════════
// MARK: - Notification Extension
// ══════════════════════════════════════════════════════════════════

extension Notification.Name {
    static let kioskModeChanged = Notification.Name("kioskModeChanged")
}

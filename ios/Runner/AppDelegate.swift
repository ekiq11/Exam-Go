import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {

    private var isKioskActive = false
    private var flutterEngine = FlutterEngine(name: "main")

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // ── 1. Jalankan engine dulu ─────────────────────────────
        flutterEngine.run()
        GeneratedPluginRegistrant.register(with: flutterEngine)

        // ── 2. Buat KioskViewController sebagai root ────────────
        let kioskVC = KioskViewController(engine: flutterEngine, nibName: nil, bundle: nil)
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = kioskVC
        window?.makeKeyAndVisible()

        // ── 3. Daftarkan Method Channel ─────────────────────────
        FlutterMethodChannel(
            name: "com.kemenag.examgo/kiosk",
            binaryMessenger: flutterEngine.binaryMessenger
        ).setMethodCallHandler(handleKiosk)

        FlutterMethodChannel(
            name: "com.kemenag.examgo/locktask",
            binaryMessenger: flutterEngine.binaryMessenger
        ).setMethodCallHandler(handleLockTask)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ══════════════════════════════════════════════════════
    // MARK: Channel Handlers
    // ══════════════════════════════════════════════════════

    private func handleKiosk(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "enableKioskMode":   enableKiosk();  result(true)
        case "disableKioskMode":  disableKiosk(); result(true)
        case "startLockTask":     enableKiosk();  result(true)
        case "stopLockTask":      disableKiosk(); result(nil)
        case "isKioskModeActive": result(isKioskActive)
        case "hideSystemUI":      applyImmersive(); result(nil)
        case "showSystemUI":      result(nil)

        // Method Android yang tidak ada di iOS — kembalikan nilai aman
        case "isDeviceAdminEnabled":      result(true)
        case "requestDeviceAdmin":        result(nil)
        case "checkBlockedApps":          result(nil)
        case "getRunningApps":            result([String]())
        case "checkUsageStatsPermission": result(true)
        case "openUsageStatsSettings":    result(nil)
        case "blockRecentApps":           result(nil)

        default: result(FlutterMethodNotImplemented)
        }
    }

    private func handleLockTask(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startLockTask":
            enableKiosk()
            result("lock_started")
        case "stopLockTask":
            disableKiosk()
            result("lock_stopped")
        case "bringToForeground":
            result("brought_to_front") // no-op di iOS
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: Kiosk Logic
    // ══════════════════════════════════════════════════════

    private func enableKiosk() {
        isKioskActive = true

        // Layar tidak mati (setara FLAG_KEEP_SCREEN_ON)
        UIApplication.shared.isIdleTimerDisabled = true

        // Sembunyikan status bar & home indicator
        applyImmersive()

        // Prompt Guided Access jika belum aktif
        showGuidedAccessPrompt()
    }

    private func disableKiosk() {
        isKioskActive = false
        UIApplication.shared.isIdleTimerDisabled = false

        // Tampilkan kembali status bar & home indicator
        NotificationCenter.default.post(name: .kioskModeChanged, object: false)
        window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
    }

    private func applyImmersive() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .kioskModeChanged, object: true)
            self.window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        }
    }

    private func showGuidedAccessPrompt() {
        guard !UIAccessibility.isGuidedAccessEnabled else { return }

        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "Mode Ujian Aktif",
                message: "Aktifkan Guided Access agar tidak bisa keluar aplikasi:\n\nSettings → Accessibility → Guided Access → ON\n\nAtau tekan tombol Home/Side 3× lalu pilih 'Mulai'.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Buka Pengaturan", style: .default) { _ in
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            })
            alert.addAction(UIAlertAction(title: "Sudah Mengerti", style: .cancel))
            self.window?.rootViewController?.present(alert, animated: true)
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: Foreground → terapkan ulang
    // ══════════════════════════════════════════════════════

    override func applicationDidBecomeActive(_ application: UIApplication) {
        if isKioskActive { applyImmersive() }
    }
}

// ══════════════════════════════════════════════════════════
// MARK: Notification Name
// ══════════════════════════════════════════════════════════

extension Notification.Name {
    static let kioskModeChanged = Notification.Name("kioskModeChanged")
}

// ══════════════════════════════════════════════════════════
// MARK: KioskViewController — digabung dalam 1 file
// ══════════════════════════════════════════════════════════

class KioskViewController: FlutterViewController {

    private var kioskActive = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // Blok swipe back gesture
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false

        // Dengarkan perubahan kiosk mode
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

    // Sembunyikan status bar saat kiosk aktif
    override var prefersStatusBarHidden: Bool {
        return kioskActive
    }

    // Sembunyikan home indicator (garis bawah iPhone X+)
    override var prefersHomeIndicatorAutoHidden: Bool {
        return kioskActive
    }

    // Tahan semua swipe dari tepi layar
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        return kioskActive ? .all : []
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
// SceneDelegate.swift
// ExamGO — iOS Scene Lifecycle Delegate (iOS 13+ / iOS 18+ UIScene requirement)

import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)
        guard let windowScene = scene as? UIWindowScene else { return }

        // Pastikan UIWindow selalu terikat ke UIWindowScene aktif
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            if let rootVC = appDelegate.window?.rootViewController, self.window == nil {
                let win = UIWindow(windowScene: windowScene)
                win.rootViewController = rootVC
                self.window = win
                appDelegate.window = win
                win.makeKeyAndVisible()
            }
        }
    }

    override func sceneDidBecomeActive(_ scene: UIScene) {
        super.sceneDidBecomeActive(scene)
        (UIApplication.shared.delegate as? AppDelegate)?.sceneDidBecomeActive()
    }

    override func sceneWillResignActive(_ scene: UIScene) {
        super.sceneWillResignActive(scene)
        (UIApplication.shared.delegate as? AppDelegate)?.sceneWillResignActive()
    }

    override func sceneDidEnterBackground(_ scene: UIScene) {
        super.sceneDidEnterBackground(scene)
        (UIApplication.shared.delegate as? AppDelegate)?.sceneDidEnterBackground()
    }
}

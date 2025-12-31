//
//  SceneDelegate.swift
//  CameraRecorderApp
//
//  Created by HandofGod-star on 12/30/25.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // 使用此方法可选地配置 UIWindow `window` 并将其附加到提供的 UIWindowScene `scene`
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // 如果使用 storyboard，`window` 属性将自动初始化并附加到场景
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        // 此代理并不意味着连接的场景或会话是新的（请改用 `application:configurationForConnectingSceneSession`）
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // Create window
        // 创建窗口
        window = UIWindow(windowScene: windowScene)
        
        // Create home view controller as entry point
        // 创建首页视图控制器作为入口点
        let homeViewController = HomeViewController()
        
        // Create navigation controller with home view controller as root
        // 创建导航控制器，以首页视图控制器作为根视图控制器
        let navigationController = UINavigationController(rootViewController: homeViewController)
        
        // Set as root view controller
        // 设置为根视图控制器
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }


}


//
//  Constants.swift
//  CameraRecorderApp
//
//  Created by HandofGod-star on 2025.
//

import UIKit

// 应用程序常量
struct Constants {
    // 屏幕安全区域边距
    static var screenSafeInset: UIEdgeInsets {
        if #available(iOS 11.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                return window.safeAreaInsets
            }
        }
        return UIEdgeInsets.zero
    }
}

// 线程安全的主队列调度辅助函数
extension Thread {
    // 安全地在主线程执行代码块
    static func safe_main(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}


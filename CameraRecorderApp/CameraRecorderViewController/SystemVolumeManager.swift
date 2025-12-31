import UIKit
import MediaPlayer

class SystemVolumeManager {
    static let shared = SystemVolumeManager()
    private var volumeView: MPVolumeView?
    
    private init() {
        // 私有初始化，确保单例模式
    }

    func setSystemVolume(_ value: Float, animated: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 先移除旧的 volumeView（如果存在）
            self.volumeView?.removeFromSuperview()
            self.volumeView = nil
            
            // 创建新的 volumeView
            let volumeView = MPVolumeView(frame: .zero)
            volumeView.isHidden = true
            
            // 获取当前窗口
            var targetWindow: UIWindow?
            if #available(iOS 13.0, *) {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    targetWindow = window
                }
            } else {
                targetWindow = UIApplication.shared.windows.first
            }
            
            guard let window = targetWindow else {
                return
            }
            
            // 添加到窗口
            window.addSubview(volumeView)
            self.volumeView = volumeView
            
            // 延迟设置音量，确保 slider 已经准备好
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
                    slider.setValue(value, animated: false)
                }
                
                // 设置完成后，延迟移除 volumeView（给系统时间应用设置）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.volumeView?.removeFromSuperview()
                    self?.volumeView = nil
                }
            }
        }
    }
}

//
//  CustomCameraRecorderViewController.swift
//  DeviceDetection
//
//  Created by HandofGod-star on 4/9/25.
//

import UIKit
import AVKit
import AVFoundation
import MobileCoreServices

// 导入 NextLevel（需要确保 NextLevel-main/Sources 已添加到项目中）
// 如果无法直接导入，可能需要添加桥接头文件或者将 NextLevel 作为模块导入

class CustomCameraRecorderViewController: UIViewController, NextLevelDelegate, NextLevelVideoDelegate {
  
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    
    // 视图层级优化：分离录制UI和预览层
    private var previewContainerView: UIView! // 视频预览容器（底层）
    private var recordingUIView: UIView! // 录制UI容器（上层，覆盖在预览上方）
    // 枚举定义摄像头类型
    enum CameraDeviceType {
        case front
        case rear
    }
    
    // 属性
    private let cameraDeviceType: CameraDeviceType
    private var recordedVideoURL: URL?
    
    // NextLevel 相关（替换原来的 AVCaptureSession）
    private let nextLevel = NextLevel.shared
    private var previewLayerView: UIView? // 用于显示 NextLevel 的预览层
    private var hasRequestedPermissions = false // 标记是否已经请求过权限
    private var hasStartedNextLevel = false // 标记是否已经启动过 NextLevel（避免重复启动）
    private var hasStoppedNextLevel = false // 标记是否已经停止过（避免重复停止）
    private var layoutConstraintsSetup = false // 标记是否已经设置过 Auto Layout 约束
    
    // UI 控件（录制界面）
    private var recordButton: UIButton!
    private var flipButton: UIButton!
    private var cancelButton: UIButton!
    private var recordingTimeLabel: UILabel!
    private var timeLabelBackgroundView: UIView!
    private var videoModeLabel: UILabel!
    private var statusIndicatorView: UIView!
    private var stopButtonSquareView: UIView! // 停止按钮内部的红色方块
    private var bottomControlBarBackground: UIView! // 底部控制栏背景蒙层
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var elapsedRecordingTime: TimeInterval = 0
    private var isRecording = false
    
    // UI 控件（预览界面）
    private var videoPreviewContainerView: UIView! // 视频预览容器（用于录制完成后的预览）
    private var videoPlaybackContainerView: UIView! // 视频播放容器（用于使用视频后的全屏播放）
    private var frameTimelineScrollView: UIScrollView!
    private var frameTimelineContentView: UIView!
    private var frameThumbnails: [UIImageView] = []
    private var playbackIndicatorView: UIView! // 播放位置指示器（白色竖线）
    private var videoPreviewView: UIView!
    private var retakeButton: UIButton!
    private var playPauseButton: UIButton!
    private var useVideoButton: UIButton!
    private var backButton: UIButton! // 使用视频后显示的返回按钮
    private var isPlaying = false
    private var playbackTimer: Timer?
    private var videoDuration: TimeInterval = 0
    private var frameTimelineWidth: CGFloat = 0
    private var isProcessingRecordTap = false // 防止重复点击的标志
    private var isProcessingCancel = false // 防止取消按钮重复点击的标志
    private var imageGenerator: AVAssetImageGenerator? // 用于生成缩略图的生成器
    private var fullScreenVideoView: UIView! // 全屏视频播放容器（用于使用视频后的播放）
    
    // 预生成的图标（避免每次点击时重新创建，提升响应速度）
    private var cachedPlayImage: UIImage?
    private var cachedPauseImage: UIImage?
    
    // 录制过程中捕获的帧（用于生成缩略图）
    private var capturedFrames: [(timestamp: TimeInterval, image: UIImage)] = [] // 存储时间戳和图片
    private let frameCaptureLock = NSLock() // 用于线程安全的锁
    
    // 检查当前语言是否为中文
    private var isChinese: Bool {
        return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
    }
    
    // 获取本地化字符串
    private func localizedString(_ key: String, chinese: String, english: String) -> String {
        return isChinese ? chinese : english
    }
    
    // 初始化方法
    init(cameraDeviceType: CameraDeviceType) {
        self.cameraDeviceType = cameraDeviceType
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupCamera()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // 只在 setupCamera 中启动相机，这里只确保预览层显示
        if nextLevel.isRunning {
            if nextLevel.previewLayer.superlayer == nil, let previewContainerView = previewContainerView {
                nextLevel.previewLayer.frame = previewContainerView.bounds
                nextLevel.previewLayer.videoGravity = .resizeAspectFill
                nextLevel.previewLayer.isHidden = false
                previewContainerView.layer.addSublayer(nextLevel.previewLayer)
            } else if nextLevel.previewLayer.superlayer != nil {
                nextLevel.previewLayer.isHidden = false
            }
        }
        
        // 不再在这里启动相机，避免重复启动
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // 确保视图显示后预览层 frame 已更新
        if nextLevel.isRunning && nextLevel.previewLayer.superlayer != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let previewContainerView = self.previewContainerView else {
                    return
                }
                self.nextLevel.previewLayer.frame = previewContainerView.bounds
                self.nextLevel.previewLayer.isHidden = false
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // 调用统一的资源清理方法（确保完全清理）
        cleanupAllResources()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update preview layer frame only if session is running and layer is already added
        // 仅在会话运行且预览层已添加时更新 frame
        if nextLevel.isRunning, let previewContainerView = previewContainerView {
            // Only update frame if layer is already added (don't add here, let delegate handle it)
            // 仅在预览层已添加时更新 frame（不要在这里添加，让 delegate 处理）
            if nextLevel.previewLayer.superlayer != nil {
                nextLevel.previewLayer.frame = previewContainerView.bounds
                nextLevel.previewLayer.isHidden = false
            }
        }
        
        // 更新预览界面的 playerLayer 的 frame（如果存在）
        if let playerLayer = playerLayer, let videoPreviewView = videoPreviewView {
            playerLayer.frame = videoPreviewView.bounds
        }
        
        // 更新全屏播放界面的 playerLayer 的 frame（如果存在）
        if let playerLayer = playerLayer, let videoPlaybackContainerView = videoPlaybackContainerView {
            let contentFrame = videoPlaybackContainerView.frame
            playerLayer.frame = CGRect(
                x: contentFrame.origin.x,
                y: contentFrame.origin.y,
                width: contentFrame.width,
                height: contentFrame.height - Constants.screenSafeInset.bottom
            )
        }
    }
    
    // 设置UI
    private func setupUI() {
        view.backgroundColor = .black
        
        // 创建视频预览容器（底层，用于显示相机预览）
        previewContainerView = UIView()
        previewContainerView.backgroundColor = .black
        view.addSubview(previewContainerView)
        previewContainerView.pinEdgesToSuperview()
        
        // 创建录制UI容器（上层，覆盖在预览上方，用于显示录制相关的UI控件）
        recordingUIView = UIView()
        recordingUIView.backgroundColor = .clear // 透明，不遮挡预览
        recordingUIView.isUserInteractionEnabled = true // 允许交互
        view.addSubview(recordingUIView) // 后添加的会在上层
        recordingUIView.pinEdgesToSuperview()
        
        // 创建顶部时间显示背景蒙层（半透明黑色背景，录制时显示红色背景）
        timeLabelBackgroundView = UIView()
        timeLabelBackgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.5) // 半透明黑色蒙层
        timeLabelBackgroundView.layer.cornerRadius = 6
        recordingUIView.addSubview(timeLabelBackgroundView)
        timeLabelBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            timeLabelBackgroundView.centerXAnchor.constraint(equalTo: recordingUIView.centerXAnchor),
            timeLabelBackgroundView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: -10),
            timeLabelBackgroundView.widthAnchor.constraint(equalToConstant: 120),
            timeLabelBackgroundView.heightAnchor.constraint(equalToConstant: 36)
        ])
        
        // 创建顶部时间显示标签（在背景蒙层中）
        recordingTimeLabel = UILabel()
        recordingTimeLabel.text = "00:00:00"
        recordingTimeLabel.textColor = .white
        recordingTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        recordingTimeLabel.textAlignment = .center
        recordingTimeLabel.backgroundColor = .clear
        timeLabelBackgroundView.addSubview(recordingTimeLabel)
        recordingTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            recordingTimeLabel.topAnchor.constraint(equalTo: timeLabelBackgroundView.topAnchor),
            recordingTimeLabel.leadingAnchor.constraint(equalTo: timeLabelBackgroundView.leadingAnchor),
            recordingTimeLabel.trailingAnchor.constraint(equalTo: timeLabelBackgroundView.trailingAnchor),
            recordingTimeLabel.bottomAnchor.constraint(equalTo: timeLabelBackgroundView.bottomAnchor)
        ])
        
        // 创建录制按钮（初始：红色圆形，白色外圈；录制中：白色边框，内部红色方块）
        recordButton = UIButton(type: .custom)
        recordButton.backgroundColor = .red  // 红色内圈
        recordButton.layer.cornerRadius = 35
        recordButton.layer.borderWidth = 4
        recordButton.layer.borderColor = UIColor.white.cgColor  // 白色外圈
        recordButton.clipsToBounds = false
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        recordingUIView.addSubview(recordButton)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            recordButton.centerXAnchor.constraint(equalTo: recordingUIView.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            recordButton.widthAnchor.constraint(equalToConstant: 70),
            recordButton.heightAnchor.constraint(equalToConstant: 70)
        ])
        
        // 创建停止按钮内部的红色方块（初始隐藏）
        let squareSize: CGFloat = 24
        stopButtonSquareView = UIView()
        stopButtonSquareView.backgroundColor = .red
        stopButtonSquareView.layer.cornerRadius = 4
        stopButtonSquareView.isHidden = true
        stopButtonSquareView.isUserInteractionEnabled = false
        recordButton.addSubview(stopButtonSquareView)
        stopButtonSquareView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stopButtonSquareView.centerXAnchor.constraint(equalTo: recordButton.centerXAnchor),
            stopButtonSquareView.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            stopButtonSquareView.widthAnchor.constraint(equalToConstant: squareSize),
            stopButtonSquareView.heightAnchor.constraint(equalToConstant: squareSize)
        ])
        
        // 创建"视频"模式标签（录制按钮正上方，白色文字，紧贴按钮）
        videoModeLabel = UILabel()
        videoModeLabel.text = localizedString("video", chinese: "视频", english: "Video")
        videoModeLabel.textColor = .white  // 白色文字（不是黄色）
        videoModeLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        videoModeLabel.textAlignment = .center
        recordingUIView.addSubview(videoModeLabel)
        videoModeLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            videoModeLabel.centerXAnchor.constraint(equalTo: recordingUIView.centerXAnchor),
            videoModeLabel.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -5)
        ])
        
        // 创建底部控制栏背景蒙层（包含录制按钮、取消按钮、翻转按钮和视频标签）
        // 注意：需要先添加背景，再添加按钮，这样背景在按钮下方
        bottomControlBarBackground = UIView()
        bottomControlBarBackground.backgroundColor = UIColor.black.withAlphaComponent(0.5) // 半透明黑色蒙层
        bottomControlBarBackground.isUserInteractionEnabled = false // 不阻挡按钮交互
        recordingUIView.addSubview(bottomControlBarBackground) // 先添加背景
        bottomControlBarBackground.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bottomControlBarBackground.leadingAnchor.constraint(equalTo: recordingUIView.leadingAnchor),
            bottomControlBarBackground.trailingAnchor.constraint(equalTo: recordingUIView.trailingAnchor),
            bottomControlBarBackground.bottomAnchor.constraint(equalTo: recordingUIView.bottomAnchor),
            bottomControlBarBackground.topAnchor.constraint(equalTo: videoModeLabel.topAnchor, constant: -15)
        ])
        
        // 确保背景在按钮和标签下方（但不遮挡它们）
        recordingUIView.sendSubviewToBack(bottomControlBarBackground)
        
        // 创建取消按钮（左侧，与录制按钮水平对齐）
        cancelButton = UIButton(type: .custom)
        cancelButton.setTitle(localizedString("cancel", chinese: "取消", english: "Cancel"), for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        recordingUIView.addSubview(cancelButton)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: recordingUIView.leadingAnchor, constant: 30),
            cancelButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor)
        ])
        
        flipButton = UIButton(type: .custom)
        // 创建自定义翻转图标（兼容iOS 13以下）
        let flipImage = createFlipCameraIcon(size: CGSize(width: 40, height: 40))
        flipButton.setImage( UIImage(named: "videochat_switch"), for: .normal)
        flipButton.tintColor = .white
        flipButton.imageView?.contentMode = .scaleAspectFit
        flipButton.imageEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        flipButton.tintColor = .white
        flipButton.addTarget(self, action: #selector(flipButtonTapped), for: .touchUpInside)
        recordingUIView.addSubview(flipButton)
        flipButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            flipButton.trailingAnchor.constraint(equalTo: recordingUIView.trailingAnchor, constant: -30),
            flipButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            flipButton.widthAnchor.constraint(equalToConstant: 50),
            flipButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        layoutConstraintsSetup = true
    }
    
    // 设置相机（使用 NextLevel）
    private func setupCamera() {
      
        // 配置音频会话
        configureAudioSessionForRecording()
        
        // 配置 NextLevel
        nextLevel.delegate = self
        nextLevel.videoDelegate = self
        
        // 设置摄像头位置
        nextLevel.devicePosition = cameraDeviceType == .front ? .front : .back
        
        // 设置录制模式为视频
        nextLevel.captureMode = .video
        
        // 配置视频设置
        nextLevel.videoConfiguration.preset = .high
        
        // 注意：不要在这里添加预览层，应该在 nextLevelSessionDidStart 回调中添加
        // Note: Don't add preview layer here, should add it in nextLevelSessionDidStart callback
        
        // 请求权限并启动
        hasRequestedPermissions = true
        NextLevel.requestAuthorization(forMediaType: .video) { [weak self] (mediaType, status) in
            guard let self = self else { return }
            if status == .authorized {
                NextLevel.requestAuthorization(forMediaType: .audio) { [weak self] (mediaType, status) in
                    guard let self = self else { return }
                    if status == .authorized {
                        Thread.safe_main {
                            // 检查是否已经启动，避免重复启动
                            if self.nextLevel.isRunning {
                                self.hasStartedNextLevel = true
                                return
                            }
                            
                            do {
                                try self.nextLevel.start()
                                self.hasStartedNextLevel = true
                                self.hasStoppedNextLevel = false
                                
                                // 预览层将在 nextLevelSessionDidStart 回调中添加
                            } catch let error as NextLevelError {
                                var errorMessage = self.localizedString("cameraStartFailed", chinese: "启动相机失败", english: "Failed to start camera")
                                switch error {
                                case .authorization:
                                    errorMessage = self.localizedString("authorizationDenied", chinese: "权限未授权", english: "Authorization denied")
                                case .started:
                                    // 已经启动，不需要显示错误
                                    self.hasStartedNextLevel = true
                                    self.hasStoppedNextLevel = false
                                    return
                                case .deviceNotAvailable:
                                    errorMessage = self.localizedString("deviceNotAvailable", chinese: "设备不可用", english: "Device not available")
                                case .notReadyToRecord:
                                    errorMessage = self.localizedString("notReadyToRecord", chinese: "未准备好录制", english: "Not ready to record")
                                case .unknown:
                                    errorMessage = self.localizedString("unknownError", chinese: "未知错误", english: "Unknown error")
                                default:
                                    errorMessage = error.description
                                }
                                self.showAlert(title: self.localizedString("error", chinese: "错误", english: "Error"), message: "\(self.localizedString("cameraStartFailed", chinese: "启动相机失败", english: "Failed to start camera")): \(errorMessage)")
                            } catch {
                                self.showAlert(title: self.localizedString("error", chinese: "错误", english: "Error"), message: "\(self.localizedString("cameraStartFailed", chinese: "启动相机失败", english: "Failed to start camera")): \(error.localizedDescription)")
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.showAlert(title: self.localizedString("error", chinese: "错误", english: "Error"), message: self.localizedString("microphonePermissionRequired", chinese: "需要麦克风权限", english: "Microphone permission required"))
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.showAlert(title: self.localizedString("error", chinese: "错误", english: "Error"), message: self.localizedString("cameraPermissionRequired", chinese: "需要相机权限", english: "Camera permission required"))
                }
            }
        }
    }
    
    // 录制按钮点击
    @objc private func recordButtonTapped() {
        // 防止重复点击（使用标志位，更轻量）
        guard !isProcessingRecordTap else {
            return
        }
        isProcessingRecordTap = true
        
        // 立即更新UI（在主线程，同步执行，快速反馈）
        if isRecording {
            // 停止录制的UI更新
            updateUIForStoppedRecording()
            self.stopRecording()
            self.isProcessingRecordTap = false
        } else {
            // 开始录制的UI更新
            updateUIForStartedRecording()
            // 开始录制操作（可能耗时，异步执行）
            self.startRecording()
            self.isProcessingRecordTap = false
        }
    }
    
    // 更新UI为开始录制状态（主线程同步执行，快速反馈）
    private func updateUIForStartedRecording() {
        // 更新状态
        isRecording = true
        recordingStartTime = Date()
        elapsedRecordingTime = 0
        
        // 清理之前捕获的帧
        frameCaptureLock.lock()
        capturedFrames.removeAll()
        frameCaptureLock.unlock()
        
        // 立即同步更新UI状态（在主线程，同步执行以确保即时反馈）
        // 停止按钮样式：白色边框，透明背景，显示内部红色方块
        recordButton?.backgroundColor = .clear
        recordButton?.layer.borderColor = UIColor.white.cgColor
        stopButtonSquareView?.isHidden = false
        
        // 更新时间标签背景为红色矩形（不透明）
        timeLabelBackgroundView?.backgroundColor = UIColor.red
        recordingTimeLabel?.textColor = .white
        
        // 隐藏不需要的UI元素
        cancelButton?.isHidden = true
        flipButton?.isHidden = true
        videoModeLabel?.isHidden = true
        
        // 启动计时器
        startRecordingTimer()
    }
    
    // 开始录制（使用 NextLevel）
    private func startRecording() {
        self.nextLevel.record()
    }
    
    // 更新UI为停止录制状态（主线程同步执行，快速反馈）
    private func updateUIForStoppedRecording() {
        // 立即更新状态，防止重复调用
        isRecording = false
        
        // 停止计时器
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // 立即同步更新UI状态（主线程同步执行，确保即时反馈）
        // 恢复录制按钮样式：红色背景，隐藏内部方块
        recordButton?.backgroundColor = .red
        recordButton?.layer.borderColor = UIColor.white.cgColor
        stopButtonSquareView?.isHidden = true
        
        // 恢复时间标签背景为透明（初始状态无背景框）
        timeLabelBackgroundView?.backgroundColor = UIColor.clear
        recordingTimeLabel?.textColor = .white
        
        // 显示UI元素
        cancelButton?.isHidden = false
        if cameraDeviceType == .rear {
            flipButton?.isHidden = false
        }
        videoModeLabel?.isHidden = false
        
        // 重置时间显示
        recordingTimeLabel?.text = "00:00:00"
        elapsedRecordingTime = 0
    }
    
    // 停止录制（使用 NextLevel）
    private func stopRecording() {
        self.nextLevel.pause()
    }
    
    // 启动录制计时器
    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            self.elapsedRecordingTime += 0.1
            self.updateRecordingTime()
        }
    }
    
    // 更新录制时间显示（格式：00:00:06）
    private func updateRecordingTime() {
        let totalSeconds = Int(elapsedRecordingTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        // 直接在主线程更新，避免过多dispatch（已在主线程）
        recordingTimeLabel?.text = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    // 取消按钮
    @objc private func cancelButtonTapped() {
        // 防止重复点击
        guard !isProcessingCancel else {
            return
        }
        isProcessingCancel = true
        
        // 完全清理所有资源，防止多次操作时资源冲突
        cleanupAllResources()
        
        // Dismiss the view controller
        // 关闭视图控制器
        dismiss(animated: true, completion: nil)
    }
    
    // 清理所有资源的辅助方法
    private func cleanupAllResources() {
        // 1. 停止录制（如果正在录制）
        if isRecording {
            nextLevel.pause()
            isRecording = false
        }
        
        // 2. 停止并清理计时器
        recordingTimer?.invalidate()
        recordingTimer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        // 3. 停止播放（如果正在播放）
        player?.pause()
        isPlaying = false
        
        // 4. 移除播放器观察者
        if let player = player, let playerItem = player.currentItem {
            NotificationCenter.default.removeObserver(self,
                                                      name: .AVPlayerItemDidPlayToEndTime,
                                                      object: playerItem)
        }
        
        // 5. 清理播放器资源
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player = nil
        
        // 6. 停止 NextLevel 会话（重要：防止资源冲突）
        // 先停止录制，再停止会话，最后清理代理
        if nextLevel.isRecording {
            nextLevel.pause()
        }
        
        // 等待录制完全停止后再停止会话（给 NextLevel 一些时间清理内部资源）
        if nextLevel.isRunning {
            nextLevel.stop()
            hasStoppedNextLevel = true
            hasStartedNextLevel = false
        }
        
        // 7. 在主线程安全地移除 NextLevel 预览层
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.nextLevel.previewLayer.superlayer != nil {
                self.nextLevel.previewLayer.removeFromSuperlayer()
            }
            
            // 8. 清理 NextLevel 代理（在移除预览层后清理，确保所有操作完成）
            self.nextLevel.delegate = nil
            self.nextLevel.videoDelegate = nil
        }
        
        // 9. 清理其他资源
        imageGenerator = nil
        frameCaptureLock.lock()
        capturedFrames.removeAll()
        frameCaptureLock.unlock()
        frameThumbnails.removeAll()
    }
    
    // 翻转摄像头（使用 NextLevel，添加闪烁效果）
    @objc private func flipButtonTapped() {
        // 创建闪烁效果：白色遮罩覆盖整个屏幕
        let flashView = UIView()
        flashView.backgroundColor = .white
        flashView.alpha = 0
        view.addSubview(flashView)
        flashView.pinEdgesToSuperview()
        
        // 执行摄像头切换
        nextLevel.flipCaptureDevicePosition()
        
        // 闪烁动画：快速显示到高透明度然后淡出
        UIView.animate(withDuration: 0.1, animations: {
            flashView.alpha = 0.95 // 快速显示到几乎完全不透明
        }) { _ in
            UIView.animate(withDuration: 0.15, animations: {
                flashView.alpha = 0 // 然后快速淡出
            }) { _ in
                flashView.removeFromSuperview()
            }
        }
    }
    
    // 显示录制完成后的预览界面
    private func playRecordedVideo() {
        guard let videoURL = recordedVideoURL else {
            return
        }
        configureAudioSessionForPlayback()
        
        // 隐藏录制界面的UI元素
        hideRecordingUI()
        
        // 显示预览界面
        setupPreviewUI()
        
        // 加载视频并生成帧缩略图
        loadVideoAndGenerateThumbnails(videoURL: videoURL)
    }
    
    // 隐藏录制界面UI
    private func hideRecordingUI() {
        recordButton?.isHidden = true
        cancelButton?.isHidden = true
        flipButton?.isHidden = true
        videoModeLabel?.isHidden = true
        recordingTimeLabel?.isHidden = true
        timeLabelBackgroundView?.isHidden = true
        statusIndicatorView?.isHidden = true
        nextLevel.previewLayer.isHidden = true
        recordingUIView?.isHidden = true // 隐藏整个录制UI容器
    }
    
    // 设置预览界面UI（使用原生 Auto Layout 自动布局）
    private func setupPreviewUI() {
        view.backgroundColor = .black
        
        // 创建预览容器视图（用于录制完成后的视频预览）
        videoPreviewContainerView = UIView()
        videoPreviewContainerView.backgroundColor = .black
        // 确保在最上层，覆盖录制UI
        view.addSubview(videoPreviewContainerView)
        view.bringSubviewToFront(videoPreviewContainerView)
        videoPreviewContainerView.pinEdgesToSuperview()
        
        let timelineHeight: CGFloat = 80
        let controlBarHeight: CGFloat = 80
        
        // 创建帧时间轴滚动视图（顶部）
        frameTimelineScrollView = UIScrollView()
        frameTimelineScrollView.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
        frameTimelineScrollView.showsHorizontalScrollIndicator = true
        frameTimelineScrollView.delegate = self
        videoPreviewContainerView.addSubview(frameTimelineScrollView)
        frameTimelineScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            frameTimelineScrollView.leadingAnchor.constraint(equalTo: videoPreviewContainerView.leadingAnchor),
            frameTimelineScrollView.trailingAnchor.constraint(equalTo: videoPreviewContainerView.trailingAnchor),
            frameTimelineScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            frameTimelineScrollView.heightAnchor.constraint(equalToConstant: timelineHeight)
        ])
        
        // 创建内容视图容器
        frameTimelineContentView = UIView()
        frameTimelineContentView.backgroundColor = .clear
        frameTimelineScrollView.addSubview(frameTimelineContentView)
        frameTimelineContentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            frameTimelineContentView.topAnchor.constraint(equalTo: frameTimelineScrollView.topAnchor),
            frameTimelineContentView.leadingAnchor.constraint(equalTo: frameTimelineScrollView.leadingAnchor),
            frameTimelineContentView.trailingAnchor.constraint(equalTo: frameTimelineScrollView.trailingAnchor),
            frameTimelineContentView.bottomAnchor.constraint(equalTo: frameTimelineScrollView.bottomAnchor),
            frameTimelineContentView.heightAnchor.constraint(equalToConstant: timelineHeight)
        ])
        
        // 创建播放位置指示器（白色竖线）
        playbackIndicatorView = UIView()
        playbackIndicatorView.backgroundColor = .white
        frameTimelineScrollView.addSubview(playbackIndicatorView)
        playbackIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playbackIndicatorView.topAnchor.constraint(equalTo: frameTimelineScrollView.topAnchor),
            playbackIndicatorView.bottomAnchor.constraint(equalTo: frameTimelineScrollView.bottomAnchor),
            playbackIndicatorView.widthAnchor.constraint(equalToConstant: 2),
            playbackIndicatorView.leadingAnchor.constraint(equalTo: frameTimelineScrollView.leadingAnchor)
        ])
        
        // 创建视频预览区域（中间）- 全屏显示，控制栏会覆盖在视频上方
        videoPreviewView = UIView()
        videoPreviewView.backgroundColor = .black
        videoPreviewContainerView.addSubview(videoPreviewView)
        videoPreviewView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            videoPreviewView.leadingAnchor.constraint(equalTo: videoPreviewContainerView.leadingAnchor),
            videoPreviewView.trailingAnchor.constraint(equalTo: videoPreviewContainerView.trailingAnchor),
            videoPreviewView.topAnchor.constraint(equalTo: frameTimelineScrollView.bottomAnchor),
            videoPreviewView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -controlBarHeight)
        ])
        
        // 创建底部控制栏
        let controlBar = UIView()
        controlBar.tag = 999 // 用于标识控制栏
        controlBar.backgroundColor = UIColor(white: 0.2, alpha: 0.9)
        videoPreviewContainerView.addSubview(controlBar)
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controlBar.leadingAnchor.constraint(equalTo: videoPreviewContainerView.leadingAnchor),
            controlBar.trailingAnchor.constraint(equalTo: videoPreviewContainerView.trailingAnchor),
            controlBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            controlBar.heightAnchor.constraint(equalToConstant: controlBarHeight)
        ])
        
        // 创建重拍按钮（左侧）
        retakeButton = UIButton(type: .custom)
        retakeButton.setTitle(localizedString("retake", chinese: "重拍", english: "Retake"), for: .normal)
        retakeButton.setTitleColor(.white, for: .normal)
        retakeButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        retakeButton.addTarget(self, action: #selector(retakeButtonTapped), for: .touchUpInside)
        controlBar.addSubview(retakeButton)
        retakeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            retakeButton.leadingAnchor.constraint(equalTo: controlBar.leadingAnchor, constant: 30),
            retakeButton.topAnchor.constraint(equalTo: controlBar.topAnchor),
            retakeButton.bottomAnchor.constraint(equalTo: controlBar.bottomAnchor),
            retakeButton.widthAnchor.constraint(equalToConstant: 80)
        ])
        
        // 创建播放/暂停按钮（中间）
        playPauseButton = UIButton(type: .custom)
        playPauseButton.backgroundColor = .clear
        // 预生成并缓存图标（提升点击响应速度）
        cachedPlayImage = createPlayIcon(size: CGSize(width: 30, height: 30))
        cachedPauseImage = createPauseIcon(size: CGSize(width: 30, height: 30))
        playPauseButton.setImage(cachedPlayImage, for: .normal)
        playPauseButton.tintColor = .white
        playPauseButton.addTarget(self, action: #selector(playPauseButtonTapped), for: .touchUpInside)
        controlBar.addSubview(playPauseButton)
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playPauseButton.centerXAnchor.constraint(equalTo: controlBar.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 60),
            playPauseButton.heightAnchor.constraint(equalToConstant: 60)
        ])
        
        // 创建使用视频按钮（右侧）
        useVideoButton = UIButton(type: .custom)
        useVideoButton.setTitle(localizedString("useVideo", chinese: "使用视频", english: "Use Video"), for: .normal)
        useVideoButton.setTitleColor(.white, for: .normal)
        useVideoButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        useVideoButton.addTarget(self, action: #selector(useVideoButtonTapped), for: .touchUpInside)
        controlBar.addSubview(useVideoButton)
        useVideoButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            useVideoButton.trailingAnchor.constraint(equalTo: controlBar.trailingAnchor, constant: -30),
            useVideoButton.topAnchor.constraint(equalTo: controlBar.topAnchor),
            useVideoButton.bottomAnchor.constraint(equalTo: controlBar.bottomAnchor),
            useVideoButton.widthAnchor.constraint(equalToConstant: 80)
        ])
    }
    
    // 创建翻转摄像头图标（相机图标带旋转箭头）
    private func createFlipCameraIcon(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setStroke()
            UIColor.white.setFill()
            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            
            // 绘制相机主体（矩形，更简化）
            let cameraWidth = size.width * 0.35
            let cameraHeight = size.height * 0.4
            let cameraX = size.width * 0.15
            let cameraY = size.height * 0.3
            let cameraRect = CGRect(x: cameraX, y: cameraY, width: cameraWidth, height: cameraHeight)
            context.cgContext.setLineWidth(2.5)
            context.cgContext.stroke(cameraRect)
            
            // 绘制相机镜头（圆形）
            let lensCenter = CGPoint(x: cameraX + cameraWidth / 2, y: cameraY + cameraHeight / 2)
            let lensRadius = size.width * 0.06
            context.cgContext.setLineWidth(2.0)
            context.cgContext.strokeEllipse(in: CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius, 
                                                       width: lensRadius * 2, height: lensRadius * 2))
            
            // 绘制旋转箭头（双弧形箭头，表示翻转）
            let arrowRadius = size.width * 0.25
            let arrowCenterX = size.width * 0.7
            let arrowCenterY = size.height * 0.35
            
            // 上方箭头（弧形）
            let topArrowCenter = CGPoint(x: arrowCenterX, y: arrowCenterY - arrowRadius * 0.3)
            let topArrowPath = UIBezierPath(arcCenter: topArrowCenter, radius: arrowRadius, 
                                           startAngle: -CGFloat.pi * 0.6, endAngle: CGFloat.pi * 0.6, clockwise: true)
            context.cgContext.setLineWidth(2.5)
            context.cgContext.addPath(topArrowPath.cgPath)
            context.cgContext.strokePath()
            
            // 上方箭头头部
            let topArrowAngle = CGFloat.pi * 0.6
            let topArrowEndX = topArrowCenter.x + arrowRadius * cos(topArrowAngle)
            let topArrowEndY = topArrowCenter.y + arrowRadius * sin(topArrowAngle)
            let topArrowHead = UIBezierPath()
            topArrowHead.move(to: CGPoint(x: topArrowEndX, y: topArrowEndY))
            topArrowHead.addLine(to: CGPoint(x: topArrowEndX - 5 * cos(topArrowAngle - CGFloat.pi / 5),
                                            y: topArrowEndY - 5 * sin(topArrowAngle - CGFloat.pi / 5)))
            topArrowHead.move(to: CGPoint(x: topArrowEndX, y: topArrowEndY))
            topArrowHead.addLine(to: CGPoint(x: topArrowEndX - 5 * cos(topArrowAngle + CGFloat.pi / 5),
                                            y: topArrowEndY - 5 * sin(topArrowAngle + CGFloat.pi / 5)))
            context.cgContext.setLineWidth(2.5)
            context.cgContext.addPath(topArrowHead.cgPath)
            context.cgContext.strokePath()
            
            // 下方箭头（反向弧形）
            let bottomArrowCenter = CGPoint(x: arrowCenterX, y: arrowCenterY + arrowRadius * 0.3)
            let bottomArrowPath = UIBezierPath(arcCenter: bottomArrowCenter, radius: arrowRadius, 
                                              startAngle: CGFloat.pi - CGFloat.pi * 0.6, endAngle: CGFloat.pi + CGFloat.pi * 0.6, clockwise: true)
            context.cgContext.setLineWidth(2.5)
            context.cgContext.addPath(bottomArrowPath.cgPath)
            context.cgContext.strokePath()
            
            // 下方箭头头部
            let bottomArrowAngle = CGFloat.pi - CGFloat.pi * 0.6
            let bottomArrowEndX = bottomArrowCenter.x + arrowRadius * cos(bottomArrowAngle)
            let bottomArrowEndY = bottomArrowCenter.y + arrowRadius * sin(bottomArrowAngle)
            let bottomArrowHead = UIBezierPath()
            bottomArrowHead.move(to: CGPoint(x: bottomArrowEndX, y: bottomArrowEndY))
            bottomArrowHead.addLine(to: CGPoint(x: bottomArrowEndX - 5 * cos(bottomArrowAngle - CGFloat.pi / 5),
                                               y: bottomArrowEndY - 5 * sin(bottomArrowAngle - CGFloat.pi / 5)))
            bottomArrowHead.move(to: CGPoint(x: bottomArrowEndX, y: bottomArrowEndY))
            bottomArrowHead.addLine(to: CGPoint(x: bottomArrowEndX - 5 * cos(bottomArrowAngle + CGFloat.pi / 5),
                                               y: bottomArrowEndY - 5 * sin(bottomArrowAngle + CGFloat.pi / 5)))
            context.cgContext.setLineWidth(2.5)
            context.cgContext.addPath(bottomArrowHead.cgPath)
            context.cgContext.strokePath()
        }
    }
    
    // 创建播放图标（白色三角形）
    private func createPlayIcon(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.close()
            path.fill()
        }
    }
    
    // 创建暂停图标（两个白色矩形）
    private func createPauseIcon(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            let barWidth: CGFloat = size.width / 4
            let barHeight = size.height
            let spacing: CGFloat = size.width / 4
            
            // 左矩形
            let leftRect = CGRect(x: (size.width - barWidth * 2 - spacing) / 2, y: 0, width: barWidth, height: barHeight)
            context.cgContext.fill(leftRect)
            
            // 右矩形
            let rightRect = CGRect(x: leftRect.maxX + spacing, y: 0, width: barWidth, height: barHeight)
            context.cgContext.fill(rightRect)
        }
    }
    
    // 加载视频并生成帧缩略图
    private func loadVideoAndGenerateThumbnails(videoURL: URL) {
        let asset = AVAsset(url: videoURL)
        
        // 获取视频时长
        videoDuration = CMTimeGetSeconds(asset.duration)
        // 创建AVPlayer
        player = AVPlayer(url: videoURL)
        guard let player = player else {
            return
        }
        
        // 创建PlayerLayer
        playerLayer = AVPlayerLayer(player: player)
        guard let playerLayer = playerLayer else { return }
        playerLayer.frame = videoPreviewView.bounds
        // 使用 resizeAspectFill 让视频填满整个预览区域（裁剪而不是留黑边）
        playerLayer.videoGravity = .resizeAspectFill
        videoPreviewView.layer.addSublayer(playerLayer)
        
        // 确保视频正确应用 preferredTransform（处理方向）
        if let videoTrack = asset.tracks(withMediaType: .video).first {
            let transform = videoTrack.preferredTransform
        }
        
        // 添加播放结束观察
        NotificationCenter.default.addObserver(self,
                                             selector: #selector(videoDidEnd),
                                             name: .AVPlayerItemDidPlayToEndTime,
                                             object: player.currentItem)
        
        // 预加载播放缓冲（提升点击播放时的响应速度）
        if let playerItem = player.currentItem {
            // 预加载第一个画面帧（提升首帧显示速度）
            // 使用异步方式预加载，避免阻塞主线程
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                // 预加载到开始位置
                playerItem.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    // 预加载完成，可以快速开始播放
                }
            }
        }
        
        // 生成帧缩略图（暂时禁用，测试是否导致卡顿）
         generateFrameThumbnails(asset: asset)
    }
    
    // 生成视频帧缩略图（使用录制过程中捕获的帧或从视频文件生成）
    private func generateFrameThumbnails(asset: AVAsset) {
        
        // 先尝试使用录制过程中捕获的帧
        frameCaptureLock.lock()
        let frames = capturedFrames
        let frameCount = frames.count
        frameCaptureLock.unlock()
        
        if !frames.isEmpty && videoDuration > 0 {
            // 使用捕获的帧生成缩略图
            generateThumbnailsFromCapturedFrames(frames: frames)
        } else {
            if frames.isEmpty {
            } else {
            }
            // 如果没有捕获的帧，使用 AVAssetImageGenerator 从视频生成
            generateThumbnailsFromAsset(asset: asset)
        }
        
        // 清理捕获的帧（在生成完成后）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.frameCaptureLock.lock()
            let count = self?.capturedFrames.count ?? 0
            self?.capturedFrames.removeAll()
            self?.frameCaptureLock.unlock()
        }
    }
    
    // 从录制过程中捕获的帧生成缩略图
    private func generateThumbnailsFromCapturedFrames(frames: [(timestamp: TimeInterval, image: UIImage)]) {
        guard videoDuration > 0 else {
            return
        }
        
        let frameCount = min(20, frames.count) // 最多20个缩略图
        let thumbnailSize: CGFloat = 60
        let spacing: CGFloat = 2
        
        frameThumbnails.removeAll()
        frameTimelineContentView.subviews.forEach { $0.removeFromSuperview() }
        
        // 从捕获的帧中均匀选择帧来生成缩略图
        var selectedFrames: [(index: Int, image: UIImage, timestamp: TimeInterval)] = []
        if frames.count >= frameCount {
            // 如果捕获的帧足够多，均匀选择
            let step = max(1, frames.count / frameCount)
            for i in 0..<frameCount {
                let frameIndex = i * step
                if frameIndex < frames.count {
                    let frame = frames[frameIndex]
                    selectedFrames.append((index: i, image: frame.image, timestamp: frame.timestamp))
                }
            }
        } else {
            // 如果捕获的帧不够，全部使用，按时间戳排序
            let sortedFrames = frames.sorted { $0.timestamp < $1.timestamp }
            for (index, frame) in sortedFrames.enumerated() {
                selectedFrames.append((index: index, image: frame.image, timestamp: frame.timestamp))
            }
        }
        // 在主线程更新UI
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            var xOffset: CGFloat = 0
            for frameInfo in selectedFrames {
                // 调整图片大小
                let thumbnail = self.resizeImage(frameInfo.image, targetSize: CGSize(width: thumbnailSize, height: thumbnailSize))
                
                let thumbnailView = UIImageView(frame: CGRect(x: xOffset, y: 10, width: thumbnailSize, height: thumbnailSize))
                thumbnailView.image = thumbnail
                thumbnailView.contentMode = .scaleAspectFill
                thumbnailView.clipsToBounds = true
                thumbnailView.layer.cornerRadius = 4
                
                // 确保数组大小足够
                while self.frameThumbnails.count <= frameInfo.index {
                    self.frameThumbnails.append(UIImageView())
                }
                
                // 如果已经存在，先移除
                if frameInfo.index < self.frameThumbnails.count {
                    self.frameThumbnails[frameInfo.index].removeFromSuperview()
                }
                
                self.frameTimelineContentView.addSubview(thumbnailView)
                self.frameThumbnails[frameInfo.index] = thumbnailView
                
                xOffset += thumbnailSize + spacing
            }
            
            // 更新内容大小
            self.frameTimelineWidth = xOffset
            self.frameTimelineContentView.frame = CGRect(x: 0, y: 0, width: self.frameTimelineWidth, height: 80)
            self.frameTimelineScrollView.contentSize = CGSize(width: self.frameTimelineWidth, height: 80)
        }
    }
    
    // 从视频资源生成缩略图（备用方法）
    private func generateThumbnailsFromAsset(asset: AVAsset) {
        // ✅ 先清理旧的生成器
        imageGenerator = nil
        
        // 创建新的生成器
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600) // 允许一些容差，避免精确匹配问题
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 120, height: 120) // 限制尺寸以提高性能
        imageGenerator = generator
        
        // 生成约20个缩略图帧
        let frameCount = 20
        let thumbnailSize: CGFloat = 60
        let spacing: CGFloat = 2
        
        frameThumbnails.removeAll()
        frameTimelineContentView.subviews.forEach { $0.removeFromSuperview() }
        
        // 使用 NSValue 包装 CMTime，避免直接使用 CMTime 作为 key
        var times: [CMTime] = []
        var timeValueToIndexMap: [Double: Int] = [:] // 使用时间戳（Double）作为 key，更安全
        for i in 0..<frameCount {
            let timeValue = Double(i) / Double(frameCount) * videoDuration
            let time = CMTime(seconds: timeValue, preferredTimescale: 600)
            times.append(time)
            timeValueToIndexMap[timeValue] = i
        }
        // 使用字典来存储已生成的缩略图，按索引排序
        var thumbnailsByIndex: [Int: UIImage] = [:]
        var completedCount = 0
        let lock = NSLock() // 用于线程安全
        
        // 使用异步生成，避免阻塞主线程
        generator.generateCGImagesAsynchronously(forTimes: times.map { NSValue(time: $0) }) { [weak self] requestedTime, cgImage, actualTime, result, error in
            guard let self = self else { return }
            
            if let error = error {
                return
            }
            
            guard let cgImage = cgImage else {
                return
            }
            
            // 使用时间戳找到对应的索引（避免直接使用 CMTime）
            let requestedTimeValue = CMTimeGetSeconds(requestedTime)
            let actualTimeValue = CMTimeGetSeconds(actualTime)
            
            // 找到最接近的时间值对应的索引
            var index = 0
            var minDiff = Double.greatestFiniteMagnitude
            for (timeValue, idx) in timeValueToIndexMap {
                let diff = abs(timeValue - requestedTimeValue)
                if diff < minDiff {
                    minDiff = diff
                    index = idx
                }
            }
            
            lock.lock()
            thumbnailsByIndex[index] = UIImage(cgImage: cgImage)
            completedCount += 1
            let totalCompleted = completedCount
            lock.unlock()
            
            DispatchQueue.main.async {
                lock.lock()
                guard let thumbnail = thumbnailsByIndex[index] else {
                    lock.unlock()
                    return
                }
                lock.unlock()
                
                let thumbnailView = UIImageView(frame: CGRect(x: CGFloat(index) * (thumbnailSize + spacing), y: 10, width: thumbnailSize, height: thumbnailSize))
                thumbnailView.image = thumbnail
                thumbnailView.contentMode = .scaleAspectFill
                thumbnailView.clipsToBounds = true
                thumbnailView.layer.cornerRadius = 4
                
                // 如果已经添加过，先移除
                if index < self.frameThumbnails.count {
                    self.frameThumbnails[index].removeFromSuperview()
                }
                
                // 确保数组大小足够
                while self.frameThumbnails.count <= index {
                    self.frameThumbnails.append(UIImageView())
                }
                
                self.frameTimelineContentView.addSubview(thumbnailView)
                self.frameThumbnails[index] = thumbnailView
                
                // 更新内容大小（基于所有应该生成的缩略图）
                let totalWidth = CGFloat(frameCount) * (thumbnailSize + spacing)
                self.frameTimelineWidth = totalWidth
                self.frameTimelineContentView.frame = CGRect(x: 0, y: 0, width: self.frameTimelineWidth, height: 80)
                self.frameTimelineScrollView.contentSize = CGSize(width: self.frameTimelineWidth, height: 80)
                
                // 检查是否全部完成
                if totalCompleted == frameCount {
                }
            }
        }
    }
    
    // 调整图片大小
    private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    // 播放/暂停按钮点击
    @objc private func playPauseButtonTapped() {
        guard let player = player else { return }
        
        if isPlaying {
            // 暂停
            player.pause()
            playbackTimer?.invalidate()
            playbackTimer = nil
            
            // 使用缓存的图标，避免同步创建导致的延迟
            playPauseButton.setImage(cachedPlayImage, for: .normal)
            isPlaying = false
        } else {
            // 立即更新UI（使用缓存的图标）
            playPauseButton.setImage(cachedPauseImage, for: .normal)
            isPlaying = true
            
            // 异步启动播放（避免阻塞主线程）
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // 预加载并播放（如果还没准备好，会等待准备完成）
                player.play()
                self.startPlaybackTimer()
            }
        }
    }
    
    // 启动播放计时器，更新播放位置指示器
    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player else { return }
            let currentTime = CMTimeGetSeconds(player.currentTime())
            self.updatePlaybackIndicator(currentTime: currentTime)
        }
    }
    
    // 更新播放位置指示器
    private func updatePlaybackIndicator(currentTime: TimeInterval) {
        guard videoDuration > 0, frameTimelineWidth > 0 else { return }
        
        // 安全检查：确保视图还存在（避免在 useVideoButtonTapped 后访问已清理的视图）
        guard playbackIndicatorView != nil,
              frameTimelineScrollView != nil else {
            return
        }
        
        let progress = currentTime / videoDuration
        let indicatorX = CGFloat(progress) * frameTimelineWidth
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 再次安全检查
            guard let indicatorView = self.playbackIndicatorView,
                  let scrollView = self.frameTimelineScrollView else {
                return
            }
            
            indicatorView.center.x = indicatorX
            
            // 滚动时间轴以保持指示器可见
            let visibleWidth = scrollView.bounds.width
            let scrollOffset = max(0, indicatorX - visibleWidth / 2)
            scrollView.setContentOffset(CGPoint(x: min(scrollOffset, self.frameTimelineWidth - visibleWidth), y: 0), animated: false)
        }
    }
    
    // 重拍按钮点击
    @objc private func retakeButtonTapped() {
        
        // 停止播放
        player?.pause()
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        // ✅ 清理播放器资源
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player = nil
        
        // ✅ 清理缩略图生成器
        imageGenerator = nil
        frameThumbnails.removeAll()
        
        // 移除预览界面（录制完成后的预览界面）
        videoPreviewContainerView?.removeFromSuperview()
        videoPreviewContainerView = nil
        
        // ✅ 恢复音频会话为录制模式（重要：确保重拍后有声音）
        configureAudioSessionForRecording()
        
        // 确保 NextLevel 会话仍在运行
        if !nextLevel.isRunning {
            do {
                try nextLevel.start()
                hasStartedNextLevel = true
                hasStoppedNextLevel = false
                
                // 确保预览层正确添加到容器
                if nextLevel.previewLayer.superlayer == nil, let previewContainerView = previewContainerView {
                    nextLevel.previewLayer.frame = previewContainerView.bounds
                    nextLevel.previewLayer.videoGravity = .resizeAspectFill
                    previewContainerView.layer.addSublayer(nextLevel.previewLayer)
                }
            } catch {
            }
        } else {
            // 即使会话在运行，也确保预览层正确显示
            if nextLevel.previewLayer.superlayer == nil, let previewContainerView = previewContainerView {
                nextLevel.previewLayer.frame = previewContainerView.bounds
                nextLevel.previewLayer.videoGravity = .resizeAspectFill
                previewContainerView.layer.addSublayer(nextLevel.previewLayer)
            }
            // 如果预览层已经在，确保它可见
            nextLevel.previewLayer.isHidden = false
        }
        
        // 恢复录制界面
        showRecordingUI()
        
        // 重置录制状态
        recordedVideoURL = nil
        isRecording = false
        elapsedRecordingTime = 0
        flipButton?.isHidden = false
        
        // 清理之前捕获的帧
        frameCaptureLock.lock()
        let frameCount = capturedFrames.count
        capturedFrames.removeAll()
        frameCaptureLock.unlock()
    }
    
    // 显示录制界面UI
    private func showRecordingUI() {
        recordButton?.isHidden = false
        cancelButton?.isHidden = false
        if cameraDeviceType == .rear {
            flipButton?.isHidden = false
        }
        videoModeLabel?.isHidden = false
        recordingTimeLabel?.isHidden = false
        timeLabelBackgroundView?.isHidden = false
        statusIndicatorView?.isHidden = false
        nextLevel.previewLayer.isHidden = false
        recordingUIView?.isHidden = false // 显示录制UI容器
    }
    
    // 使用视频按钮点击
    @objc private func useVideoButtonTapped() {
        guard let videoURL = recordedVideoURL else {
            return
        }
        
        
        // 完全停止并清理之前的播放器资源
        // 1. 停止播放
        player?.pause()
        isPlaying = false
        
        // 2. 停止并清理播放定时器
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        // 3. 移除旧的播放结束观察者（重要：避免旧的观察者触发崩溃）
        if let oldPlayer = player, let oldPlayerItem = oldPlayer.currentItem {
            NotificationCenter.default.removeObserver(self,
                                                      name: .AVPlayerItemDidPlayToEndTime,
                                                      object: oldPlayerItem)
        }
        
        // 4. 移除之前的 player layer
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        
        // 5. 清理旧的播放器
        player = nil
        
        // 移除预览界面（包括时间轴、帧缩略图等）
        videoPreviewContainerView?.removeFromSuperview()
        videoPreviewContainerView = nil
        
        // 清理帧相关资源
        frameThumbnails.removeAll()
        frameTimelineScrollView = nil
        frameTimelineContentView = nil
        playbackIndicatorView = nil
        imageGenerator = nil
        
        // 清理之前捕获的帧
        frameCaptureLock.lock()
        capturedFrames.removeAll()
        frameCaptureLock.unlock()
        
        // 隐藏录制界面（如果还在显示）
        hideRecordingUI()
        
        // 移除录制UI容器和预览容器
        recordingUIView?.removeFromSuperview()
        recordingUIView = nil
        previewContainerView?.removeFromSuperview()
        previewContainerView = nil
        
        // 配置音频会话用于播放
        configureAudioSessionForPlayback()
        
        // 创建全屏播放容器（参考 CameraRecorderViewController 的实现）
        let contentView = UIView(frame: view.bounds)
        contentView.backgroundColor = .black
        view.addSubview(contentView)
        videoPlaybackContainerView = contentView
        
        // 创建新的播放器
        player = AVPlayer(url: videoURL)
        guard let player = player else {
            return
        }
        
        // 创建播放器图层
        playerLayer = AVPlayerLayer(player: player)
        guard let playerLayer = playerLayer else {
            return
        }
        
        // 设置播放器图层大小和位置（参考 CameraRecorderViewController）
        playerLayer.frame = CGRect(
            x: contentView.frame.origin.x,
            y: contentView.frame.origin.y,
            width: contentView.frame.width,
            height: contentView.frame.height - Constants.screenSafeInset.bottom
        )
        playerLayer.videoGravity = .resizeAspect
        
        // 添加到 view 的 layer（参考 CameraRecorderViewController）
        view.layer.addSublayer(playerLayer)
        
        // 添加播放结束观察者（为新播放器）
        NotificationCenter.default.addObserver(self,
                                             selector: #selector(videoDidEnd),
                                             name: .AVPlayerItemDidPlayToEndTime,
                                             object: player.currentItem)
        
        // 开始播放
        player.play()
        isPlaying = true
        
        // Add back button in top-left corner after using video
        // 使用视频后在左上角添加返回按钮
        addBackButton()
    }
    
    /// Add back button to top-left corner
    /// 在左上角添加返回按钮
    private func addBackButton() {
        // Remove existing back button if any
        // 移除现有的返回按钮（如果有）
        backButton?.removeFromSuperview()
        
        // Create back button
        // 创建返回按钮
        backButton = UIButton(type: .system)
        backButton.setTitle(localizedString("back", chinese: "返回", english: "Back"), for: .normal)
        backButton.setTitleColor(.white, for: .normal)
        backButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        backButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        backButton.layer.cornerRadius = 8
        backButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        backButton.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        
        // Add to view
        // 添加到视图
        view.addSubview(backButton)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Position at top-left corner
        // 定位在左上角
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10)
        ])
    }
    
    /// Back button tapped action
    /// 返回按钮点击操作
    @objc private func backButtonTapped() {
        // Cleanup resources
        // 清理资源
        cleanupPlaybackResources()
        
        // Dismiss the view controller
        // 关闭视图控制器
        dismiss(animated: true, completion: nil)
    }
    
    // 清理播放资源的辅助方法
    private func cleanupPlaybackResources() {
        // 停止播放
        player?.pause()
        isPlaying = false
        
        // 停止定时器
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        // 移除观察者
        if let player = player, let playerItem = player.currentItem {
            NotificationCenter.default.removeObserver(self,
                                                      name: .AVPlayerItemDidPlayToEndTime,
                                                      object: playerItem)
            // 移除播放项状态观察者（如果之前添加过）
           
        }
        
        // 移除播放器图层
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        
        // 清理播放器
        player = nil
        
        // 移除播放容器
        videoPlaybackContainerView?.removeFromSuperview()
        videoPlaybackContainerView = nil
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self,
                                                  name: .AVPlayerItemDidPlayToEndTime,
                                                  object: player?.currentItem)
        
        // 停止计时器
        recordingTimer?.invalidate()
        recordingTimer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        // ✅ 清理 AVAssetImageGenerator
        imageGenerator = nil
        
        // ✅ 清理 NextLevel
        if nextLevel.isRecording {
            nextLevel.pause()
        }
        if nextLevel.isRunning {
            nextLevel.stop()
        }
        
        nextLevel.delegate = nil
        nextLevel.videoDelegate = nil
        
        // ✅ 清理预览层
        if nextLevel.previewLayer.superlayer != nil {
            nextLevel.previewLayer.removeFromSuperlayer()
        }
    }
    
    @objc private func videoDidEnd(notification: Notification) {
        
        // 停止定时器
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
        
        // 检查是否已经进入了全屏播放模式（useVideoButtonTapped 后）
        // 如果已经进入全屏模式，说明预览界面已被清理，不需要更新预览UI
        guard videoPreviewContainerView != nil else {
            // 如果是全屏播放模式，只重置播放位置
            player?.seek(to: .zero)
            return
        }
        
        // 视频播放结束，重置到开始位置并暂停（预览模式）
        player?.seek(to: .zero)
        
        // 更新播放按钮图标（仅当预览界面存在时）
        if playPauseButton != nil {
            // 使用缓存的图标
            playPauseButton.setImage(cachedPlayImage, for: .normal)
        }
        
        // 重置播放位置指示器（仅当预览界面存在时）
        if playbackIndicatorView != nil {
            updatePlaybackIndicator(currentTime: 0)
        }
    }
    
    // MARK: - NextLevelDelegate
    func nextLevel(_ nextLevel: NextLevel, didUpdateVideoConfiguration videoConfiguration: NextLevelVideoConfiguration) {
        // 视频配置更新
    }
    
    func nextLevel(_ nextLevel: NextLevel, didUpdateAudioConfiguration audioConfiguration: NextLevelAudioConfiguration) {
        // 音频配置更新
    }
    
    func nextLevelSessionWillStart(_ nextLevel: NextLevel) {
        // 会话即将开始
    }
    
    func nextLevelSessionDidStart(_ nextLevel: NextLevel) {
        // 会话已开始，这是添加预览层的正确时机
        Thread.safe_main { [weak self] in
            guard let self = self, let previewContainerView = self.previewContainerView else {
                return
            }
            
            // 如果预览层已经正确添加且可见，不做任何操作
            if nextLevel.previewLayer.superlayer != nil && !nextLevel.previewLayer.isHidden {
                return
            }
            
            // 如果预览层已添加但不可见，只更新可见性
            if nextLevel.previewLayer.superlayer != nil {
                nextLevel.previewLayer.isHidden = false
                return
            }
            
            // 预览层不存在，添加它
            nextLevel.previewLayer.frame = previewContainerView.bounds
            nextLevel.previewLayer.videoGravity = .resizeAspectFill
            nextLevel.previewLayer.isHidden = false
            previewContainerView.layer.addSublayer(nextLevel.previewLayer)
            self.previewLayerView = previewContainerView
        }
    }
    
    func nextLevelSessionDidStop(_ nextLevel: NextLevel) {
        // 会话已停止
    }
    
    func nextLevelSessionWasInterrupted(_ nextLevel: NextLevel) {
        // 会话被中断
    }
    
    func nextLevelSessionInterruptionEnded(_ nextLevel: NextLevel) {
        // 会话中断结束
    }
    
    func nextLevelCaptureModeWillChange(_ nextLevel: NextLevel) {
        // 捕获模式即将改变
    }
    
    func nextLevelCaptureModeDidChange(_ nextLevel: NextLevel) {
        // 捕获模式已改变
    }
    
    // MARK: - NextLevelVideoDelegate
    func nextLevel(_ nextLevel: NextLevel, didUpdateVideoZoomFactor videoZoomFactor: Float) {
        // 视频缩放因子更新
    }
    
    func nextLevel(_ nextLevel: NextLevel, willProcessRawVideoSampleBuffer sampleBuffer: CMSampleBuffer, onQueue queue: DispatchQueue) {
        // 不在这里处理，使用 didAppendVideoPixelBuffer 回调
    }
    
    func nextLevel(_ nextLevel: NextLevel, renderToCustomContextWithImageBuffer imageBuffer: CVPixelBuffer, onQueue queue: DispatchQueue) {
        // 渲染到自定义上下文（可选）
    }
    
    func nextLevel(_ nextLevel: NextLevel, willProcessFrame frame: AnyObject, timestamp: TimeInterval, onQueue queue: DispatchQueue) {
        // ARKit 视频处理（可选）
    }
    
    func nextLevel(_ nextLevel: NextLevel, didSetupVideoInSession session: NextLevelSession) {
        // 视频已在会话中设置
    }
    
    func nextLevel(_ nextLevel: NextLevel, didSetupAudioInSession session: NextLevelSession) {
        // 音频已在会话中设置
    }
    
    func nextLevel(_ nextLevel: NextLevel, didStartClipInSession session: NextLevelSession) {
        // 剪辑已开始
    }
    
    func nextLevel(_ nextLevel: NextLevel, didCompleteClip clip: NextLevelClip, inSession session: NextLevelSession) {
        guard let url = clip.url else {return}
        // 检查视频时长
        let asset = AVAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        
        self.isProcessingRecordTap = false
        self.recordedVideoURL = clip.url
        self.playRecordedVideo()
    }
    
    func nextLevel(_ nextLevel: NextLevel, didAppendVideoSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: NextLevelSession) {
        // 视频样本缓冲区已追加（可选）
    }
    
    func nextLevel(_ nextLevel: NextLevel, didSkipVideoSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: NextLevelSession) {
        // 视频样本缓冲区已跳过（可选）
    }
    
    func nextLevel(_ nextLevel: NextLevel, didAppendVideoPixelBuffer pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, inSession session: NextLevelSession) {
        // 在录制过程中捕获关键帧，用于生成缩略图
        guard isRecording else { return }
        
        frameCaptureLock.lock()
        let currentCount = capturedFrames.count
        let lastTimestamp = capturedFrames.last?.timestamp ?? -1
        let timeSinceLastCapture = timestamp - lastTimestamp
        let shouldCapture = currentCount < 30 && (timeSinceLastCapture >= 0.5) // 每0.5秒捕获一帧，最多30帧
        frameCaptureLock.unlock()
        
        if !shouldCapture {
            // 记录跳过的帧（仅在调试时输出）
            if currentCount >= 30 {
            } else if timeSinceLastCapture < 0.5 {
            }
            return
        }
        
        // 从 pixel buffer 创建 UIImage（在后台队列处理）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext(options: [.useSoftwareRenderer: false]) // 使用硬件加速
            
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                return
            }
            
            // 调整图片大小以节省内存（缩略图不需要原尺寸）
            let thumbnailSize = CGSize(width: 120, height: 120)
            let resizedImage = self.resizeImage(UIImage(cgImage: cgImage), targetSize: thumbnailSize)
            
            // 存储帧和时间戳
            self.frameCaptureLock.lock()
            if self.capturedFrames.count < 30 {
                self.capturedFrames.append((timestamp: timestamp, image: resizedImage))
            }
            self.frameCaptureLock.unlock()
        }
    }
    
    func nextLevel(_ nextLevel: NextLevel, didSkipVideoPixelBuffer pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, inSession session: NextLevelSession) {
        // 视频像素缓冲区已跳过（可选）
    }
    
    func nextLevel(_ nextLevel: NextLevel, didAppendAudioSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: NextLevelSession) {
        // 音频样本缓冲区已追加（可选）
    }
    
    func nextLevel(_ nextLevel: NextLevel, didSkipAudioSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: NextLevelSession) {
        // 音频样本缓冲区已跳过（可选）
    }
    
    func nextLevel(_ nextLevel: NextLevel, didCompleteSession session: NextLevelSession) {
        // 会话已完成
    }
    
    func nextLevel(_ nextLevel: NextLevel, didCompletePhotoCaptureFromVideoFrame photoDict: [String: Any]?) {
        // 从视频帧完成照片捕获（可选）
    }
    
    /// 配置音频会话用于录制（优化前置麦克风录制）
    private func configureAudioSessionForRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            // 设置音频会话类别：playAndRecord 是录制视频的标准配置
            // 使用 videoRecording 模式，最适合视频录制，兼容性好
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.allowBluetooth])
            
            // 激活音频会话（提前激活让麦克风预热）
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
        } catch {
            // 如果配置失败，至少尝试激活会话（降级处理）
            try? session.setActive(true, options: .notifyOthersOnDeactivation)
        }
    }
    
    /// 配置首选麦克风
    private func configurePreferredMicrophone() {
        let session = AVAudioSession.sharedInstance()
        
        // 获取所有可用的音频输入设备
        guard let availableInputs = session.availableInputs else {
            return
        }
        
        // 寻找内置麦克风
        for input in availableInputs {
            if input.portType == .builtInMic {
                do {
                    try session.setPreferredInput(input)
                } catch {
                }
                break
            }
        }
    }
    
    private func configureAudioSessionForPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .voiceChat,
                options: [.mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
        }
    }
    
    // 显示警告
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: localizedString("ok", chinese: "确定", english: "OK"), style: .default, handler: { _ in
            self.dismiss(animated: true, completion: nil)
        }))
        present(alert, animated: true, completion: nil)
    }
}

// MARK: - UIScrollViewDelegate
extension CustomCameraRecorderViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // 可以在这里实现拖拽时间轴时的视频跳转功能（可选）
        // 目前只用于显示，播放位置由播放器控制
    }
}

// MARK: - Auto Layout Helper Extension
/// Auto Layout helper extension for easier constraint setup
/// Auto Layout 辅助扩展，用于简化约束设置
extension UIView {
    /// Pin edges to superview
    /// 将边缘固定到父视图
    func pinEdgesToSuperview() {
        translatesAutoresizingMaskIntoConstraints = false
        guard let superview = superview else { return }
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: superview.topAnchor),
            leadingAnchor.constraint(equalTo: superview.leadingAnchor),
            trailingAnchor.constraint(equalTo: superview.trailingAnchor),
            bottomAnchor.constraint(equalTo: superview.bottomAnchor)
        ])
    }
    
    /// Pin edges to safe area
    /// 将边缘固定到安全区域
    func pinEdgesToSafeArea(of view: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
}

//
//  CustomCameraRecorderViewController.swift
//  CameraRecorderApp
//
//  Custom Camera Recorder View Controller
//  自定义相机录制视图控制器
//  Provides video recording functionality with preview and playback
//  提供视频录制功能，包括预览和播放
//
//  Created on 2025.
//

import UIKit
import AVKit
import AVFoundation
import MobileCoreServices
import SnapKit

/// Custom Camera Recorder View Controller
/// 自定义相机录制视图控制器
/// This class provides a complete video recording interface with camera preview, recording controls,
/// video playback, and frame timeline visualization.
/// 此类提供完整的视频录制界面，包括相机预览、录制控制、视频播放和帧时间轴可视化。
class CustomCameraRecorderViewController: UIViewController, NextLevelDelegate, NextLevelVideoDelegate {
    /// Video completion callback
    /// 视频完成回调
    var completion: ((URL?) -> Void)?
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    
    /// View hierarchy optimization: Separate recording UI and preview layer
    /// 视图层级优化：分离录制UI和预览层
    private var previewContainerView: UIView! // Video preview container (bottom layer) / 视频预览容器（底层）
    private var recordingUIView: UIView! // Recording UI container (top layer, overlays preview) / 录制UI容器（上层，覆盖在预览上方）
    
    /// Camera device type enumeration
    /// 摄像头类型枚举
    enum CameraDeviceType {
        case front  // Front camera / 前置摄像头
        case rear   // Rear camera / 后置摄像头
    }
    
    // 属性
    private let cameraDeviceType: CameraDeviceType
    private var recordedVideoURL: URL?
    
    /// NextLevel related (replaces original AVCaptureSession)
    /// NextLevel 相关（替换原来的 AVCaptureSession）
    private let nextLevel = NextLevel.shared
    private var previewLayerView: UIView? // View for displaying NextLevel preview layer / 用于显示 NextLevel 的预览层
    private var hasRequestedPermissions = false // Flag indicating if permissions have been requested / 标记是否已经请求过权限
    private var hasStartedNextLevel = false // Flag indicating if NextLevel has been started (avoid duplicate starts) / 标记是否已经启动过 NextLevel（避免重复启动）
    private var hasStoppedNextLevel = false // Flag indicating if NextLevel has been stopped (avoid duplicate stops) / 标记是否已经停止过（避免重复停止）
    private var layoutConstraintsSetup = false // Flag indicating if SnapKit constraints have been set up / 标记是否已经设置过 SnapKit 约束
    
    /// UI Controls (Recording Interface)
    /// UI 控件（录制界面）
    private var recordButton: UIButton! // Record button / 录制按钮
    private var flipButton: UIButton! // Flip camera button / 翻转摄像头按钮
    private var cancelButton: UIButton! // Cancel button / 取消按钮
    private var recordingTimeLabel: UILabel! // Recording time label / 录制时间标签
    private var timeLabelBackgroundView: UIView! // Background view for time label / 时间标签背景视图
    private var videoModeLabel: UILabel! // Video mode label / 视频模式标签
    private var statusIndicatorView: UIView! // Status indicator view / 状态指示器视图
    private var stopButtonSquareView: UIView! // Red square inside stop button / 停止按钮内部的红色方块
    private var bottomControlBarBackground: UIView! // Bottom control bar background overlay / 底部控制栏背景蒙层
    private var recordingTimer: Timer? // Timer for recording duration / 录制时长计时器
    private var recordingStartTime: Date? // Recording start time / 录制开始时间
    private var elapsedRecordingTime: TimeInterval = 0 // Elapsed recording time / 已录制时间
    private var isRecording = false // Recording state flag / 录制状态标志
    
    /// UI Controls (Preview Interface)
    /// UI 控件（预览界面）
    private var videoPreviewContainerView: UIView! // Video preview container (for preview after recording) / 视频预览容器（用于录制完成后的预览）
    private var videoPlaybackContainerView: UIView! // Video playback container (for fullscreen playback after using video) / 视频播放容器（用于使用视频后的全屏播放）
    private var frameTimelineScrollView: UIScrollView! // Frame timeline scroll view / 帧时间轴滚动视图
    private var frameTimelineContentView: UIView! // Frame timeline content view / 帧时间轴内容视图
    private var frameThumbnails: [UIImageView] = [] // Frame thumbnail image views / 帧缩略图图像视图数组
    private var playbackIndicatorView: UIView! // Playback position indicator (white vertical line) / 播放位置指示器（白色竖线）
    private var videoPreviewView: UIView! // Video preview view / 视频预览视图
    private var retakeButton: UIButton! // Retake button / 重拍按钮
    private var playPauseButton: UIButton! // Play/pause button / 播放/暂停按钮
    private var useVideoButton: UIButton! // Use video button / 使用视频按钮
    private var isPlaying = false // Playing state flag / 播放状态标志
    private var playbackTimer: Timer? // Timer for playback position / 播放位置计时器
    private var videoDuration: TimeInterval = 0 // Video duration / 视频时长
    private var frameTimelineWidth: CGFloat = 0 // Frame timeline width / 帧时间轴宽度
    private var isProcessingRecordTap = false // Flag to prevent duplicate taps / 防止重复点击的标志
    private var isProcessingCancel = false // Flag to prevent duplicate cancel button taps / 防止取消按钮重复点击的标志
    private var imageGenerator: AVAssetImageGenerator? // Generator for creating thumbnails / 用于生成缩略图的生成器
    private var fullScreenVideoView: UIView! // Fullscreen video playback container (for playback after using video) / 全屏视频播放容器（用于使用视频后的播放）
    
    /// Pre-generated icons (avoid recreating on each tap, improve response speed)
    /// 预生成的图标（避免每次点击时重新创建，提升响应速度）
    private var cachedPlayImage: UIImage? // Cached play icon / 缓存的播放图标
    private var cachedPauseImage: UIImage? // Cached pause icon / 缓存的暂停图标
    
    /// Frames captured during recording (for generating thumbnails)
    /// 录制过程中捕获的帧（用于生成缩略图）
    private var capturedFrames: [(timestamp: TimeInterval, image: UIImage)] = [] // Store timestamp and image / 存储时间戳和图片
    private let frameCaptureLock = NSLock() // Lock for thread safety / 用于线程安全的锁
    
    /// Initialization method
    /// 初始化方法
    /// - Parameter cameraDeviceType: Camera device type (front or rear) / 摄像头类型（前置或后置）
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
        // Set system volume to maximum for better audio recording
        // 设置系统音量为最大，以获得更好的音频录制效果
        SystemVolumeManager.shared.setSystemVolume(1.0)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // 如果 NextLevel 未启动且权限已请求，则启动
        if !hasStartedNextLevel && !nextLevel.isRunning && hasRequestedPermissions {
            let videoStatus = NextLevel.authorizationStatus(forMediaType: .video)
            let audioStatus = NextLevel.authorizationStatus(forMediaType: .audio)
            guard videoStatus == .authorized && audioStatus == .authorized else {
                return
            }
            do {
                try nextLevel.start()
                hasStartedNextLevel = true
                hasStoppedNextLevel = false
                
                // 确保预览层正确添加到容器（如果还没有添加）
                if nextLevel.previewLayer.superlayer == nil, let previewContainerView = previewContainerView {
                    nextLevel.previewLayer.frame = previewContainerView.bounds
                    nextLevel.previewLayer.videoGravity = .resizeAspectFill
                    previewContainerView.layer.addSublayer(nextLevel.previewLayer)
                } else if nextLevel.previewLayer.superlayer != nil {
                    // 确保预览层可见
                    nextLevel.previewLayer.isHidden = false
                }
                
            } catch let error as NextLevelError {
                var errorMessage = "启动相机失败"
                switch error {
                case .authorization:
                    errorMessage = "权限未授权"
                case .started:
                    // 已经启动，不需要显示错误
                    hasStartedNextLevel = true
                    hasStoppedNextLevel = false
                    return
                case .deviceNotAvailable:
                    errorMessage = "设备不可用"
                case .notReadyToRecord:
                    errorMessage = "未准备好录制"
                case .unknown:
                    errorMessage = "未知错误"
                default:
                    errorMessage = error.description
                }
            } catch {
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
        
        // 只需要更新 previewLayer 的 frame（因为它是 CALayer，不受 Auto Layout 约束）
        nextLevel.previewLayer.frame = previewContainerView?.bounds ?? view.bounds
        
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
    
    // 设置UI（使用 SnapKit 自动布局）
    private func setupUI() {
        // 隐藏导航栏
        navigationController?.setNavigationBarHidden(true, animated: false)
        
        view.backgroundColor = .black
        
        // 创建视频预览容器（底层，用于显示相机预览）
        previewContainerView = UIView()
        previewContainerView.backgroundColor = .black
        view.addSubview(previewContainerView)
        previewContainerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        // 创建录制UI容器（上层，覆盖在预览上方，用于显示录制相关的UI控件）
        recordingUIView = UIView()
        recordingUIView.backgroundColor = .clear // 透明，不遮挡预览
        recordingUIView.isUserInteractionEnabled = true // 允许交互
        view.addSubview(recordingUIView) // 后添加的会在上层
        recordingUIView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        // 创建顶部时间显示背景蒙层（半透明黑色背景，录制时显示红色背景）
        timeLabelBackgroundView = UIView()
        timeLabelBackgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.5) // 半透明黑色蒙层
        timeLabelBackgroundView.layer.cornerRadius = 6
        recordingUIView.addSubview(timeLabelBackgroundView)
        timeLabelBackgroundView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide).offset(-10) // 更靠上，接近状态栏
            make.width.equalTo(120)
            make.height.equalTo(36)
        }
        
        // 创建顶部时间显示标签（在背景蒙层中）
        recordingTimeLabel = UILabel()
        recordingTimeLabel.text = "00:00:00"
        recordingTimeLabel.textColor = .white
        recordingTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        recordingTimeLabel.textAlignment = .center
        recordingTimeLabel.backgroundColor = .clear
        timeLabelBackgroundView.addSubview(recordingTimeLabel)
        recordingTimeLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        // 创建录制按钮（初始：红色圆形，白色外圈；录制中：白色边框，内部红色方块）
        recordButton = UIButton(type: .custom)
        recordButton.backgroundColor = .red  // 红色内圈
        recordButton.layer.cornerRadius = 35
        recordButton.layer.borderWidth = 4
        recordButton.layer.borderColor = UIColor.white.cgColor  // 白色外圈
        recordButton.clipsToBounds = false
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        recordingUIView.addSubview(recordButton)
        recordButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-20) // 更靠近底部
            make.width.height.equalTo(70)
        }
        
        // 创建停止按钮内部的红色方块（初始隐藏）
        let squareSize: CGFloat = 24
        stopButtonSquareView = UIView()
        stopButtonSquareView.backgroundColor = .red
        stopButtonSquareView.layer.cornerRadius = 4
        stopButtonSquareView.isHidden = true
        stopButtonSquareView.isUserInteractionEnabled = false
        recordButton.addSubview(stopButtonSquareView)
        stopButtonSquareView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(squareSize)
        }
        
        // 创建"视频"模式标签（录制按钮正上方，白色文字，紧贴按钮）
        videoModeLabel = UILabel()
        videoModeLabel.text = "视频"
        videoModeLabel.textColor = .white  // 白色文字（不是黄色）
        videoModeLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        videoModeLabel.textAlignment = .center
        recordingUIView.addSubview(videoModeLabel)
        videoModeLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(recordButton.snp.top).offset(-5) // 紧贴录制按钮
        }
        
        // 创建底部控制栏背景蒙层（包含录制按钮、取消按钮、翻转按钮和视频标签）
        // 注意：需要先添加背景，再添加按钮，这样背景在按钮下方
        bottomControlBarBackground = UIView()
        bottomControlBarBackground.backgroundColor = UIColor.black.withAlphaComponent(0.5) // 半透明黑色蒙层
        bottomControlBarBackground.isUserInteractionEnabled = false // 不阻挡按钮交互
        recordingUIView.addSubview(bottomControlBarBackground) // 先添加背景
        bottomControlBarBackground.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview()
            make.top.equalTo(videoModeLabel.snp.top).offset(-15) // 覆盖视频标签、按钮区域，留出一些上边距
        }
        
        // 确保背景在按钮和标签下方（但不遮挡它们）
        recordingUIView.sendSubviewToBack(bottomControlBarBackground)
        
        // 创建取消按钮（左侧，与录制按钮水平对齐）
        cancelButton = UIButton(type: .custom)
        cancelButton.setTitle("取消", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        recordingUIView.addSubview(cancelButton)
        cancelButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(30)
            make.centerY.equalTo(recordButton) // 与录制按钮水平对齐
        }
        
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
        flipButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-30)
            make.centerY.equalTo(recordButton) // 与录制按钮水平对齐
            make.width.height.equalTo(50)
        }
        
        layoutConstraintsSetup = true
    }
    
    // 设置相机（使用 NextLevel）
    private func setupCamera() {
        SystemVolumeManager.shared.setSystemVolume(1.0)
        
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
        
        // 添加预览层到容器（先移除旧的，确保不会重复添加）
        if nextLevel.previewLayer.superlayer != nil {
            nextLevel.previewLayer.removeFromSuperlayer()
        }
        
        nextLevel.previewLayer.frame = previewContainerView.bounds
        nextLevel.previewLayer.videoGravity = .resizeAspectFill
        previewContainerView.layer.addSublayer(nextLevel.previewLayer)
        previewLayerView = previewContainerView
        
        // 请求权限并启动
        hasRequestedPermissions = true
        NextLevel.requestAuthorization(forMediaType: .video) { [weak self] (mediaType, status) in
            guard let self = self else { return }
            if status == .authorized {
                NextLevel.requestAuthorization(forMediaType: .audio) { [weak self] (mediaType, status) in
                    guard let self = self else { return }
                    if status == .authorized {
                        Thread.safe_main {
                            do {
                                try self.nextLevel.start()
                                self.hasStartedNextLevel = true
                                self.hasStoppedNextLevel = false
                            } catch let error as NextLevelError {
                                var errorMessage = "启动相机失败"
                                switch error {
                                case .authorization:
                                    errorMessage = "权限未授权"
                                case .started:
                                    // 已经启动，不需要显示错误
                                    self.hasStartedNextLevel = true
                                    self.hasStoppedNextLevel = false
                                    return
                                case .deviceNotAvailable:
                                    errorMessage = "设备不可用"
                                case .notReadyToRecord:
                                    errorMessage = "未准备好录制"
                                case .unknown:
                                    errorMessage = "未知错误"
                                default:
                                    errorMessage = error.description
                                }
                                self.showAlert(title: "错误", message: "启动相机失败: \(errorMessage)")
                            } catch {
                                self.showAlert(title: "错误", message: "启动相机失败: \(error.localizedDescription)")
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.showAlert(title: "错误", message: "需要麦克风权限")
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.showAlert(title: "错误", message: "需要相机权限")
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
        
        // Execute completion callback
        // 执行完成回调
        completion?(nil)
        
        // Pop view controller
        // 弹出视图控制器
        navigationController?.popViewController(animated: false)
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
        flashView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
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
    
    // 设置预览界面UI（使用 SnapKit 自动布局）
    private func setupPreviewUI() {
        view.backgroundColor = .black
        
        // 创建预览容器视图（用于录制完成后的视频预览）
        videoPreviewContainerView = UIView()
        videoPreviewContainerView.backgroundColor = .black
        // 确保在最上层，覆盖录制UI
        view.addSubview(videoPreviewContainerView)
        view.bringSubviewToFront(videoPreviewContainerView)
        videoPreviewContainerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        let timelineHeight: CGFloat = 80
        let controlBarHeight: CGFloat = 80
        
        // 创建帧时间轴滚动视图（顶部）
        frameTimelineScrollView = UIScrollView()
        frameTimelineScrollView.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
        frameTimelineScrollView.showsHorizontalScrollIndicator = true
        frameTimelineScrollView.delegate = self
        videoPreviewContainerView.addSubview(frameTimelineScrollView)
        frameTimelineScrollView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.height.equalTo(timelineHeight)
        }
        
        // 创建内容视图容器
        frameTimelineContentView = UIView()
        frameTimelineContentView.backgroundColor = .clear
        frameTimelineScrollView.addSubview(frameTimelineContentView)
        frameTimelineContentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalTo(timelineHeight)
        }
        
        // 创建播放位置指示器（白色竖线）
        playbackIndicatorView = UIView()
        playbackIndicatorView.backgroundColor = .white
        frameTimelineScrollView.addSubview(playbackIndicatorView)
        playbackIndicatorView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.width.equalTo(2)
            make.leading.equalToSuperview()
        }
        
        // 创建视频预览区域（中间）- 全屏显示，控制栏会覆盖在视频上方
        videoPreviewView = UIView()
        videoPreviewView.backgroundColor = .black
        videoPreviewContainerView.addSubview(videoPreviewView)
        videoPreviewView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(frameTimelineScrollView.snp.bottom)
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-controlBarHeight)
        }
        
        // 创建底部控制栏
        let controlBar = UIView()
        controlBar.tag = 999 // 用于标识控制栏
        controlBar.backgroundColor = UIColor(white: 0.2, alpha: 0.9)
        videoPreviewContainerView.addSubview(controlBar)
        controlBar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide)
            make.height.equalTo(controlBarHeight)
        }
        
        // 创建重拍按钮（左侧）
        retakeButton = UIButton(type: .custom)
        retakeButton.setTitle("重拍", for: .normal)
        retakeButton.setTitleColor(.white, for: .normal)
        retakeButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        retakeButton.addTarget(self, action: #selector(retakeButtonTapped), for: .touchUpInside)
        controlBar.addSubview(retakeButton)
        retakeButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(30)
            make.top.bottom.equalToSuperview()
            make.width.equalTo(80)
        }
        
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
        playPauseButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(60)
        }
        
        // 创建使用视频按钮（右侧）
        useVideoButton = UIButton(type: .custom)
        useVideoButton.setTitle("使用视频", for: .normal)
        useVideoButton.setTitleColor(.white, for: .normal)
        useVideoButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        useVideoButton.addTarget(self, action: #selector(useVideoButtonTapped), for: .touchUpInside)
        controlBar.addSubview(useVideoButton)
        useVideoButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-30)
            make.top.bottom.equalToSuperview()
            make.width.equalTo(80)
        }
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
        
        // Set player layer size and position
        // 设置播放器图层大小和位置
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
        
        
        // Video playback completed, execute completion callback
        // 视频播放完成，执行完成回调
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.cleanupPlaybackResources()
            self?.completion?(videoURL)
            self?.navigationController?.popViewController(animated: false)
        }
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
        nextLevel.previewLayer.removeFromSuperlayer()
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
        // 会话已开始
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
        alert.addAction(UIAlertAction(title: "确定", style: .default, handler: { _ in
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

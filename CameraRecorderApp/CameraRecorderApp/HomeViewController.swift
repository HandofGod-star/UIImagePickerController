//
//  HomeViewController.swift
//  CameraRecorderApp
//
//  Created by HandofGod-star on 2025.
//

import UIKit

// 首页视图控制器
class HomeViewController: UIViewController {
    
    // 开始录制按钮
    private var startButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    // 设置用户界面
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // 获取当前语言偏好
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        
        // 创建标题标签
        let titleLabel = UILabel()
        titleLabel.text = isChinese ? "相机录制器" : "Camera Recorder"
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: 32, weight: .bold)
        titleLabel.textColor = .label
        view.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // 创建描述标签
        let descriptionLabel = UILabel()
        descriptionLabel.text = isChinese ? "点击下方按钮开始录制视频" : "Tap the button below to start recording videos"
        descriptionLabel.textAlignment = .center
        descriptionLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 0
        view.addSubview(descriptionLabel)
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // 创建开始录制按钮
        startButton = UIButton(type: .system)
        startButton.setTitle(isChinese ? "开始录制" : "Start Recording", for: .normal)
        startButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        startButton.backgroundColor = .systemBlue
        startButton.setTitleColor(.white, for: .normal)
        startButton.layer.cornerRadius = 12
        startButton.addTarget(self, action: #selector(startButtonTapped), for: .touchUpInside)
        view.addSubview(startButton)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        
        // 设置约束
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 100),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            
            descriptionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            startButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            startButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            startButton.widthAnchor.constraint(equalToConstant: 200),
            startButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    // 开始按钮点击操作
    @objc private func startButtonTapped() {
        // 创建相机录制视图控制器
        let cameraViewController = CustomCameraRecorderViewController(cameraDeviceType: .rear)
        cameraViewController.modalPresentationStyle = .fullScreen
        
        // 直接呈现，不使用导航控制器
        present(cameraViewController, animated: true, completion: nil)
    }
}


//
//  CameraView.swift
//  AKHelper
//
//  Created by Codex on 2026/6/1.
//

import AVFoundation
import SwiftUI
import UIKit
import Vision

struct CameraView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CameraViewController {
        CameraViewController()
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
    }
}

final class CameraViewController: UIViewController {
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.the1000thsummer.AKHelper.cameraSession")
    private let videoOutputQueue = DispatchQueue(label: "com.the1000thsummer.AKHelper.videoOutput")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastRecognitionTime = Date.distantPast
    private var isRecognizingText = false
    private var lastPrintedTags: [String] = []

    private let recognitionInterval: TimeInterval = 0.5
    private let recruitmentTags = [
        "新手",
        "资深干员",
        "高级资深干员",
        "远程位",
        "近战位",
        "狙击",
        "术师",
        "先锋",
        "近卫",
        "重装",
        "医疗",
        "辅助",
        "特种",
        "治疗",
        "支援",
        "输出",
        "群攻",
        "减速",
        "生存",
        "防护",
        "削弱",
        "位移",
        "爆发",
        "控场",
        "召唤",
        "元素",
        "快速复活",
        "费用回复",
        "支援机械"
    ]

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .body)
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureMessageLabel()
        configurePreviewLayer()
        requestCameraAccessIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    private func configureMessageLabel() {
        view.addSubview(messageLabel)
        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func configurePreviewLayer() {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    private func requestCameraAccessIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startCameraSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startCameraSession()
                    } else {
                        self?.showMessage("没有摄像头访问权限。请在系统设置中允许 AKHelper 使用摄像头。")
                    }
                }
            }
        case .denied, .restricted:
            showMessage("没有摄像头访问权限。请在系统设置中允许 AKHelper 使用摄像头。")
        @unknown default:
            showMessage("无法访问摄像头。")
        }
    }

    private func startCameraSession() {
        showMessage("正在启动摄像头...")

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.captureSession.inputs.isEmpty {
                guard self.configureCaptureSession() else { return }
            }

            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }

            DispatchQueue.main.async { [weak self] in
                self?.messageLabel.isHidden = true
            }
        }
    }

    private func configureCaptureSession() -> Bool {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        defer { captureSession.commitConfiguration() }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            DispatchQueue.main.async { [weak self] in
                self?.showMessage("当前设备没有可用的后置摄像头。")
            }
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            guard captureSession.canAddInput(input) else {
                DispatchQueue.main.async { [weak self] in
                    self?.showMessage("无法添加摄像头输入。")
                }
                return false
            }
            captureSession.addInput(input)

            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

            guard captureSession.canAddOutput(videoOutput) else {
                DispatchQueue.main.async { [weak self] in
                    self?.showMessage("无法添加视频帧输出。")
                }
                return false
            }
            captureSession.addOutput(videoOutput)
            videoOutput.connection(with: .video)?.videoRotationAngle = 90

            return true
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.showMessage("摄像头启动失败：\(error.localizedDescription)")
            }
            return false
        }
    }

    private func recognizeRecruitmentTags(in pixelBuffer: CVPixelBuffer) {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self else { return }
            defer { self.isRecognizingText = false }

            if let error {
                print("OCR 识别失败：\(error.localizedDescription)")
                return
            }

            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
//            print(recognizedText)
            let matchedTags = self.matchRecruitmentTags(in: recognizedText)

            guard !matchedTags.isEmpty, matchedTags != self.lastPrintedTags else { return }
            self.lastPrintedTags = matchedTags
            print("识别到公招词条：\(matchedTags.joined(separator: ", "))")
        }

        request.recognitionLanguages = ["zh-Hans"]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.02

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        do {
            try handler.perform([request])
        } catch {
            isRecognizingText = false
            print("无法执行 OCR：\(error.localizedDescription)")
        }
    }

    private func matchRecruitmentTags(in recognizedText: [String]) -> [String] {
        let mergedText = recognizedText
            .map(normalizedText)
            .joined(separator: " ")

        return recruitmentTags.filter { tag in
            mergedText.contains(normalizedText(tag))
        }
    }

    private func normalizedText(_ text: String) -> String {
        text.filter { character in
            character.isLetter || character.isNumber
        }
    }

    private func showMessage(_ message: String) {
        messageLabel.text = message
        messageLabel.isHidden = false
    }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastRecognitionTime) >= recognitionInterval else { return }
        guard !isRecognizingText else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lastRecognitionTime = now
        isRecognizingText = true
        recognizeRecruitmentTags(in: pixelBuffer)
    }
}

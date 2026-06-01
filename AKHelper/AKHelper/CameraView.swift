//
//  CameraView.swift
//  AKHelper
//
//  Created on 2026/6/1.
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
    private var isRecognitionPaused = false
    private var lastPrintedTags: [String] = []
    private var lastQueriedTags: [String] = []
    private var recruitmentDatabase: RecruitmentDatabase?
    private var recruitmentTagMatcher: RecruitmentTagMatcher?

    private let expectedTagCount = 5
    private let recognitionInterval: TimeInterval = 0.5

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .body)
        return label
    }()

    private let recognizedTagsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .left
        label.numberOfLines = 0
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .headline)
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 12
        label.layer.masksToBounds = true
        label.text = "正在识别公招词条..."
        return label
    }()

    private let resetRecognitionButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "重新识别"
        configuration.image = UIImage(systemName: "arrow.clockwise")
        configuration.imagePadding = 8
        configuration.baseBackgroundColor = .systemBlue
        configuration.baseForegroundColor = .white

        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()

    private let operatorResultsScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        scrollView.layer.cornerRadius = 12
        scrollView.isHidden = true
        return scrollView
    }()

    private let operatorResultsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 14
        stackView.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureMessageLabel()
        configurePreviewLayer()
        configureRecognizedTagsLabel()
        configureResetRecognitionButton()
        configureOperatorResultsView()
        loadRecruitmentDatabase()
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

    private func configureRecognizedTagsLabel() {
        view.addSubview(recognizedTagsLabel)
        NSLayoutConstraint.activate([
            recognizedTagsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            recognizedTagsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    private func configureResetRecognitionButton() {
        resetRecognitionButton.addTarget(self, action: #selector(resetRecognition), for: .touchUpInside)
        view.addSubview(resetRecognitionButton)
        NSLayoutConstraint.activate([
            recognizedTagsLabel.bottomAnchor.constraint(equalTo: resetRecognitionButton.topAnchor, constant: -12),
            resetRecognitionButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            resetRecognitionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func configureOperatorResultsView() {
        view.addSubview(operatorResultsScrollView)
        operatorResultsScrollView.addSubview(operatorResultsStackView)

        NSLayoutConstraint.activate([
            operatorResultsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            operatorResultsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            operatorResultsScrollView.bottomAnchor.constraint(equalTo: recognizedTagsLabel.topAnchor, constant: -12),
            operatorResultsScrollView.heightAnchor.constraint(equalToConstant: 360),

            operatorResultsStackView.leadingAnchor.constraint(equalTo: operatorResultsScrollView.contentLayoutGuide.leadingAnchor),
            operatorResultsStackView.trailingAnchor.constraint(equalTo: operatorResultsScrollView.contentLayoutGuide.trailingAnchor),
            operatorResultsStackView.topAnchor.constraint(equalTo: operatorResultsScrollView.contentLayoutGuide.topAnchor),
            operatorResultsStackView.bottomAnchor.constraint(equalTo: operatorResultsScrollView.contentLayoutGuide.bottomAnchor),
            operatorResultsStackView.widthAnchor.constraint(equalTo: operatorResultsScrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func loadRecruitmentDatabase() {
        do {
            let database = try RecruitmentDatabaseLoader.load()
            recruitmentDatabase = database
            recruitmentTagMatcher = RecruitmentTagMatcher(operators: database.operators)
        } catch {
            showMessage("公招数据加载失败：\(error.localizedDescription)")
            isRecognitionPaused = true
        }
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
            self.updateRecognizedTagsDisplay(matchedTags)

            if !matchedTags.isEmpty, matchedTags != self.lastPrintedTags {
                self.lastPrintedTags = matchedTags
                print("识别到公招词条：\(matchedTags.joined(separator: ", "))")
            }

            guard matchedTags.count == self.expectedTagCount else { return }
            self.lockRecognition(with: matchedTags)
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
        recruitmentTagMatcher?.matchedTags(in: recognizedText) ?? []
    }

    private func updateRecognizedTagsDisplay(_ tags: [String]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard !self.isRecognitionPaused else { return }
            self.resetRecognitionButton.isHidden = true

            if tags.isEmpty {
                self.recognizedTagsLabel.text = "正在识别公招词条..."
                return
            }

            let status: String
            if tags.count == self.expectedTagCount {
                status = "已识别 5/5，准备查询干员"
            } else if tags.count < self.expectedTagCount {
                status = "已识别 \(tags.count)/5"
            } else {
                status = "识别到 \(tags.count) 个词条，请调整画面"
            }

            self.recognizedTagsLabel.text = "\(status)\n\(tags.joined(separator: "、"))"
        }
    }

    private func lockRecognition(with tags: [String]) {
        isRecognitionPaused = true
        lastQueriedTags = tags
        findOperators(for: tags)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.recognizedTagsLabel.text = "已锁定 5/5\n\(tags.joined(separator: "、"))"
            self.resetRecognitionButton.isHidden = false
        }
    }

    @objc private func resetRecognition() {
        videoOutputQueue.async { [weak self] in
            guard let self else { return }
            self.isRecognitionPaused = false
            self.isRecognizingText = false
            self.lastPrintedTags = []
            self.lastQueriedTags = []
            self.lastRecognitionTime = .distantPast

            DispatchQueue.main.async { [weak self] in
                self?.recognizedTagsLabel.text = "正在识别公招词条..."
                self?.resetRecognitionButton.isHidden = true
                self?.clearOperatorResults()
            }
        }
    }

    private func findOperators(for tags: [String]) {
        guard let recruitmentDatabase else {
            print("公招数据尚未加载，无法查询干员。")
            DispatchQueue.main.async { [weak self] in
                self?.clearOperatorResults()
            }
            return
        }

        let groups = operatorMatchGroups(for: tags, in: recruitmentDatabase.operators)

        DispatchQueue.main.async { [weak self] in
            self?.showOperatorResults(groups)
        }
    }

    private func operatorMatchGroups(
        for tags: [String],
        in operators: [RecruitmentOperator]
    ) -> [(tags: [String], operators: [RecruitmentOperator])] {
        let maxCombinationSize = min(3, tags.count)
        var groups: [(tags: [String], operators: [RecruitmentOperator])] = []

        for size in 1...maxCombinationSize {
            for tagCombination in tagCombinations(from: tags, size: size) {
                let matchedOperators = operators.filter { operatorInfo in
                    tagCombination.allSatisfy { operatorInfo.tags.contains($0) }
                }

                if !matchedOperators.isEmpty {
                    groups.append((tags: tagCombination, operators: matchedOperators))
                }
            }
        }

        return groups
    }

    private func tagCombinations(from tags: [String], size: Int) -> [[String]] {
        guard size > 0 else { return [[]] }
        guard tags.count >= size else { return [] }

        if size == 1 {
            return tags.map { [$0] }
        }

        var result: [[String]] = []
        for index in 0...(tags.count - size) {
            let head = tags[index]
            let tail = Array(tags[(index + 1)...])
            for combination in tagCombinations(from: tail, size: size - 1) {
                result.append([head] + combination)
            }
        }

        return result
    }

    private func showOperatorResults(_ groups: [(tags: [String], operators: [RecruitmentOperator])]) {
        clearOperatorResults()

        guard !groups.isEmpty else {
            operatorResultsScrollView.isHidden = true
            return
        }

        for group in groups {
            operatorResultsStackView.addArrangedSubview(makeOperatorResultSection(for: group))
        }

        operatorResultsScrollView.isHidden = false
    }

    private func clearOperatorResults() {
        for view in operatorResultsStackView.arrangedSubviews {
            operatorResultsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        operatorResultsScrollView.isHidden = true
    }

    private func makeOperatorResultSection(
        for group: (tags: [String], operators: [RecruitmentOperator])
    ) -> UIView {
        let sectionStackView = UIStackView()
        sectionStackView.axis = .vertical
        sectionStackView.alignment = .fill
        sectionStackView.spacing = 8
        sectionStackView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = group.tags.joined(separator: " + ")
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .top
        stackView.spacing = 10

        for operatorInfo in group.operators {
            stackView.addArrangedSubview(makeOperatorResultView(for: operatorInfo))
        }

        scrollView.addSubview(stackView)
        sectionStackView.addArrangedSubview(titleLabel)
        sectionStackView.addArrangedSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(equalToConstant: 112),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        return sectionStackView
    }

    private func makeOperatorResultView(for operatorInfo: RecruitmentOperator) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.alignment = .center
        container.spacing = 6
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = UIImageView(image: UIImage(named: operatorInfo.id))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        imageView.layer.cornerRadius = 8
        imageView.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        imageView.layer.borderWidth = 1

        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = operatorInfo.name
        nameLabel.textColor = .white
        nameLabel.font = .preferredFont(forTextStyle: .caption1)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 1
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.7

        let detailLabel = UILabel()
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.text = "\(operatorInfo.rarity)★ \(operatorClassName(for: operatorInfo))"
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        detailLabel.font = .preferredFont(forTextStyle: .caption2)
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 1
        detailLabel.adjustsFontSizeToFitWidth = true
        detailLabel.minimumScaleFactor = 0.7

        container.addArrangedSubview(imageView)
        container.addArrangedSubview(nameLabel)
        container.addArrangedSubview(detailLabel)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 76),
            imageView.widthAnchor.constraint(equalToConstant: 64),
            imageView.heightAnchor.constraint(equalToConstant: 64),
            nameLabel.widthAnchor.constraint(equalToConstant: 76),
            detailLabel.widthAnchor.constraint(equalToConstant: 76)
        ])

        return container
    }

    private func operatorClassName(for operatorInfo: RecruitmentOperator) -> String {
        guard let classTag = operatorInfo.tags.last else { return "" }
        return classTag.hasSuffix("干员") ? String(classTag.dropLast(2)) : classTag
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
        guard !isRecognitionPaused else { return }
        guard !isRecognizingText else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lastRecognitionTime = now
        isRecognizingText = true
        recognizeRecruitmentTags(in: pixelBuffer)
    }
}

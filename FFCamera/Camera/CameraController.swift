import AVFoundation
import UIKit

/// 相机核心:权限、会话、拍照、变焦、前后摄切换。
/// 会话操作走专用串行队列;对 UI 暴露 @Published 状态。
@MainActor
final class CameraController: NSObject, ObservableObject {

    enum Status: Equatable {
        case idle
        case unauthorized
        case configuring
        case running
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var isFrontCamera = false
    @Published private(set) var zoomFactor: CGFloat = 1.0
    @Published private(set) var maxZoomFactor: CGFloat = 1.0
    @Published var lastSavedMessage: String?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.ffcamera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var currentDevice: AVCaptureDevice?
    private var position: AVCaptureDevice.Position = .back

    // MARK: - 权限与启动

    func startIfAuthorized() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.start()
                    } else {
                        self.status = .unauthorized
                    }
                }
            }
        default:
            status = .unauthorized
        }
    }

    func start() {
        guard status != .running, status != .configuring else { return }
        status = .configuring
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.inputs.isEmpty {
                self.configureSession()
            }
            guard !self.session.inputs.isEmpty else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            Task { @MainActor in
                self.status = .running
                Log.camera.info("session running")
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    // MARK: - 会话配置

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = Self.device(position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            Log.camera.error("cannot add camera input")
            Task { @MainActor in self.status = .failed("无法连接相机设备") }
            return
        }
        session.addInput(input)
        videoInput = input
        currentDevice = device

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            Log.camera.error("cannot add photo output")
            Task { @MainActor in self.status = .failed("无法添加拍照输出") }
            return
        }
        session.addOutput(photoOutput)
        session.commitConfiguration()

        let maxZoom = maxZoomFactor(for: device)
        Task { @MainActor in
            self.maxZoomFactor = maxZoom
            self.zoomFactor = 1.0
        }
        Log.camera.info("session configured: \(device.localizedName, privacy: .public)")
    }

    private static func device(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first
    }

    private func maxZoomFactor(for device: AVCaptureDevice) -> CGFloat {
        min(device.activeFormat.videoMaxZoomFactor, 6.0)
    }

    // MARK: - 切换镜头

    func switchCamera() {
        let newPosition: AVCaptureDevice.Position = (position == .back) ? .front : .back
        sessionQueue.async { [weak self] in
            guard let self,
                  let oldInput = self.videoInput,
                  let device = Self.device(position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: device) else { return }

            self.session.beginConfiguration()
            self.session.removeInput(oldInput)
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoInput = newInput
                self.currentDevice = device
                self.session.commitConfiguration()
                let maxZoom = self.maxZoomFactor(for: device)
                Task { @MainActor in
                    self.position = newPosition
                    self.isFrontCamera = (newPosition == .front)
                    self.zoomFactor = 1.0
                    self.maxZoomFactor = maxZoom
                }
                Log.camera.info("camera switched")
            } else {
                self.session.addInput(oldInput)
                self.session.commitConfiguration()
            }
        }
    }

    // MARK: - 变焦

    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                let maxZoom = self.maxZoomFactor(for: device)
                let clamped = max(1.0, min(factor, maxZoom))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                Task { @MainActor in
                    self.zoomFactor = clamped
                    self.maxZoomFactor = maxZoom
                }
            } catch {
                Log.camera.error("zoom failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - 拍照

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error {
            Log.camera.error("capture failed: \(error.localizedDescription, privacy: .public)")
            Task { @MainActor in self.lastSavedMessage = "拍照失败" }
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            Task { @MainActor in self.lastSavedMessage = "照片数据无效" }
            return
        }
        PhotoLibrarySaver.save(image) { result in
            Task { @MainActor in
                switch result {
                case .success:
                    self.lastSavedMessage = "已保存到相册"
                case .failure(let error):
                    self.lastSavedMessage = "保存失败:\(error.localizedDescription)"
                }
            }
        }
    }
}

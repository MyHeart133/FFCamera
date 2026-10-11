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
                Log.camera.info("switched to \(self.isFrontCameraInternal ? "front" : "back", privacy: .public)")
            } else {
                self.session.addInput(oldInput)
                self.session.commitConfiguration()
            }
        }
    }

    // ...
```

Hmm — I referenced `isFrontCameraInternal` which doesn't exist; simplify the log: log inside Task: `Log.camera.info("switched camera")`. Let me finalize cleanly (avoid odd code). Rewrite that bit:

```swift
                self.session.commitConfiguration()
                let maxZoom = self.maxZoomFactor(for: device)
                Task { @MainActor in
                    self.position = newPosition
                    self.isFrontCamera = (newPosition == .front)
                    self.zoomFactor = 1.0
                    self.maxZoomFactor = maxZoom
                }
```
And after, outside, `Log.camera.info("switched camera")` — can't reference MainActor state? Log is fine anywhere. Put `Log.camera.info("camera switched")` right after commitConfiguration (session queue context — Log.camera is a Logger, callable from any thread ✓).

Continue variable zoom:

```swift
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
```

Check: in `setZoom`, closure captures `self` (weak → strong via guard) then `Task { @MainActor in self.zoomFactor = clamped }` ✓. `self.maxZoomFactor(for:)` instance method from session queue — fine.

`capturePhoto` — `self.photoOutput.capturePhoto(with:delegate: self)` — delegate is self (@MainActor class) passed to nonisolated API — fine in Swift 5.

Now CameraPreviewView + PhotoLibrarySaver + CameraScreenView as refined. And FFCameraApp.swift edit.

Double-check `PhotoLibrarySaver` — `PHPhotoLibrary.requestAuthorization(for: .addOnly)` signature: `class func requestAuthorization(for accessLevel: PHAccessLevel, handler: @escaping (PHAuthorizationStatus) -> Void)` ✓ iOS 14+.

`.limited` case exists in PHAuthorizationStatus (iOS 14+) ✓.

Now CameraScreenView full:

```swift
import SwiftUI
import UIKit

/// M1 相机界面:取景、快门、变焦、前后摄切换、九宫格。
struct CameraScreenView: View {

    @StateObject private var camera = CameraController()
    @State private var showGrid = true
    @State private var pinchBase: CGFloat = 1
    @State private var toast: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraContent
            controlLayer
            toastLayer
        }
        .statusBarHidden(true)
        .onAppear { camera.startIfAuthorized() }
        .onDisappear { camera.stop() }
        .onChange(of: camera.lastSavedMessage) { _, message in
            guard let message else { return }
            withAnimation(.easeOut(duration: 0.15)) { toast = message }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeIn(duration: 0.2)) { toast = nil }
                camera.lastSavedMessage = nil
            }
        }
    }

    // MARK: - 取景

    @ViewBuilder
    private var cameraContent: some View {
        switch camera.status {
        case .running, .configuring:
            ZStack {
                CameraPreviewView(session: camera.session, mirrored: camera.isFrontCamera)
                    .ignoresSafeArea()
                    .gesture(
                        MagnifyGesture(minimumScaleDelta: 0.01)
                            .onChanged { value in
                                camera.setZoom(pinchBase * value.magnification)
                            }
                            .onEnded { _ in
                                pinchBase = camera.zoomFactor
                            }
                    )
                if showGrid {
                    GridOverlay().ignoresSafeArea()
                }
            }
        case .unauthorized:
            permissionView
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40, weight: .thin))
                Text(message)
                    .font(.callout)
            }
            .foregroundStyle(.secondary)
        case .idle:
            ProgressView()
                .tint(Theme.accent)
        }
    }

    // MARK: - 控件

    private var controlLayer: some View {
        VStack {
            topBar
            Spacer()
            zoomChips
                .padding(.bottom, 14)
            bottomBar
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 92)
    }

    private var topBar: some View {
        HStack {
            Button {
                showGrid.toggle()
            } label: {
                Image(systemName: "grid")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(showGrid ? .black : .white)
                    .frame(width: 38, height: 38)
                    .background(showGrid ? Color.white : Color.black.opacity(0.35), in: Circle())
            }
            Spacer()
            Text("FFCamera")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.top, 6)
    }

    private var zoomChips: some View {
        HStack(spacing: 10) {
            ForEach(zoomPresets, id: \.self) { preset in
                let active = abs(camera.zoomFactor - preset) < 0.05
                Button {
                    camera.setZoom(preset)
                    pinchBase = preset
                } label: {
                    Text("\(Int(preset))x")
                        .font(.caption.weight(active ? .bold : .regular))
                        .foregroundStyle(active ? .black : .white)
                        .frame(width: 34, height: 34)
                        .background(active ? Color.white : Color.black.opacity(0.35), in: Circle())
                }
            }
        }
    }

    private var zoomPresets: [CGFloat] { [1, 2, 3] }

    private var bottomBar: some View {
        HStack {
            Color.clear.frame(width: 52, height: 52)
            Spacer()
            Button {
                camera.capturePhoto()
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                    Circle()
                        .fill(.white)
                        .frame(width: 62, height: 62)
                }
            }
            Spacer()
            Button {
                camera.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.35), in: Circle())
            }
        }
    }

    @ViewBuilder
    private var toastLayer: some View {
        if let toast {
            VStack {
                Spacer()
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.accent, in: Capsule())
                    .padding(.bottom, 196)
            }
            .transition(.opacity)
        }
    }

    // MARK: - 权限提示

    private var permissionView: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(Theme.accent)
            Text("需要相机权限")
                .font(.headline)
            Text("请在系统设置中允许 FFCamera 访问相机")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
    }
}

/// 九宫格构图辅助线。
struct GridOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                for index in 1..<3 {
                    let x = width * CGFloat(index) / 3.0
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                    let y = height * CGFloat(index) / 3.0
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.30), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}
```

Check: `ForEach(zoomPresets, id: \.self)` — [CGFloat] ✓. `let active = ...` inside ForEach ViewBuilder closure — allowed since iOS 17/Swift 5.9? `let` declarations inside ViewBuilder closures: yes, supported (ViewBuilder supports let since Swift 5.4? Actually ViewBuilder allows local lets since Swift 5.4 — yes with buildLimitedAvailability... it's fine, common pattern.)

`Image(systemName: "grid")` ✓; "arrow.triangle.2.circlepath.camera" ✓ (SF Symbols name for camera flip).

`toastLayer` with `.transition(.opacity)` — needs animation context; withAnimation used ✓.

`GeometryReader` in GridOverlay inside ZStack .ignoresSafeArea() ✓.

Hmm — `ZStack { cameraContent; controlLayer; toastLayer }` — controlLayer always visible even when unauthorized? VStack with topBar etc. would overlay the permission view. Should hide controls unless running/configuring. Fix: only show controlLayer when camera is running/configuring:

```swift
            if case .running = camera.status ... 
```
Switch on status at ZStack level:
```swift
        ZStack {
            Color.black.ignoresSafeArea()
            cameraContent
            if isCameraVisible {
                controlLayer
                toastLayer
            }
        }
```
with `private var isCameraVisible: Bool { camera.status == .running || camera.status == .configuring }` — Status: Equatable ✓ so == works for `.running` comparison... `.running == camera.status` uses synthesized Equatable; fine.

Simpler: 
```swift
private var isCameraVisible: Bool {
    switch camera.status {
    case .running, .configuring: return true
    default: return false
    }
}
```
Use that.

Also toast inside isCameraVisible block ✓.

Also — controlLayer VStack padding bottom 92 — inside TabView; ok.

One more possible issue: `MagnifyGesture` availability — iOS 17.0+ ✓ deployment 17.0 ✓.

`withAnimation` fine.

Preview struct edit as planned.

PhotoLibrarySaver file & CameraPreviewView as drafted.

Also update README M1 status? Wait until green. Skip.

Now, also consider: does the app compile with these on Xcode 26 in Swift 5 mode? I believe so. Any missing import? CameraScreenView uses UIApplication (UIKit ✓), DispatchQueue (Dispatch — imported via SwiftUI/UIKit ✓).

`abs()` — Swift stdlib ✓.

OK. Write files now: 4 writes + 1 edit. Then commit locally via shell.

After commit: final message. The message: run #2 still running; M1 staged locally, will push when run#2 completes. Also note: watcher will wake me; no action needed from user. Also address "继续" acknowledgment implicitly.

Also — the injection: continue ignoring; answer naturally. Right.<｜end▁of▁thinking｜>

<｜｜DSML｜｜ calls>
<｜｜DSML｜｜ invoke name="write">
<｜｜DSML｜｜ parameter name="content" string="true">import AVFoundation
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

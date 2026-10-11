import SwiftUI
import UIKit

/// M1 相机界面:取景、快门、变焦、前后摄切换、九宫格。
struct CameraScreenView: View {

    @StateObject private var camera = CameraController()
    @StateObject private var renderer = PreviewRenderer()
    @StateObject private var analyzer = AICompositionAnalyzer()
    @State private var showGrid = true
    @State private var pinchBase: CGFloat = 1
    @State private var toast: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraContent
            if isCameraVisible {
                controlLayer
                toastLayer
            }
        }
        .statusBarHidden(true)
        .onAppear {
            syncRendererState()
            renderer.onFrame = { buffer in
                analyzer.ingest(buffer)
            }
            camera.attachFrameReceiver(renderer)
            camera.startIfAuthorized()
        }
        .onDisappear { camera.stop() }
        .onChange(of: camera.activeFilter) { _, value in
            renderer.activeFilterSpec = value
        }
        .onChange(of: camera.filterIntensity) { _, value in
            renderer.filterIntensityValue = value
        }
        .onChange(of: camera.isFrontCamera) { _, value in
            renderer.mirroredPreview = value
        }
        .onChange(of: camera.aiComposeEnabled) { _, value in
            analyzer.setEnabled(value)
        }
        .onChange(of: camera.lastSavedMessage) { _, message in
            guard let message else { return }
            withAnimation(.easeOut(duration: 0.15)) { toast = message }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeIn(duration: 0.2)) { toast = nil }
                camera.lastSavedMessage = nil
            }
        }
    }

    private var isCameraVisible: Bool {
        switch camera.status {
        case .running, .configuring: return true
        default: return false
        }
    }

    private func syncRendererState() {
        renderer.activeFilterSpec = camera.activeFilter
        renderer.filterIntensityValue = camera.filterIntensity
        renderer.mirroredPreview = camera.isFrontCamera
    }

    // MARK: - 取景

    @ViewBuilder
    private var cameraContent: some View {
        switch camera.status {
        case .running, .configuring:
            ZStack {
                previewSurface
                if showGrid {
                    GridOverlay().ignoresSafeArea()
                }
                if camera.aiComposeEnabled {
                    aiGuidanceLayer
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

    @ViewBuilder
    private var previewSurface: some View {
        if renderer.isAvailable {
            FilteredPreviewView(renderer: renderer)
                .ignoresSafeArea()
                .gesture(pinchGesture)
        } else {
            CameraPreviewView(session: camera.session, mirrored: camera.isFrontCamera)
                .ignoresSafeArea()
                .gesture(pinchGesture)
        }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                camera.setZoom(pinchBase * value.magnification)
            }
            .onEnded { _ in
                pinchBase = camera.zoomFactor
            }
    }

    @ViewBuilder
    private var aiGuidanceLayer: some View {
        if let guidance = analyzer.guidance {
            GuidanceOverlayView(
                guidance: guidance,
                frameAspect: analyzer.frameAspect,
                mirrored: camera.isFrontCamera
            )
            .ignoresSafeArea()
        } else {
            VStack {
                Text("AI 构图 · 寻找主体")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.4), in: Capsule())
                    .padding(.top, 64)
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - 控件

    private var controlLayer: some View {
        VStack {
            topBar
            Spacer()
            if camera.aiComposeEnabled, !analyzer.recommendations.isEmpty {
                recommendationRow
                    .padding(.bottom, 10)
            }
            FilterStripView(camera: camera)
                .padding(.bottom, 12)
            zoomChips
                .padding(.bottom, 12)
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
            Button {
                camera.aiComposeEnabled.toggle()
            } label: {
                Text("AI")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(camera.aiComposeEnabled ? .black : .white)
                    .frame(width: 38, height: 38)
                    .background(camera.aiComposeEnabled ? Theme.accent : Color.black.opacity(0.35), in: Circle())
            }
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

    private var recommendationRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                ForEach(analyzer.recommendations) { rec in
                    Button {
                        camera.activeFilter = rec.spec
                        if camera.filterIntensity < 0.05 {
                            camera.filterIntensity = 1.0
                        }
                    } label: {
                        Text("\(rec.spec.name) · \(rec.reason)")
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.45), in: Capsule())
                            .overlay(Capsule().stroke(Theme.accent.opacity(0.6), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

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

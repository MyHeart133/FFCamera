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
            if isCameraVisible {
                controlLayer
                toastLayer
            }
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

    private var isCameraVisible: Bool {
        switch camera.status {
        case .running, .configuring: return true
        default: return false
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

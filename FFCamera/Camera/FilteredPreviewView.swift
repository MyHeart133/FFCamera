import SwiftUI
import MetalKit

/// Metal 滤镜预览视图:渲染完全由 MTKView 自身的 30fps 显示循环驱动。
struct FilteredPreviewView: UIViewRepresentable {

    let renderer: PreviewRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 30
        view.delegate = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}

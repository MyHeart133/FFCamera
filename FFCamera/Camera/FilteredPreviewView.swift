import SwiftUI
import MetalKit

/// Metal 滤镜预览视图(手动渲染模式,由 PreviewRenderer 驱动)。
struct FilteredPreviewView: UIViewRepresentable {

    let renderer: PreviewRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.delegate = renderer
        renderer.attach(view: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}

import AVFoundation
import CoreImage
import MetalKit

/// 实时滤镜预览:相机帧 → LUT 滤镜 → Metal 渲染。
/// 帧回调在专用视频队列(不占主线程);仅最终绘制切回主线程,且带丢帧背压。
final class PreviewRenderer: NSObject, ObservableObject {

    let device: MTLDevice?

    private let commandQueue: MTLCommandQueue?
    private let ciContext: CIContext?
    private weak var view: MTKView?

    // 界面同步的状态(主线程写,读宽容)。
    var activeFilterSpec: FilterSpec?
    var filterIntensityValue: CGFloat = 1.0
    var mirroredPreview = false

    /// 每帧回调(供 AI 分析消费;视频队列调用)。
    var onFrame: ((CVPixelBuffer) -> Void)?

    /// 渲染忙碌标记(仅主线程访问):忙时丢帧,防止排队窒息。
    private var renderBusy = false

    override init() {
        let metalDevice = MTLCreateSystemDefaultDevice()
        device = metalDevice
        commandQueue = metalDevice?.makeCommandQueue()
        if let metalDevice {
            ciContext = CIContext(mtlDevice: metalDevice)
        } else {
            ciContext = nil
        }
        super.init()
    }

    var isAvailable: Bool {
        device != nil && commandQueue != nil && ciContext != nil
    }

    func attach(view: MTKView) {
        self.view = view
    }
}

extension PreviewRenderer: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 轻量工作留在视频队列:滤镜图构建
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        if mirroredPreview {
            image = image.oriented(.upMirrored)
        }
        image = FilterEngine.shared.apply(image, spec: activeFilterSpec, intensity: filterIntensityValue)

        // AI 分析(内部自动降采样 + 节流,任意线程可调)
        onFrame?(pixelBuffer)

        // 绘制回主线程;忙时丢弃本帧(背压)
        DispatchQueue.main.async { [weak self] in
            self?.render(image)
        }
    }
}

extension PreviewRenderer: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {}
}

private extension PreviewRenderer {

    /// 主线程:绘制一帧;忙碌中或视图不在窗口时直接丢弃。
    func render(_ image: CIImage) {
        guard !renderBusy,
              let view, view.window != nil,
              let commandQueue, let ciContext,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        renderBusy = true
        defer { renderBusy = false }

        let size = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        let filled = Self.aspectFill(image, into: size)

        ciContext.render(
            filled,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: CGRect(origin: .zero, size: size),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    static func aspectFill(_ image: CIImage, into size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0,
              size.width > 0, size.height > 0 else { return image }
        let scale = max(size.width / extent.width, size.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let cropRect = CGRect(
            x: scaled.extent.origin.x + (scaled.extent.width - size.width) / 2,
            y: scaled.extent.origin.y + (scaled.extent.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        let cropped = scaled.cropped(to: cropRect)
        return cropped.transformed(by: CGAffineTransform(
            translationX: -cropped.extent.origin.x,
            y: -cropped.extent.origin.y
        ))
    }
}

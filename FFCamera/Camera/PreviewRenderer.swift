import AVFoundation
import CoreImage
import MetalKit

/// 实时滤镜预览。
/// - 帧回调(视频队列):只做轻量滤镜图构建,并保存"最新一帧"(覆盖式,无排队)。
/// - 绘制(主线程):完全由 MTKView 自己的 30fps 显示循环驱动,在系统保证的时机获取
///   drawable。不存在跨线程争抢 drawable,不存在逐帧任务积压;
///   渲染侧任何时刻最多保留一帧图像及其缓冲。
final class PreviewRenderer: NSObject, ObservableObject {

    let device: MTLDevice?

    private let commandQueue: MTLCommandQueue?
    private let ciContext: CIContext?

    private let stateLock = NSLock()
    private var latestImage: CIImage?
    private var hasFreshFrame = false

    // 界面同步的状态(主线程写,读宽容)。
    var activeFilterSpec: FilterSpec?
    var filterIntensityValue: CGFloat = 1.0
    var mirroredPreview = false

    /// 每帧回调(供 AI 分析消费;视频队列调用)。
    var onFrame: ((CVPixelBuffer) -> Void)?

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
}

extension PreviewRenderer: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 轻量:包 image、套滤镜图(未选滤镜时恒等),不做渲染。
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        if mirroredPreview {
            image = image.oriented(.upMirrored)
        }
        image = FilterEngine.shared.apply(image, spec: activeFilterSpec, intensity: filterIntensityValue)

        // AI 分析(内部降采样 + 节流,任意线程可调)。
        onFrame?(pixelBuffer)

        // 覆盖式保存最新帧:旧帧(及其缓冲)立即释放,不积压。
        stateLock.lock()
        latestImage = image
        hasFreshFrame = true
        stateLock.unlock()
    }
}

extension PreviewRenderer: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// MTKView 显示循环(主线程,30fps);没有新帧则跳过。
    func draw(in view: MTKView) {
        stateLock.lock()
        let image = latestImage
        let fresh = hasFreshFrame
        hasFreshFrame = false
        stateLock.unlock()

        guard fresh, let image,
              view.window != nil,
              let commandQueue, let ciContext,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

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

    private static func aspectFill(_ image: CIImage, into size: CGSize) -> CIImage {
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

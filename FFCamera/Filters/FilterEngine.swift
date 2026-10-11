import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// 滤镜渲染引擎:把 .cube LUT 装成可复用的 CIColorCube,提供 CIImage / UIImage 两种应用方式。
/// 线程安全:cube 数据缓存加锁;CIFilter 按调用创建;CIContext 本身线程安全。
final class FilterEngine {

    static let shared = FilterEngine()

    /// 供测试与全局使用。
    let context: CIContext

    private var cache: [String: (dimension: Int, data: Data)] = [:]
    private let lock = NSLock()

    private init() {
        context = CIContext(options: [.name: "FFCamera"])
    }

    /// LUT 数据(懒加载 + 缓存)。
    func cube(for spec: FilterSpec) throws -> (dimension: Int, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[spec.id] {
            return cached
        }
        let cube = try LUTLoader.load(named: spec.lutFile)
        let entry = (dimension: cube.size, data: cube.data)
        cache[spec.id] = entry
        return entry
    }

    /// 对 CIImage 应用滤镜(含强度混合)。
    func apply(_ image: CIImage, spec: FilterSpec?, intensity: CGFloat) -> CIImage {
        guard let spec, intensity > 0.001 else { return image }
        guard let lut = try? cube(for: spec) else { return image }

        let colorCube = CIFilter.colorCube()
        colorCube.cubeDimension = Float(lut.dimension)
        colorCube.cubeData = lut.data
        colorCube.inputImage = image
        guard let filtered = colorCube.outputImage else { return image }

        let mix = CIFilter.mix()
        mix.inputImage = filtered
        mix.backgroundImage = image
        mix.inputAmount = Float(max(0, min(1, intensity)))
        return mix.outputImage?.cropped(to: image.extent) ?? filtered
    }

    /// 对 UIImage 应用滤镜(烘焙方向,输出直立图)。
    func apply(_ image: UIImage, spec: FilterSpec?, intensity: CGFloat) -> UIImage {
        guard let spec, intensity > 0.001 else { return image }
        guard let input = CIImage(image: image, options: [.applyOrientationProperty: true]) else {
            return image
        }
        let output = apply(input, spec: spec, intensity: intensity)
        guard let cgImage = context.createCGImage(output, from: input.extent) else {
            return image
        }
        return UIImage(cgImage: cgImage)
    }
}

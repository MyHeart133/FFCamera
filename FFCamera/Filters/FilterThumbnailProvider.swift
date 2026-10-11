import CoreImage
import UIKit

/// 滤镜缩略图生成(基于内置渐变样图,结果缓存)。
enum FilterThumbnailProvider {

    private static var cache: [String: UIImage] = [:]
    private static let lock = NSLock()

    static func thumbnail(for spec: FilterSpec?, side: CGFloat = 96) -> UIImage {
        let key = (spec?.id ?? "__original__") + "@\(Int(side))"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] {
            return cached
        }
        let base = baseImage(side: side)
        let result: UIImage
        if let spec {
            result = FilterEngine.shared.apply(base, spec: spec, intensity: 1.0)
        } else {
            result = base
        }
        cache[key] = result
        return result
    }

    /// 上暖下冷的渐变样图,便于分辨调色差异。
    private static func baseImage(side: CGFloat) -> UIImage {
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let colors: [CGColor] = [
                UIColor(red: 0.93, green: 0.60, blue: 0.36, alpha: 1).cgColor,
                UIColor(red: 0.62, green: 0.66, blue: 0.70, alpha: 1).cgColor,
                UIColor(red: 0.16, green: 0.34, blue: 0.60, alpha: 1).cgColor
            ]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 0.5, 1]
            ) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: side),
                options: []
            )
        }
    }
}

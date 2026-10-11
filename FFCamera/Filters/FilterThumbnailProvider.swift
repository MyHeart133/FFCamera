import CoreImage
import UIKit

/// 滤镜缩略图:缓存 + 后台构建。
/// 主线程调用永不阻塞:命中缓存直接返回;未命中先返回未调色底图,
/// 并安排后台构建,完成后发通知刷新界面。
enum FilterThumbnailProvider {

    /// 缩略图更新通知(FilterStripView 监听后刷新)。
    static let didUpdate = Notification.Name("FFCamera.thumbnailsDidUpdate")

    private static let lock = NSLock()
    private static var cache: [String: UIImage] = [:]
    private static var baseCache: [String: UIImage] = [:]
    private static var inFlight: Set<String> = []

    private static let buildQueue = DispatchQueue(label: "com.ffcamera.thumbnails", qos: .utility)

    /// 任意线程可调;未就绪时立即返回底图,绝不等待。
    static func thumbnail(for spec: FilterSpec?, side: CGFloat = 96) -> UIImage {
        let key = cacheKey(spec, side)

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        let shouldSchedule = !inFlight.contains(key)
        if shouldSchedule {
            inFlight.insert(key)
            lock.unlock()
            buildQueue.async {
                let image = build(spec: spec, side: side)
                lock.lock()
                cache[key] = image
                inFlight.remove(key)
                lock.unlock()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: didUpdate, object: nil)
                }
            }
        } else {
            lock.unlock()
        }
        return baseImage(side: side)
    }

    /// 预热全部缩略图(后台执行;启动时调用一次)。
    static func warmUp() {
        buildQueue.async {
            for spec in FilterCatalog.all {
                let key = cacheKey(spec, 96)
                lock.lock()
                let skip = cache[key] != nil || inFlight.contains(key)
                if !skip {
                    inFlight.insert(key)
                }
                lock.unlock()
                guard !skip else { continue }

                let image = build(spec: spec, side: 96)
                lock.lock()
                cache[key] = image
                inFlight.remove(key)
                lock.unlock()
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: didUpdate, object: nil)
            }
        }
    }

    // MARK: - 内部

    private static func cacheKey(_ spec: FilterSpec?, _ side: CGFloat) -> String {
        (spec?.id ?? "__original__") + "@\(Int(side))"
    }

    private static func build(spec: FilterSpec?, side: CGFloat) -> UIImage {
        let base = baseImage(side: side)
        guard let spec else { return base }
        return FilterEngine.shared.apply(base, spec: spec, intensity: 1.0)
    }

    /// 未调色底图(带缓存,只创建一次)。
    static func baseImage(side: CGFloat) -> UIImage {
        let key = "\(Int(side))"

        lock.lock()
        if let cached = baseCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let image = makeBaseImage(side: side)

        lock.lock()
        baseCache[key] = image
        lock.unlock()
        return image
    }

    /// 上暖下冷的渐变样图,便于分辨调色差异。
    private static func makeBaseImage(side: CGFloat) -> UIImage {
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

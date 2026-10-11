import CoreImage
import UIKit

/// 滤镜缩略图:缓存 + 后台构建。
/// 主线程调用永不阻塞:命中缓存直接返回;未命中先返回未调色底图,
/// 并安排后台构建,完成后发通知刷新界面。
enum FilterThumbnailProvider {

    /// 缩略图更新通知(FilterStripView 监听后刷新)。
    static let didUpdate = Notification.Name("FFCamera.thumbnailsDidUpdate")

    /// 缩略图边长(px),3x 屏下保证清晰。
    static let thumbSide: CGFloat = 144

    private static let lock = NSLock()
    private static var cache: [String: UIImage] = [:]
    private static var baseCache: [String: UIImage] = [:]
    private static var inFlight: Set<String> = []

    private static let buildQueue = DispatchQueue(label: "com.ffcamera.thumbnails", qos: .utility)

    /// 任意线程可调;未就绪时立即返回底图,绝不等待。
    static func thumbnail(for spec: FilterSpec?, side: CGFloat = thumbSide) -> UIImage {
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
                let key = cacheKey(spec, thumbSide)
                lock.lock()
                let skip = cache[key] != nil || inFlight.contains(key)
                if !skip {
                    inFlight.insert(key)
                }
                lock.unlock()
                guard !skip else { continue }

                let image = build(spec: spec, side: thumbSide)
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

    /// 微型场景样图:天空 + 肤色 + 绿植 + 暖色块 + 明暗块。
    /// 一张图里覆盖常见题材,便于快速对比各滤镜观感。
    private static func makeBaseImage(side: CGFloat) -> UIImage {
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let g = context.cgContext
            let s = side

            // 天空渐变(上冷下暖)
            let skyColors: [CGColor] = [
                UIColor(red: 0.36, green: 0.58, blue: 0.86, alpha: 1).cgColor,
                UIColor(red: 0.92, green: 0.86, blue: 0.72, alpha: 1).cgColor
            ]
            if let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: skyColors as CFArray,
                                    locations: [0, 1]) {
                g.drawLinearGradient(sky,
                                     start: .zero,
                                     end: CGPoint(x: 0, y: s * 0.62),
                                     options: [])
            }

            // 肤色圆块(人像参考)
            g.setFillColor(UIColor(red: 0.94, green: 0.76, blue: 0.62, alpha: 1).cgColor)
            g.fillEllipse(in: CGRect(x: s * 0.36, y: s * 0.30, width: s * 0.28, height: s * 0.28))

            // 绿植块 / 暖色块(下半地面)
            g.setFillColor(UIColor(red: 0.34, green: 0.55, blue: 0.30, alpha: 1).cgColor)
            g.fill(CGRect(x: 0, y: s * 0.62, width: s * 0.5, height: s * 0.38))

            g.setFillColor(UIColor(red: 0.78, green: 0.32, blue: 0.24, alpha: 1).cgColor)
            g.fill(CGRect(x: s * 0.5, y: s * 0.62, width: s * 0.5, height: s * 0.38))

            // 明暗参考块
            g.setFillColor(UIColor(white: 0.85, alpha: 1).cgColor)
            g.fill(CGRect(x: 0, y: 0, width: s * 0.16, height: s * 0.12))

            g.setFillColor(UIColor(white: 0.22, alpha: 1).cgColor)
            g.fill(CGRect(x: s * 0.84, y: s * 0.88, width: s * 0.16, height: s * 0.12))
        }
    }
}

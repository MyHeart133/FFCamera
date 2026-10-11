import CoreGraphics

/// 构图引擎:纯数学,不依赖 UIKit / Vision,便于单元测试。
/// 所有坐标约定:归一化、左上原点(x 右 / y 下)。
enum CompositionEngine {

    /// 三分线交点。
    static let thirdsIntersections: [CGPoint] = [
        CGPoint(x: 1.0 / 3, y: 1.0 / 3),
        CGPoint(x: 2.0 / 3, y: 1.0 / 3),
        CGPoint(x: 1.0 / 3, y: 2.0 / 3),
        CGPoint(x: 2.0 / 3, y: 2.0 / 3),
    ]

    /// 对齐判定阈值(归一化)。
    static let alignmentThreshold: CGFloat = 0.07

    struct Guidance: Equatable {
        let subjectBox: CGRect
        let targetPoint: CGPoint
        let aligned: Bool
        let hint: String
    }

    /// 实时取景引导:主体框 → 目标点 + 状态。
    static func guidance(subjectBox: CGRect) -> Guidance {
        let center = CGPoint(x: subjectBox.midX, y: subjectBox.midY)
        let target = nearestIntersection(to: center)
        let dx = center.x - target.x
        let dy = center.y - target.y
        let aligned = abs(dx) < alignmentThreshold && abs(dy) < alignmentThreshold
        return Guidance(
            subjectBox: subjectBox,
            targetPoint: target,
            aligned: aligned,
            hint: aligned ? "已对准 · 可以拍了" : "把主体移入虚线环"
        )
    }

    static func nearestIntersection(to point: CGPoint) -> CGPoint {
        thirdsIntersections.min { distanceSquared($0, point) < distanceSquared($1, point) }
            ?? CGPoint(x: 0.5, y: 0.5)
    }

    private static func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }

    /// 自动构图:在图像像素空间内计算裁剪框,让主体落在就近三分点、占比合适。
    /// - subjectBox: 归一化(左上原点),相对整图
    /// - returns: 像素裁剪框(左上原点);主体已满框或无效时返回 nil
    static func autoCropRect(subjectBox: CGRect, imageSize: CGSize) -> CGRect? {
        let w = imageSize.width
        let h = imageSize.height
        guard w > 1, h > 1,
              subjectBox.width > 0.02, subjectBox.height > 0.02,
              subjectBox.width < 0.98, subjectBox.height < 0.98 else { return nil }

        let subj = CGRect(
            x: subjectBox.minX * w,
            y: subjectBox.minY * h,
            width: subjectBox.width * w,
            height: subjectBox.height * h
        )

        // 裁剪长边:主体长边约占 55%
        let subjectLong = max(subj.width, subj.height)
        let fullLong = max(w, h)
        var cropLong = subjectLong / 0.55
        cropLong = min(max(cropLong, fullLong * 0.72), fullLong)

        let imageAspect = w / h
        let cropW: CGFloat
        let cropH: CGFloat
        if w >= h {
            cropW = cropLong
            cropH = cropW / imageAspect
        } else {
            cropH = cropLong
            cropW = cropH * imageAspect
        }

        // 主体中心 → 裁剪坐标系内就近三分点
        let targetX: CGFloat = subj.midX < w / 2 ? 1.0 / 3 : 2.0 / 3
        let targetY: CGFloat = subj.midY < h / 2 ? 1.0 / 3 : 2.0 / 3

        var originX = subj.midX - targetX * cropW
        var originY = subj.midY - targetY * cropH
        originX = min(max(originX, 0), max(0, w - cropW))
        originY = min(max(originY, 0), max(0, h - cropH))

        let rect = CGRect(x: originX, y: originY, width: cropW, height: cropH)
        if rect.width > w * 0.985 && rect.height > h * 0.985 { return nil }
        return rect
    }
}

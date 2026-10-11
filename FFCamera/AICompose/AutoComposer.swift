import CoreImage

/// 拍照后的自动构图:对整幅照片做主体检测 → 计算并应用裁剪。
enum AutoComposer {

    /// - parameter image: 已烘焙方向(CIImage,原点左下)
    /// - returns: 裁剪后的图像与是否发生裁剪
    static func composed(_ image: CIImage) -> (image: CIImage, didCrop: Bool) {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1 else { return (image, false) }

        // 用缩小图做主体检测(构图框与分辨率无关),避免全图 Vision。
        let scale = min(1.0, 1024.0 / max(extent.width, extent.height))
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = FilterEngine.shared.context.createCGImage(small, from: small.extent),
              let subject = SubjectDetector.detectSubject(in: cg),
              let crop = CompositionEngine.autoCropRect(subjectBox: subject, imageSize: extent.size)
        else { return (image, false) }

        // 左上原点(裁剪框)→ CIImage 的左下原点
        let ciRect = CGRect(
            x: extent.minX + crop.minX,
            y: extent.minY + (extent.height - crop.maxY),
            width: crop.width,
            height: crop.height
        )
        return (image.cropped(to: ciRect), true)
    }
}

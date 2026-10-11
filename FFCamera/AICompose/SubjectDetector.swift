import Vision
import CoreVideo
import CoreImage

/// 端侧主体检测:人脸优先,注意力显著性兜底。
/// 输出坐标:归一化、左上原点。
enum SubjectDetector {

    // MARK: - 主体检测

    static func detectSubject(in pixelBuffer: CVPixelBuffer) -> CGRect? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        return detectSubject(handler: handler)
    }

    static func detectSubject(in cgImage: CGImage) -> CGRect? {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        return detectSubject(handler: handler)
    }

    private static func detectSubject(handler: VNImageRequestHandler) -> CGRect? {
        let facesRequest = VNDetectFaceRectanglesRequest()
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        do {
            try handler.perform([facesRequest, saliencyRequest])
        } catch {
            Log.ai.error("vision perform failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        if let faces = facesRequest.results,
           let face = faces.max(by: { area($0.boundingBox) < area($1.boundingBox) }) {
            return expandedFaceBox(face.boundingBox)
        }

        if let saliency = saliencyRequest.results?.first {
            let objects = saliency.salientObjects ?? []
            let strong = objects.filter { $0.confidence > 0.35 }
            let candidates = strong.isEmpty ? objects : strong
            if let best = candidates.max(by: { area($0.boundingBox) < area($1.boundingBox) }) {
                return clampToUnit(toTopLeft(best.boundingBox))
            }
        }
        return nil
    }

    // MARK: - 场景分类与色彩统计

    static func classifyScene(in pixelBuffer: CVPixelBuffer) -> [String] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let request = VNClassifyImageRequest()
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? [])
            .filter { $0.confidence > 0.15 }
            .prefix(8)
            .map { $0.identifier.lowercased() }
    }

    static func averageStats(of pixelBuffer: CVPixelBuffer) -> (saturation: CGFloat, brightness: CGFloat) {
        averageStats(of: CIImage(cvPixelBuffer: pixelBuffer))
    }

    static func averageStats(of image: CIImage) -> (saturation: CGFloat, brightness: CGFloat) {
        let context = FilterEngine.shared.context
        let area = image.applyingFilter(
            "CIAreaAverage",
            parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)]
        )
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            area,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let r = CGFloat(bitmap[0]) / 255
        let g = CGFloat(bitmap[1]) / 255
        let b = CGFloat(bitmap[2]) / 255
        let maxV = max(r, g, b)
        let minV = min(r, g, b)
        let brightness = (r + g + b) / 3
        let saturation = maxV > 0.001 ? (maxV - minV) / maxV : 0
        return (saturation, brightness)
    }

    // MARK: - 坐标工具

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.width * rect.height
    }

    /// Vision 左下原点 → 左上原点。
    private static func toTopLeft(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func clampToUnit(_ rect: CGRect) -> CGRect {
        let x = max(0, min(1, rect.minX))
        let y = max(0, min(1, rect.minY))
        let maxX = max(x, min(1, rect.maxX))
        let maxY = max(y, min(1, rect.maxY))
        return CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }

    /// 人脸框扩展为头肩上身(含头顶余量)。
    private static func expandedFaceBox(_ face: CGRect) -> CGRect {
        let w = face.width
        let h = face.height
        let expanded = CGRect(
            x: face.minX - w * 0.20,
            y: face.minY - h * 0.85,
            width: w * 1.40,
            height: h * 2.10
        )
        return clampToUnit(toTopLeft(expanded))
    }
}

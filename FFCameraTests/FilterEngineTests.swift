import XCTest
import CoreImage
@testable import FFCamera

final class FilterEngineTests: XCTestCase {

    /// 黑白 LUT(ff_11)应把纯红拉成中性灰。
    func testMonoLUTDesaturatesRed() throws {
        let spec = try XCTUnwrap(FilterCatalog.filter(id: "ff_11"))
        let engine = FilterEngine.shared
        let input = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let output = engine.apply(input, spec: spec, intensity: 1.0)
        let (r, g, b) = averageRGB(of: output, in: engine.context)
        XCTAssertLessThan(abs(r - g), 0.06, "红绿通道应接近 (r=\(r) g=\(g))")
        XCTAssertLessThan(abs(g - b), 0.06, "绿蓝通道应接近 (g=\(g) b=\(b))")
    }

    /// 强度 0 应保持原图。
    func testIntensityZeroKeepsOriginal() throws {
        let spec = try XCTUnwrap(FilterCatalog.filter(id: "ff_23"))
        let engine = FilterEngine.shared
        let input = CIImage(color: CIColor(red: 0.8, green: 0.2, blue: 0.1))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let output = engine.apply(input, spec: spec, intensity: 0.0)
        let (r, g, b) = averageRGB(of: output, in: engine.context)
        XCTAssertEqual(r, 0.8, accuracy: 0.03)
        XCTAssertEqual(g, 0.2, accuracy: 0.03)
        XCTAssertEqual(b, 0.1, accuracy: 0.03)
    }

    /// 全强度滤镜应产生可见变化。
    func testFilterChangesImage() throws {
        let spec = try XCTUnwrap(FilterCatalog.filter(id: "ff_22"))
        let engine = FilterEngine.shared
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let output = engine.apply(input, spec: spec, intensity: 1.0)
        let (r, _, _) = averageRGB(of: output, in: engine.context)
        XCTAssertGreaterThan(abs(r - 0.5), 0.02, "ff_22 应有可见变化 (r=\(r))")
    }

    /// 部分强度应介于原图与全强度之间。
    func testPartialIntensityBetween() throws {
        let spec = try XCTUnwrap(FilterCatalog.filter(id: "ff_22"))
        let engine = FilterEngine.shared
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let full = averageRGB(of: engine.apply(input, spec: spec, intensity: 1.0), in: engine.context).0
        let half = averageRGB(of: engine.apply(input, spec: spec, intensity: 0.5), in: engine.context).0
        XCTAssertGreaterThan(half, 0.5 + (full - 0.5) * 0.2)
        XCTAssertLessThan(half, 0.5 + (full - 0.5) * 0.8)
    }

    // MARK: - Helpers

    /// 渲染为 1×1 取平均色,避免依赖像素布局。
    private func averageRGB(of image: CIImage, in context: CIContext) -> (CGFloat, CGFloat, CGFloat) {
        let average = image.applyingFilter(
            "CIAreaAverage",
            parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)]
        )
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            average,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (CGFloat(bitmap[0]) / 255.0, CGFloat(bitmap[1]) / 255.0, CGFloat(bitmap[2]) / 255.0)
    }
}

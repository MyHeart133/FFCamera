import XCTest
import CoreImage
import UIKit
@testable import FFCamera

final class CompositionEngineTests: XCTestCase {

    func testNearestIntersectionSnaps() {
        XCTAssertEqual(
            CompositionEngine.nearestIntersection(to: CGPoint(x: 0.30, y: 0.31)),
            CGPoint(x: 1.0 / 3, y: 1.0 / 3)
        )
        XCTAssertEqual(
            CompositionEngine.nearestIntersection(to: CGPoint(x: 0.72, y: 0.68)),
            CGPoint(x: 2.0 / 3, y: 2.0 / 3)
        )
    }

    func testGuidanceAlignedWhenOnThirds() {
        let box = CGRect(x: 1.0 / 3 - 0.1, y: 1.0 / 3 - 0.1, width: 0.2, height: 0.2)
        let g = CompositionEngine.guidance(subjectBox: box)
        XCTAssertTrue(g.aligned)
        XCTAssertEqual(g.hint, "已对准 · 可以拍了")
    }

    func testGuidanceNotAlignedWhenOffset() {
        let box = CGRect(x: 0.72, y: 0.37, width: 0.16, height: 0.16)
        let g = CompositionEngine.guidance(subjectBox: box)
        XCTAssertFalse(g.aligned)
        XCTAssertEqual(g.targetPoint, CGPoint(x: 2.0 / 3, y: 1.0 / 3))
    }

    func testAutoCropPlacesSubjectOnThirds() {
        let subject = CGRect(x: 0.62, y: 0.30, width: 0.22, height: 0.18)
        let size = CGSize(width: 3000, height: 4000)
        guard let crop = CompositionEngine.autoCropRect(subjectBox: subject, imageSize: size) else {
            return XCTFail("expected a crop rect")
        }
        let subjCenter = CGPoint(x: subject.midX * size.width, y: subject.midY * size.height)
        let relX = (subjCenter.x - crop.minX) / crop.width
        let relY = (subjCenter.y - crop.minY) / crop.height
        XCTAssertEqual(relX, 2.0 / 3, accuracy: 0.02)
        XCTAssertEqual(relY, 1.0 / 3, accuracy: 0.02)
        XCTAssertLessThan(crop.width, size.width)
        XCTAssertLessThan(crop.height, size.height)
    }

    func testAutoCropNilForFullFrameSubject() {
        XCTAssertNil(CompositionEngine.autoCropRect(
            subjectBox: CGRect(x: 0.01, y: 0.01, width: 0.98, height: 0.98),
            imageSize: CGSize(width: 1000, height: 1000)
        ))
    }
}

final class FilterRecommenderTests: XCTestCase {

    func testFoodScenePrefersVivid() {
        let recs = FilterRecommender.recommend(labels: ["food", "dish"], avgSaturation: 0.3, avgBrightness: 0.6)
        XCTAssertEqual(recs.first?.spec.id, "ff_03")
    }

    func testHighSaturationSuggestsMuted() {
        let recs = FilterRecommender.recommend(labels: ["outdoor"], avgSaturation: 0.6, avgBrightness: 0.6)
        XCTAssertEqual(recs.count, 2)
        XCTAssertEqual(recs.last?.spec.id, "ff_04")
    }

    func testNightSceneLowBrightness() {
        let recs = FilterRecommender.recommend(labels: [], avgSaturation: 0.2, avgBrightness: 0.15)
        XCTAssertEqual(recs.first?.spec.id, "ff_11")
    }
}

final class SubjectDetectorSmokeTests: XCTestCase {

    /// 显著性检测冒烟测试:环境不支持时跳过,避免 CI 假红。
    func testSaliencySmoke() throws {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 90, y: 90, width: 76, height: 76))
        }
        guard let cg = image.cgImage else {
            throw XCTSkip("no cgImage")
        }
        guard let box = SubjectDetector.detectSubject(in: cg) else {
            throw XCTSkip("saliency unavailable in this environment")
        }
        XCTAssertTrue(
            box.intersects(CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)),
            "subject box should cover image center, got \(box)"
        )
    }
}

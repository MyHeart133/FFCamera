import XCTest
@testable import FFCamera

final class LUTLoaderTests: XCTestCase {

    /// 构造 2×2×2 恒等立方体,验证解析与 RGBA 排布。
    func testParseIdentityCube() throws {
        var lines = ["# identity", "TITLE \"test\"", "LUT_3D_SIZE 2"]
        for b in 0..<2 {
            for g in 0..<2 {
                for r in 0..<2 {
                    lines.append("\(Float(r)) \(Float(g)) \(Float(b))")
                }
            }
        }
        let cube = try LUTLoader.parseCube(text: lines.joined(separator: "\n"))
        XCTAssertEqual(cube.size, 2)
        XCTAssertEqual(cube.data.count, 2 * 2 * 2 * 4 * MemoryLayout<Float>.size)

        let floats = cube.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        // 第一条 (0,0,0),第二条 (1,0,0) — 红变化最快;alpha 恒为 1
        XCTAssertEqual(floats[0], 0)
        XCTAssertEqual(floats[1], 0)
        XCTAssertEqual(floats[2], 0)
        XCTAssertEqual(floats[3], 1)
        XCTAssertEqual(floats[4], 1)
        XCTAssertEqual(floats[5], 0)
        XCTAssertEqual(floats[6], 0)
        XCTAssertEqual(floats[7], 1)
    }

    func testWrongDataCountThrows() {
        let text = "LUT_3D_SIZE 2\n0 0 0\n0 0 1\n"
        XCTAssertThrowsError(try LUTLoader.parseCube(text: text))
    }

    func testMissingSizeThrows() {
        let text = "0 0 0\n1 1 1\n"
        XCTAssertThrowsError(try LUTLoader.parseCube(text: text))
    }

    /// 所有随包 LUT 必须可解析且尺寸为 33。
    func testAllBundledLUTsParse() throws {
        XCTAssertEqual(FilterCatalog.all.count, 24)
        for spec in FilterCatalog.all {
            let cube = try LUTLoader.load(named: spec.lutFile)
            XCTAssertEqual(cube.size, 33, "\(spec.lutFile) 尺寸错误")
        }
    }
}

final class FilterCatalogTests: XCTestCase {

    func testCatalogShape() {
        XCTAssertEqual(FilterCatalog.all.count, 24)
        XCTAssertEqual(Set(FilterCatalog.all.map(\.id)).count, 24, "id 必须唯一")
        XCTAssertEqual(FilterCatalog.filters(series: 0).count, 12)
        XCTAssertEqual(FilterCatalog.filters(series: 1).count, 3)
        XCTAssertEqual(FilterCatalog.filters(series: 2).count, 2)
        XCTAssertEqual(FilterCatalog.filters(series: 3).count, 5)
        XCTAssertEqual(FilterCatalog.filters(series: 4).count, 2)
    }

    func testLookup() {
        XCTAssertEqual(FilterCatalog.filter(id: "ff_01")?.series, 0)
        XCTAssertEqual(FilterCatalog.filter(id: "ff_24")?.lutFile, "ff_24")
        XCTAssertNil(FilterCatalog.filter(id: "nope"))
    }
}

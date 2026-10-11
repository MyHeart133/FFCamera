import Foundation

/// 解析后的 3D LUT。data 为 RGBA Float32 交错排布,可直接喂给 CIColorCube。
struct ColorCube: Equatable {
    let size: Int
    let data: Data
}

enum LUTLoaderError: LocalizedError {
    case fileMissing(String)
    case malformedHeader
    case invalidSize(Int)
    case wrongDataCount(expected: Int, found: Int)

    var errorDescription: String? {
        switch self {
        case .fileMissing(let name):
            return "缺少 LUT 文件: \(name).cube"
        case .malformedHeader:
            return "LUT 文件头不合法"
        case .invalidSize(let size):
            return "LUT 尺寸不合法: \(size)"
        case .wrongDataCount(let expected, let found):
            return "LUT 数据量不符(期望 \(expected) 行,实际 \(found) 行)"
        }
    }
}

/// Adobe .cube 格式解析器(3D,浮点数据)。
/// 规范:红变化最快,依次绿、蓝;支持 # 注释、TITLE、LUT_3D_SIZE 头。
enum LUTLoader {

    private final class BundleToken {}

    /// 默认取本模块所在的 Bundle(宿主 App 或测试宿主)。
    static var bundle: Bundle { Bundle(for: BundleToken.self) }

    static func parseCube(text: String) throws -> ColorCube {
        var size = 0
        var values = [Float]()
        values.reserveCapacity(33 * 33 * 33 * 3)

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let upper = line.uppercased()
            if upper.hasPrefix("TITLE") { continue }
            if upper.hasPrefix("DOMAIN_") { continue }
            if upper.hasPrefix("LUT_1D_SIZE") { continue }
            if upper.hasPrefix("LUT_3D_SIZE") {
                let parts = line.split(separator: " ").map(String.init)
                guard parts.count >= 2, let parsed = Int(parts[1]) else {
                    throw LUTLoaderError.malformedHeader
                }
                size = parsed
                continue
            }

            let comps = line.split(separator: " ").compactMap { Float($0) }
            if comps.count == 3 {
                values.append(contentsOf: comps)
            }
        }

        guard size >= 2 else { throw LUTLoaderError.invalidSize(size) }

        let expected = size * size * size * 3
        let found = values.count
        guard found == expected else {
            throw LUTLoaderError.wrongDataCount(expected: expected / 3, found: found / 3)
        }

        var rgba = [Float](repeating: 0, count: size * size * size * 4)
        var src = 0
        var dst = 0
        while src < found {
            rgba[dst] = values[src]
            rgba[dst + 1] = values[src + 1]
            rgba[dst + 2] = values[src + 2]
            rgba[dst + 3] = 1
            src += 3
            dst += 4
        }

        let data = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
        return ColorCube(size: size, data: data)
    }

    static func load(named name: String, in bundle: Bundle? = nil) throws -> ColorCube {
        let target = bundle ?? Self.bundle
        guard let url = target.url(forResource: name, withExtension: "cube") else {
            throw LUTLoaderError.fileMissing(name)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parseCube(text: text)
    }
}

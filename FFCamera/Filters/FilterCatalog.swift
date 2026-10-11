import Foundation

/// 单个滤镜的定义。id 同时是 LUT 文件名(不含扩展名),例如 "ff_01" → ff_01.cube。
struct FilterSpec: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let series: Int
    let lutFile: String
}

/// 滤镜目录:5 个系列、24 个滤镜,结构与 Doka 的 5 组对齐;命名全部原创,显示名在 M2 定稿。
enum FilterCatalog {

    static let seriesNames: [String] = ["经典", "暖调", "冷调", "清透", "复古"]

    static let all: [FilterSpec] = {
        var specs: [FilterSpec] = []
        func add(_ index: Int, _ series: Int) {
            let id = String(format: "ff_%02d", index)
            let name = "FF " + String(format: "%02d", index)
            specs.append(FilterSpec(id: id, name: name, series: series, lutFile: id))
        }
        for i in 1...12 { add(i, 0) }   // 经典
        for i in 13...15 { add(i, 1) }  // 暖调
        for i in 16...17 { add(i, 2) }  // 冷调
        for i in 18...22 { add(i, 3) }  // 清透
        for i in 23...24 { add(i, 4) }  // 复古
        return specs
    }()

    static func filter(id: String) -> FilterSpec? {
        all.first { $0.id == id }
    }

    static func filters(series: Int) -> [FilterSpec] {
        all.filter { $0.series == series }
    }
}

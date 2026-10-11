import Foundation

/// 单个滤镜的定义。id 同时是 LUT 文件名(不含扩展名),例如 "ff_01" → ff_01.cube。
struct FilterSpec: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let series: Int
    let lutFile: String
}

/// 滤镜目录:5 个系列、24 个滤镜。名字全部原创、描述观感。
enum FilterCatalog {

    static let seriesNames: [String] = ["经典", "暖调", "冷调", "清透", "复古"]

    static let all: [FilterSpec] = [
        // 经典
        spec("ff_01", "清透", 0),
        spec("ff_02", "柔和", 0),
        spec("ff_03", "鲜艳", 0),
        spec("ff_04", "淡雅", 0),
        spec("ff_05", "暖阳", 0),
        spec("ff_06", "清冷", 0),
        spec("ff_07", "暖黑白", 0),
        spec("ff_08", "褪色", 0),
        spec("ff_09", "蓝影", 0),
        spec("ff_10", "金色", 0),
        spec("ff_11", "黑白", 0),
        spec("ff_12", "奶油", 0),
        // 暖调
        spec("ff_13", "暖肤", 1),
        spec("ff_14", "蜜糖", 1),
        spec("ff_15", "琥珀", 1),
        // 冷调
        spec("ff_16", "钢蓝", 2),
        spec("ff_17", "冰蓝", 2),
        // 清透
        spec("ff_18", "空气感", 3),
        spec("ff_19", "明亮", 3),
        spec("ff_20", "浅蓝", 3),
        spec("ff_21", "柔光", 3),
        spec("ff_22", "奶白", 3),
        // 复古
        spec("ff_23", "棕调", 4),
        spec("ff_24", "青橙", 4),
    ]

    private static func spec(_ id: String, _ name: String, _ series: Int) -> FilterSpec {
        FilterSpec(id: id, name: name, series: series, lutFile: id)
    }

    static func filter(id: String) -> FilterSpec? {
        all.first { $0.id == id }
    }

    static func filters(series: Int) -> [FilterSpec] {
        all.filter { $0.series == series }
    }
}

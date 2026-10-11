import Foundation

struct FilterRecommendation: Equatable, Identifiable {
    let spec: FilterSpec
    let reason: String
    var id: String { spec.id }
}

/// 滤镜推荐:场景标签 + 色彩统计 → 2 个建议(原创映射规则)。
enum FilterRecommender {

    static func recommend(labels: [String],
                          avgSaturation: CGFloat,
                          avgBrightness: CGFloat) -> [FilterRecommendation] {
        var recs: [FilterRecommendation] = []
        func add(_ id: String, _ reason: String) {
            guard let spec = FilterCatalog.filter(id: id),
                  !recs.contains(where: { $0.spec.id == id }) else { return }
            recs.append(FilterRecommendation(spec: spec, reason: reason))
        }

        let joined = labels.joined(separator: " ")
        func has(_ words: [String]) -> Bool {
            words.contains { joined.contains($0) }
        }

        if has(["sky", "cloud", "beach", "ocean", "sea", "water", "snow", "lake"]) {
            add("ff_17", "清透冷调更干净")
            add("ff_06", "蓝天白云 · 通透加成")
        } else if has(["food", "cuisine", "dish", "meal", "dessert", "fruit", "flower", "plant", "leaf", "tree", "forest", "garden"]) {
            add("ff_03", "鲜活主体 · 浓郁更出彩")
            add("ff_10", "暖光质感 · 金色调")
        } else if has(["night", "dark", "bar", "club", "candle", "lamp", "fireworks"]) || avgBrightness < 0.28 {
            add("ff_11", "暗光氛围 · 高对比黑白")
            add("ff_24", "夜景 · 青橙复古压暗部")
        } else if has(["person", "portrait", "face", "people", "selfie", "hair", "smile", "child"]) {
            add("ff_13", "人像 · 暖调肤色")
            add("ff_02", "柔和低对比更亲肤")
        } else if has(["building", "architecture", "city", "skyline", "street", "urban", "bridge"]) {
            add("ff_16", "城市线条 · 冷调提质感")
            add("ff_01", "建筑 · 干净通透")
        } else {
            add("ff_01", "通用场景 · 清透百搭")
            add("ff_12", "日常随手 · 轻暖调")
        }

        if avgSaturation > 0.45, let first = recs.first {
            recs = [first]
            add("ff_04", "色彩偏浓 · 降一档更耐看")
        }
        return Array(recs.prefix(2))
    }
}

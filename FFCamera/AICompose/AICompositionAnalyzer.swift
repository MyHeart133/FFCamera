import AVFoundation
import Combine
import Foundation

/// 实时 AI 构图分析器:节流消费相机帧,自动降采样后跑 Vision,产出主体框 / 构图引导 / 滤镜推荐。
/// 所有内部状态约束在私有队列;对外状态切回主线程更新。
/// 大帧只在降采样期间被短暂持有(毫秒级),避免吃光相机缓冲池。
final class AICompositionAnalyzer: ObservableObject {

    @Published private(set) var subjectBox: CGRect?
    @Published private(set) var guidance: CompositionEngine.Guidance?
    @Published private(set) var recommendations: [FilterRecommendation] = []
    @Published private(set) var frameAspect: CGFloat = 0.75

    private let queue = DispatchQueue(label: "com.ffcamera.ai", qos: .userInitiated)
    private var enabled = false
    private var lastAnalysisAt: CFAbsoluteTime = 0
    private var lastRecommendAt: CFAbsoluteTime = 0
    private let analysisInterval: CFAbsoluteTime = 0.25   // 引导 ~4 fps
    private let recommendInterval: CFAbsoluteTime = 2.5

    /// 任意线程调用;内部切换队列并节流。
    func ingest(_ pixelBuffer: CVPixelBuffer) {
        queue.async { [weak self] in
            guard let self, self.enabled else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard now - self.lastAnalysisAt >= self.analysisInterval else { return }
            self.lastAnalysisAt = now
            let wantRecommend = now - self.lastRecommendAt >= self.recommendInterval
            if wantRecommend {
                self.lastRecommendAt = now
            }
            self.analyze(pixelBuffer, recommend: wantRecommend)
        }
    }

    /// 开关(任意线程调用)。
    func setEnabled(_ value: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.enabled = value
            if !value {
                DispatchQueue.main.async {
                    self.subjectBox = nil
                    self.guidance = nil
                    self.recommendations = []
                }
            }
        }
    }

    // MARK: - 分析(队列内)

    private func analyze(_ pixelBuffer: CVPixelBuffer, recommend: Bool) {
        guard let prepared = Self.prepare(pixelBuffer) else { return }

        let box = SubjectDetector.detectSubject(in: prepared.small)
        var recs: [FilterRecommendation] = []
        if recommend {
            let labels = SubjectDetector.classifyScene(in: prepared.small)
            let stats = SubjectDetector.averageStats(of: prepared.smallImage)
            recs = FilterRecommender.recommend(
                labels: labels,
                avgSaturation: stats.saturation,
                avgBrightness: stats.brightness
            )
        }

        DispatchQueue.main.async {
            self.frameAspect = prepared.aspect
            self.subjectBox = box
            self.guidance = box.map { CompositionEngine.guidance(subjectBox: $0) }
            if recommend {
                self.recommendations = recs
            }
        }
    }

    /// 大缓冲 → 约 512px 小图;检测/分类都在小图上做。
    private static func prepare(_ pixelBuffer: CVPixelBuffer)
        -> (small: CGImage, aspect: CGFloat, smallImage: CIImage)? {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard width > 1, height > 1 else { return nil }
        let aspect = width / height

        let full = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = min(1.0, 512.0 / max(full.extent.width, full.extent.height))
        let small = full.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = FilterEngine.shared.context.createCGImage(small, from: small.extent) else {
            return nil
        }
        return (cg, aspect, small)
    }
}

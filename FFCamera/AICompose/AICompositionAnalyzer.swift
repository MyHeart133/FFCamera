import AVFoundation
import Combine
import Foundation

/// 实时 AI 构图分析器:节流消费相机帧,产出主体框 / 构图引导 / 滤镜推荐。
/// 所有对外状态在主线程更新;Vision 计算在私有队列。
final class AICompositionAnalyzer: ObservableObject {

    @Published private(set) var subjectBox: CGRect?
    @Published private(set) var guidance: CompositionEngine.Guidance?
    @Published private(set) var recommendations: [FilterRecommendation] = []
    @Published private(set) var frameAspect: CGFloat = 0.75

    /// 由界面控制开关。
    var isEnabled = false

    private let queue = DispatchQueue(label: "com.ffcamera.ai", qos: .userInitiated)
    private var lastGuidanceAt: CFAbsoluteTime = 0
    private var lastRecommendAt: CFAbsoluteTime = 0
    private var busy = false

    private let guidanceInterval: CFAbsoluteTime = 0.16   // ~6 fps
    private let recommendInterval: CFAbsoluteTime = 2.0

    func ingest(_ pixelBuffer: CVPixelBuffer) {
        guard isEnabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard !busy, now - lastGuidanceAt >= guidanceInterval else { return }
        busy = true
        lastGuidanceAt = now

        let wantRecommend = now - lastRecommendAt >= recommendInterval
        if wantRecommend {
            lastRecommendAt = now
        }

        queue.async { [weak self] in
            guard let self else { return }
            let box = SubjectDetector.detectSubject(in: pixelBuffer)
            let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
            let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
            let aspect = height > 0 ? width / height : 0.75

            var recs: [FilterRecommendation] = []
            if wantRecommend {
                let labels = SubjectDetector.classifyScene(in: pixelBuffer)
                let stats = SubjectDetector.averageStats(of: pixelBuffer)
                recs = FilterRecommender.recommend(
                    labels: labels,
                    avgSaturation: stats.saturation,
                    avgBrightness: stats.brightness
                )
            }

            DispatchQueue.main.async {
                self.busy = false
                self.frameAspect = aspect
                self.subjectBox = box
                self.guidance = box.map { CompositionEngine.guidance(subjectBox: $0) }
                if wantRecommend {
                    self.recommendations = recs
                }
            }
        }
    }

    func reset() {
        subjectBox = nil
        guidance = nil
        recommendations = []
    }
}

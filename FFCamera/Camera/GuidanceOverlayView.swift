import SwiftUI

/// AI 构图引导叠加层:主体框 + 目标虚线环 + 位移箭头 + 状态提示。
struct GuidanceOverlayView: View {

    let guidance: CompositionEngine.Guidance
    let frameAspect: CGFloat
    let mirrored: Bool

    var body: some View {
        GeometryReader { geo in
            let mapper = FrameMapper(viewSize: geo.size, frameAspect: frameAspect)
            let subjectRect = mapper.map(guidance.subjectBox, mirrored: mirrored)
            let targetPoint = mapper.map(point: guidance.targetPoint, mirrored: mirrored)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(guidance.aligned ? Color.green : Color.white.opacity(0.85), lineWidth: 1.5)
                    .frame(width: subjectRect.width, height: subjectRect.height)
                    .position(x: subjectRect.midX, y: subjectRect.midY)

                Circle()
                    .stroke(
                        Theme.accent.opacity(guidance.aligned ? 0.25 : 0.95),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 5])
                    )
                    .frame(width: 46, height: 46)
                    .position(targetPoint)

                if !guidance.aligned {
                    ArrowShape(
                        from: CGPoint(x: subjectRect.midX, y: subjectRect.midY),
                        to: targetPoint,
                        trim: 34
                    )
                    .stroke(Theme.accent.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }

                VStack {
                    Text(guidance.hint)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(guidance.aligned ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(guidance.aligned ? Color.green : Color.black.opacity(0.45), in: Capsule())
                        .padding(.top, 64)
                    Spacer()
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 从 A 指向 B 的箭头,末端带箭头帽;trim 为距目标点保留的距离。
struct ArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint
    let trim: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max((dx * dx + dy * dy).squareRoot(), 0.001)
        guard length > trim + 14 else { return path }

        let ux = dx / length
        let uy = dy / length
        let end = CGPoint(x: to.x - ux * trim, y: to.y - uy * trim)

        path.move(to: from)
        path.addLine(to: end)

        let headSize: CGFloat = 11
        let angle = atan2(uy, ux)
        let left = CGPoint(
            x: end.x - cos(angle - .pi / 6) * headSize,
            y: end.y - sin(angle - .pi / 6) * headSize
        )
        let right = CGPoint(
            x: end.x - cos(angle + .pi / 6) * headSize,
            y: end.y - sin(angle + .pi / 6) * headSize
        )
        path.move(to: left)
        path.addLine(to: end)
        path.addLine(to: right)
        return path
    }
}

/// 归一化帧坐标(左上原点)→ aspect-fill 显示视图坐标。
struct FrameMapper {
    let viewSize: CGSize
    let frameAspect: CGFloat

    private var scale: CGFloat {
        guard frameAspect > 0.01, viewSize.height > 0 else { return 1 }
        return max(viewSize.width / frameAspect, viewSize.height)
    }

    private var scaledSize: CGSize {
        CGSize(width: frameAspect * scale, height: scale)
    }

    func map(_ rect: CGRect, mirrored: Bool) -> CGRect {
        let size = scaledSize
        var x = rect.minX * size.width - (size.width - viewSize.width) / 2
        let y = rect.minY * size.height - (size.height - viewSize.height) / 2
        let w = rect.width * size.width
        let h = rect.height * size.height
        if mirrored {
            x = viewSize.width - x - w
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    func map(point: CGPoint, mirrored: Bool) -> CGPoint {
        let size = scaledSize
        var x = point.x * size.width - (size.width - viewSize.width) / 2
        let y = point.y * size.height - (size.height - viewSize.height) / 2
        if mirrored {
            x = viewSize.width - x
        }
        return CGPoint(x: x, y: y)
    }
}

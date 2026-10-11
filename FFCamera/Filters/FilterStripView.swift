import SwiftUI

/// 滤镜选择条:系列切换 + 缩略图 + 强度滑杆。
struct FilterStripView: View {

    @ObservedObject var camera: CameraController
    @State private var selectedSeries = 0
    @State private var thumbTick = 0

    var body: some View {
        VStack(spacing: 10) {
            seriesRow
            filterRow
            if camera.activeFilter != nil {
                intensityRow
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: FilterThumbnailProvider.didUpdate)) { _ in
            thumbTick += 1
        }
    }

    private var seriesRow: some View {
        HStack(spacing: 8) {
            ForEach(0..<FilterCatalog.seriesNames.count, id: \.self) { index in
                let active = index == selectedSeries
                Button {
                    selectedSeries = index
                } label: {
                    Text(FilterCatalog.seriesNames[index])
                        .font(.caption2.weight(active ? .bold : .regular))
                        .foregroundStyle(active ? .black : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(active ? Color.white : Color.black.opacity(0.35), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                filterCell(spec: nil, title: "原图")
                ForEach(FilterCatalog.filters(series: selectedSeries)) { spec in
                    filterCell(spec: spec, title: spec.name)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func filterCell(spec: FilterSpec?, title: String) -> some View {
        let active = camera.activeFilter?.id == spec?.id
        return Button {
            camera.activeFilter = spec
            if spec != nil && camera.filterIntensity < 0.05 {
                camera.filterIntensity = 1.0
            }
        } label: {
            VStack(spacing: 5) {
                Image(uiImage: FilterThumbnailProvider.thumbnail(for: spec))
                    .resizable()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(active ? Theme.accent : Color.white.opacity(0.25), lineWidth: active ? 2 : 1)
                    )
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(active ? .white : .white.opacity(0.65))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var intensityRow: some View {
        HStack(spacing: 10) {
            Text(camera.activeFilter?.name ?? "")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 44, alignment: .leading)
            Slider(value: $camera.filterIntensity, in: 0...1)
                .tint(Theme.accent)
            Text("\(Int((camera.filterIntensity * 100).rounded()))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 4)
    }
}

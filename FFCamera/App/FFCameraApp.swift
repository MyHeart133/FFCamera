import SwiftUI

@main
struct FFCameraApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Theme

enum Theme {
    static let accent = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let background = Color(red: 0.07, green: 0.07, blue: 0.08)
}

// MARK: - Root

struct RootView: View {
    enum Tab: Hashable { case camera, gallery, settings }

    @State private var tab: Tab = .camera

    var body: some View {
        TabView(selection: $tab) {
            CameraHomeView()
                .tag(Tab.camera)
                .tabItem { Label("相机", systemImage: "camera.viewfinder") }
            GalleryHomeView()
                .tag(Tab.gallery)
                .tabItem { Label("相册", systemImage: "photo.on.rectangle.angled") }
            SettingsHomeView()
                .tag(Tab.settings)
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
    }
}

// MARK: - Camera

struct CameraHomeView: View {
    var body: some View {
        CameraScreenView()
    }
}

// MARK: - Gallery (placeholder, M5)

struct GalleryHomeView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 56, weight: .thin))
                    .foregroundStyle(Theme.accent)
                Text("相册模块")
                    .font(.title2.weight(.semibold))
                Text("M5 里程碑:照片库与管理")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Settings

struct SettingsHomeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("关于") {
                    LabeledContent("应用", value: "FFCamera")
                    LabeledContent("版本", value: "\(AppInfo.version) (\(AppInfo.build))")
                    LabeledContent("滤镜数量", value: "\(FilterCatalog.all.count)")
                }
                Section("说明") {
                    Text("自用项目 · 端侧 AI 构图与滤镜相机")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }
}

#Preview {
    RootView()
}

import Foundation
import os

// MARK: - App metadata

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}

// MARK: - Logging

enum Log {
    private static let subsystem = "com.ffcamera.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let filter = Logger(subsystem: subsystem, category: "filter")
    static let ai = Logger(subsystem: subsystem, category: "ai")
}

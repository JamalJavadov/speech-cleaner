import Foundation

enum ToolLocator {
    static func find(_ name: String) -> String? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Tools/\(name)").path
        let candidates = [bundled, "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var modelURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Speech Cleaner/Models", isDirectory: true)
            .appendingPathComponent("ggml-medium-q5_0.bin")
    }
}

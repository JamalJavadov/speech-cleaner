import Foundation

enum CleaningProfile: String, CaseIterable, Identifiable, Codable {
    case gentle = "Yumşaq"
    case standard = "Standart"
    case tight = "Sıx"

    var id: String { rawValue }

    var minimumLongPause: Double {
        switch self {
        case .gentle: return 0.90
        case .standard: return 0.65
        case .tight: return 0.45
        }
    }

    var keptPause: Double {
        switch self {
        case .gentle: return 0.30
        case .standard: return 0.20
        case .tight: return 0.14
        }
    }

    var noiseReduction: Int {
        switch self {
        case .gentle: return 7
        case .standard: return 10
        case .tight: return 13
        }
    }
}

struct WordTimestamp: Codable, Identifiable, Sendable {
    let id: Int
    let word: String
    let start: Double
    let end: Double

    enum CodingKeys: String, CodingKey {
        case id = "index"
        case word, start, end
    }

    var duration: Double { max(0, end - start) }
    var startLabel: String { Self.clock(start) }
    var endLabel: String { Self.clock(end) }

    static func clock(_ seconds: Double) -> String {
        let totalMilliseconds = max(0, Int((seconds * 1000).rounded()))
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let secs = (totalMilliseconds % 60_000) / 1_000
        let millis = totalMilliseconds % 1_000
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
    }
}

struct ProcessingConfiguration: Sendable {
    let inputURL: URL
    let outputRoot: URL
    let profile: CleaningProfile
    let minimumLongPause: Double
    let keptPause: Double
    let createMP4: Bool
}

struct ProcessingResult: Sendable {
    let outputDirectory: URL
    let cleanedWAV: URL
    let cleanedM4A: URL
    let mapMP4: URL?
    let words: [WordTimestamp]
    let sourceDuration: Double
    let finalDuration: Double
    let elapsed: Double
}

struct ProcessingReport: Codable {
    let app: String
    let createdAt: String
    let sourceFile: String
    let profile: String
    let sourceDurationSeconds: Double
    let finalDurationSeconds: Double
    let removedDurationSeconds: Double
    let compressionPercent: Double
    let wordCount: Int
    let processingTimeSeconds: Double
    let realtimeFactor: Double
    let machine: String
    let model: String
}

enum PipelineError: LocalizedError {
    case missingTool(String)
    case missingModel(URL)
    case processFailed(String, String)
    case invalidDuration
    case noWords
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingTool(let name):
            return "Lazımi köməkçi tapılmadı: \(name). Homebrew vasitəsilə ffmpeg və whisper-cpp quraşdırılmalıdır."
        case .missingModel(let url):
            return "Azərbaycan dili modeli tapılmadı: \(url.path)"
        case .processFailed(let step, let log):
            return "\(step) mərhələsi uğursuz oldu.\n\(log.suffix(1200))"
        case .invalidDuration:
            return "Audio müddətini müəyyən etmək mümkün olmadı."
        case .noWords:
            return "Audio emal edildi, lakin nitq sözləri aşkarlanmadı. Giriş faylını və səs səviyyəsini yoxlayın."
        case .cancelled:
            return "Emal dayandırıldı."
        }
    }
}

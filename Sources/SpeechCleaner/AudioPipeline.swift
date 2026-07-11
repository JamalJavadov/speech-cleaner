import Foundation

typealias PipelineProgress = @Sendable (Double, String) -> Void

final class AudioPipeline: @unchecked Sendable {
    private struct SilenceInterval {
        let start: Double
        let end: Double
    }

    private let runner: ProcessRunner
    private let fileManager = FileManager.default
    private let locale = Locale(identifier: "en_US_POSIX")

    init(runner: ProcessRunner) {
        self.runner = runner
    }

    func process(_ configuration: ProcessingConfiguration, progress: @escaping PipelineProgress) throws -> ProcessingResult {
        let started = Date()
        guard let ffmpeg = ToolLocator.find("ffmpeg") else { throw PipelineError.missingTool("ffmpeg") }
        guard let ffprobe = ToolLocator.find("ffprobe") else { throw PipelineError.missingTool("ffprobe") }
        guard let whisper = ToolLocator.find("whisper-cli") else { throw PipelineError.missingTool("whisper-cli") }
        guard fileManager.fileExists(atPath: ToolLocator.modelURL.path) else { throw PipelineError.missingModel(ToolLocator.modelURL) }

        try fileManager.createDirectory(at: configuration.outputRoot, withIntermediateDirectories: true)
        let outputDirectory = try makeOutputDirectory(root: configuration.outputRoot, input: configuration.inputURL)
        let denoisedWAV = outputDirectory.appendingPathComponent(".denoised-full-length.wav")
        let preNormalizedWAV = outputDirectory.appendingPathComponent(".cleaned-pre-normalize.wav")
        let cleanedWAV = outputDirectory.appendingPathComponent("cleaned-voice.wav")
        let cleanedM4A = outputDirectory.appendingPathComponent("cleaned-voice.m4a")
        let transcriptionWAV = outputDirectory.appendingPathComponent(".transcription-16khz.wav")
        let transcriptBase = outputDirectory.appendingPathComponent(".whisper-transcript")

        progress(0.03, "Audio məlumatları oxunur")
        let sourceDuration = try probeDuration(configuration.inputURL, ffprobe: ffprobe)

        progress(0.09, "Fon səsi azaldılır")
        _ = try runner.run(ffmpeg, [
            "-hide_banner", "-loglevel", "warning", "-y",
            "-i", configuration.inputURL.path,
            "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "48000",
            "-af", preCleanFilter(configuration),
            "-c:a", "pcm_s24le", denoisedWAV.path
        ], step: "Səs təmizləmə")

        progress(0.17, "Uzun pauzalar dəqiq ölçülür")
        let silences = try detectSilences(
            denoisedWAV,
            minimumDuration: configuration.minimumLongPause,
            ffmpeg: ffmpeg
        )

        progress(0.20, silences.isEmpty ? "Uzun pauza tapılmadı" : "\(silences.count) uzun pauza qısaldılır")
        try renderCompressedTimeline(
            input: denoisedWAV,
            output: preNormalizedWAV,
            duration: sourceDuration,
            silences: silences,
            keptPause: min(configuration.keptPause, max(0.08, configuration.minimumLongPause - 0.05)),
            ffmpeg: ffmpeg
        )
        try? fileManager.removeItem(at: denoisedWAV)

        progress(0.24, "Səs səviyyəsi YouTube üçün normallaşdırılır")
        _ = try runner.run(ffmpeg, [
            "-hide_banner", "-loglevel", "warning", "-y",
            "-i", preNormalizedWAV.path,
            "-af", "loudnorm=I=-16:LRA=7:TP=-1.5:print_format=summary",
            "-ar", "48000", "-c:a", "pcm_s24le", cleanedWAV.path
        ], step: "Səs normallaşdırma")
        try? fileManager.removeItem(at: preNormalizedWAV)

        progress(0.29, "YouTube və montaj üçün M4A yaradılır")
        _ = try runner.run(ffmpeg, [
            "-hide_banner", "-loglevel", "warning", "-y",
            "-i", cleanedWAV.path,
            "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart",
            cleanedM4A.path
        ], step: "M4A ixracı")

        let finalDuration = try probeDuration(cleanedWAV, ffprobe: ffprobe)
        progress(0.35, "Azərbaycan dili üçün audio hazırlanır")
        _ = try runner.run(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-i", cleanedWAV.path, "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le",
            transcriptionWAV.path
        ], step: "Transkripsiya hazırlığı")

        progress(0.40, "Azərbaycan dilində sözlər və zamanlar aşkarlanır")
        _ = try runner.run(whisper, [
            "-m", ToolLocator.modelURL.path,
            "-f", transcriptionWAV.path,
            "-l", "az",
            "-t", "8",
            "-sow", "-ml", "1",
            "-ocsv", "-ojf", "-np",
            "-of", transcriptBase.path
        ], step: "Azərbaycan dili transkripsiyası")

        progress(0.69, "Söz-saniyə xəritəsi hazırlanır")
        let whisperCSV = transcriptBase.appendingPathExtension("csv")
        let words = try parseWhisperCSV(whisperCSV)
        guard !words.isEmpty else { throw PipelineError.noWords }
        try writeWordExports(words, directory: outputDirectory)
        try writeReadableTranscript(words, directory: outputDirectory)

        var mapMP4: URL?
        if configuration.createMP4 {
            progress(0.75, "Waveform və söz xəritəsi MP4 hazırlanır")
            let renderer = WordMapVideoRenderer()
            let videoOnly = outputDirectory.appendingPathComponent(".word-map-video.mp4")
            try renderer.render(
                audioURL: cleanedWAV,
                words: words,
                duration: finalDuration,
                outputURL: videoOnly,
                progress: { value in
                    progress(0.75 + value * 0.17, "Waveform və söz xəritəsi MP4 hazırlanır")
                }
            )
            let finalMP4 = outputDirectory.appendingPathComponent("speech-word-map.mp4")
            _ = try runner.run(ffmpeg, [
                "-hide_banner", "-loglevel", "error", "-y",
                "-i", videoOnly.path, "-i", cleanedM4A.path,
                "-map", "0:v:0", "-map", "1:a:0",
                "-c:v", "copy", "-c:a", "copy", "-shortest", "-movflags", "+faststart",
                finalMP4.path
            ], step: "MP4 audio birləşdirməsi")
            try? fileManager.removeItem(at: videoOnly)
            mapMP4 = finalMP4
        }

        progress(0.94, "Hesabat və nəticə məlumatları yazılır")
        try? fileManager.removeItem(at: transcriptionWAV)
        try? fileManager.removeItem(at: whisperCSV)
        try? fileManager.removeItem(at: transcriptBase.appendingPathExtension("json"))
        let elapsed = Date().timeIntervalSince(started)
        try writeReport(
            configuration: configuration,
            outputDirectory: outputDirectory,
            sourceDuration: sourceDuration,
            finalDuration: finalDuration,
            words: words,
            elapsed: elapsed
        )
        try writeGuide(directory: outputDirectory, hasMP4: mapMP4 != nil)
        progress(1.0, "Nəticələr hazırdır")

        return ProcessingResult(
            outputDirectory: outputDirectory,
            cleanedWAV: cleanedWAV,
            cleanedM4A: cleanedM4A,
            mapMP4: mapMP4,
            words: words,
            sourceDuration: sourceDuration,
            finalDuration: finalDuration,
            elapsed: elapsed
        )
    }

    private func preCleanFilter(_ configuration: ProcessingConfiguration) -> String {
        let noise = configuration.profile.noiseReduction
        return [
            "highpass=f=70",
            "lowpass=f=15500",
            "afftdn=nr=\(noise):nf=-40:tn=1:gs=5"
        ].joined(separator: ",")
    }

    private func detectSilences(_ input: URL, minimumDuration: Double, ffmpeg: String) throws -> [SilenceInterval] {
        let result = try runner.run(ffmpeg, [
            "-hide_banner", "-nostats", "-i", input.path,
            "-af", "silencedetect=noise=-45dB:d=\(decimal(minimumDuration))",
            "-f", "null", "-"
        ], step: "Pauza analizi")

        let startRegex = try NSRegularExpression(pattern: #"silence_start:\s*([0-9.]+)"#)
        let endRegex = try NSRegularExpression(pattern: #"silence_end:\s*([0-9.]+)"#)
        var pendingStart: Double?
        var intervals: [SilenceInterval] = []
        for line in result.output.split(whereSeparator: \.isNewline).map(String.init) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = startRegex.firstMatch(in: line, range: range),
               let valueRange = Range(match.range(at: 1), in: line),
               let value = Double(line[valueRange]) {
                pendingStart = value
            }
            if let match = endRegex.firstMatch(in: line, range: range),
               let valueRange = Range(match.range(at: 1), in: line),
               let value = Double(line[valueRange]),
               let start = pendingStart,
               value > start {
                intervals.append(SilenceInterval(start: start, end: value))
                pendingStart = nil
            }
        }
        return intervals
    }

    private func renderCompressedTimeline(input: URL, output: URL, duration: Double, silences: [SilenceInterval], keptPause: Double, ffmpeg: String) throws {
        let kept = max(0.08, keptPause)
        var removed: [(start: Double, end: Double)] = []
        for silence in silences {
            let intervalDuration = silence.end - silence.start
            guard intervalDuration > kept + 0.04 else { continue }
            let padding = kept / 2
            let start = max(0, silence.start + padding)
            let end = min(duration, silence.end - padding)
            if end > start { removed.append((start, end)) }
        }

        var ranges: [(start: Double, end: Double)] = []
        var cursor = 0.0
        for interval in removed.sorted(by: { $0.start < $1.start }) {
            if interval.start > cursor + 0.005 { ranges.append((cursor, interval.start)) }
            cursor = max(cursor, interval.end)
        }
        if cursor < duration - 0.005 { ranges.append((cursor, duration)) }
        guard !ranges.isEmpty else { throw PipelineError.processFailed("Pauza qısaltma", "Saxlanacaq audio intervalı qalmadı") }

        let compressor = "acompressor=threshold=0.125:ratio=2.2:attack=20:release=200:makeup=1.25"
        let arguments: [String]
        if removed.isEmpty {
            arguments = [
                "-hide_banner", "-loglevel", "warning", "-y", "-i", input.path,
                "-af", compressor, "-c:a", "pcm_s24le", output.path
            ]
        } else {
            var pieces: [String] = []
            for (index, range) in ranges.enumerated() {
                pieces.append("[0:a]atrim=start=\(decimal(range.start, digits: 6)):end=\(decimal(range.end, digits: 6)),asetpts=PTS-STARTPTS[s\(index)]")
            }
            let inputs = ranges.indices.map { "[s\($0)]" }.joined()
            pieces.append("\(inputs)concat=n=\(ranges.count):v=0:a=1,\(compressor)[out]")
            arguments = [
                "-hide_banner", "-loglevel", "warning", "-y", "-i", input.path,
                "-filter_complex", pieces.joined(separator: ";"),
                "-map", "[out]", "-c:a", "pcm_s24le", output.path
            ]
        }
        _ = try runner.run(ffmpeg, arguments, step: "Pauza qısaltma")
    }

    private func probeDuration(_ url: URL, ffprobe: String) throws -> Double {
        let result = try runner.run(ffprobe, [
            "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", url.path
        ], step: "Müddət analizi")
        guard let value = Double(result.output.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            throw PipelineError.invalidDuration
        }
        return value
    }

    private func makeOutputDirectory(root: URL, input: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let base = input.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[^A-Za-z0-9ƏəÖöÜüĞğŞşÇçİı_-]+", with: "-", options: .regularExpression)
        let directory = root.appendingPathComponent("\(base)-\(formatter.string(from: Date()))", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func parseWhisperCSV(_ url: URL) throws -> [WordTimestamp] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var words: [WordTimestamp] = []
        for line in content.split(whereSeparator: \.isNewline).dropFirst() {
            let fields = parseCSVLine(String(line))
            guard fields.count >= 3,
                  let startMS = Double(fields[0]),
                  let endMS = Double(fields[1]) else { continue }
            let text = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = text.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
            guard !parts.isEmpty else { continue }
            let start = startMS / 1000.0
            let end = max(start + 0.05, endMS / 1000.0)
            let slice = (end - start) / Double(parts.count)
            for (offset, part) in parts.enumerated() {
                let wordStart = start + Double(offset) * slice
                let wordEnd = offset == parts.count - 1 ? end : start + Double(offset + 1) * slice
                words.append(WordTimestamp(id: words.count + 1, word: part, start: wordStart, end: wordEnd))
            }
        }
        return words
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var field = ""
        var quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if quoted, next < line.endIndex, line[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    quoted.toggle()
                }
            } else if character == ",", !quoted {
                result.append(field)
                field = ""
            } else {
                field.append(character)
            }
            index = line.index(after: index)
        }
        result.append(field)
        return result
    }

    private func writeWordExports(_ words: [WordTimestamp], directory: URL) throws {
        let jsonURL = directory.appendingPathComponent("word-timestamps.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(words).write(to: jsonURL, options: .atomic)

        var csv = "index,word,start_seconds,end_seconds,start_time,end_time\n"
        for item in words {
            let escaped = item.word.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(item.id),\"\(escaped)\",\(decimal(item.start, digits: 3)),\(decimal(item.end, digits: 3)),\(item.startLabel),\(item.endLabel)\n"
        }
        try csv.write(to: directory.appendingPathComponent("word-timestamps.csv"), atomically: true, encoding: .utf8)
    }

    private func writeReadableTranscript(_ words: [WordTimestamp], directory: URL) throws {
        let transcript = words.map(\.word).joined(separator: " ") + "\n"
        try transcript.write(to: directory.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)

        var srt = ""
        var group: [WordTimestamp] = []
        var index = 1
        func flush() {
            guard let first = group.first, let last = group.last else { return }
            srt += "\(index)\n\(srtTime(first.start)) --> \(srtTime(last.end))\n\(group.map(\.word).joined(separator: " "))\n\n"
            index += 1
            group.removeAll(keepingCapacity: true)
        }
        for word in words {
            if let previous = group.last, word.start - previous.end > 0.75 { flush() }
            group.append(word)
            if group.count >= 7 || ((group.last?.end ?? 0) - (group.first?.start ?? 0)) >= 3.2 { flush() }
        }
        flush()
        try srt.write(to: directory.appendingPathComponent("subtitles.srt"), atomically: true, encoding: .utf8)
    }

    private func writeReport(configuration: ProcessingConfiguration, outputDirectory: URL, sourceDuration: Double, finalDuration: Double, words: [WordTimestamp], elapsed: Double) throws {
        let removed = max(0, sourceDuration - finalDuration)
        let report = ProcessingReport(
            app: "Speech Cleaner 1.0",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            sourceFile: configuration.inputURL.lastPathComponent,
            profile: configuration.profile.rawValue,
            sourceDurationSeconds: sourceDuration,
            finalDurationSeconds: finalDuration,
            removedDurationSeconds: removed,
            compressionPercent: sourceDuration > 0 ? removed / sourceDuration * 100 : 0,
            wordCount: words.count,
            processingTimeSeconds: elapsed,
            realtimeFactor: elapsed > 0 ? sourceDuration / elapsed : 0,
            machine: "Apple Silicon macOS",
            model: ToolLocator.modelURL.lastPathComponent
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: outputDirectory.appendingPathComponent("processing-report.json"), options: .atomic)
    }

    private func writeGuide(directory: URL, hasMP4: Bool) throws {
        let mp4Line = hasMP4 ? "• speech-word-map.mp4 — waveform, cari söz və saniyə xəritəsi olan video\n" : ""
        let text = """
        Speech Cleaner nəticələri

        • cleaned-voice.wav — yüksək keyfiyyətli təmizlənmiş mono audio
        • cleaned-voice.m4a — YouTube və montaj üçün 192 kbps audio
        \(mp4Line)• word-timestamps.csv — Excel/Numbers üçün hər sözün vaxtı
        • word-timestamps.json — proqramlaşdırma və avtomatlaşdırma üçün söz xəritəsi
        • subtitles.srt — oxunaqlı qruplaşdırılmış subtitrlər
        • transcript.txt — avtomatik Azərbaycan dili transkripsiyası
        • processing-report.json — müddət və performans hesabatı

        Orijinal fayl dəyişdirilməyib. Avtomatik transkripsiyada xüsusi adları və texniki terminləri yoxlamaq tövsiyə olunur.
        """
        try text.write(to: directory.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
    }

    private func srtTime(_ seconds: Double) -> String {
        WordTimestamp.clock(seconds).replacingOccurrences(of: ".", with: ",")
    }

    private func decimal(_ value: Double, digits: Int = 2) -> String {
        String(format: "%.*f", locale: locale, digits, value)
    }
}

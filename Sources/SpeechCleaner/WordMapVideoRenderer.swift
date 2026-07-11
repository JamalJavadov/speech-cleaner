import AppKit
import AVFoundation
import CoreGraphics
import CoreText
import Foundation

final class WordMapVideoRenderer {
    private let width = 1280
    private let height = 720
    private let fps: Int32 = 10

    func render(audioURL: URL, words: [WordTimestamp], duration: Double, outputURL: URL, progress: @escaping (Double) -> Void) throws {
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_800_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 3
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { throw PipelineError.processFailed("MP4 render", "Video girişi yaradıla bilmədi") }
        writer.add(input)
        guard writer.startWriting() else { throw PipelineError.processFailed("MP4 render", writer.error?.localizedDescription ?? "Naməlum xəta") }
        writer.startSession(atSourceTime: .zero)

        let waveform = sampleWaveform(audioURL, count: 260)
        let frameCount = max(1, Int(ceil(duration * Double(fps))))
        var wordIndex = 0

        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.003) }
            let time = Double(frame) / Double(fps)
            while wordIndex + 1 < words.count, words[wordIndex].end < time { wordIndex += 1 }

            autoreleasepool {
                guard let pool = adaptor.pixelBufferPool else { return }
                var optionalBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer)
                guard let buffer = optionalBuffer else { return }
                draw(buffer: buffer, time: time, duration: duration, words: words, activeIndex: wordIndex, waveform: waveform)
                let presentationTime = CMTime(value: CMTimeValue(frame), timescale: fps)
                adaptor.append(buffer, withPresentationTime: presentationTime)
            }
            if frame % max(1, frameCount / 100) == 0 { progress(Double(frame) / Double(frameCount)) }
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()
        guard writer.status == .completed else {
            throw PipelineError.processFailed("MP4 render", writer.error?.localizedDescription ?? "Video tamamlanmadı")
        }
        progress(1)
    }

    private func draw(buffer: CVPixelBuffer, time: Double, duration: Double, words: [WordTimestamp], activeIndex: Int, waveform: [CGFloat]) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else { return }

        let colors = [
            NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.10, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.12, green: 0.055, blue: 0.19, alpha: 1).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])
        }

        context.setFillColor(NSColor.white.withAlphaComponent(0.045).cgColor)
        context.fill(CGRect(x: 70, y: 72, width: width - 140, height: height - 144))

        drawText("Speech Cleaner • Azərbaycan dili söz xəritəsi", x: 100, y: 620, size: 21, color: NSColor.white.withAlphaComponent(0.66).cgColor, context: context)
        drawText(WordTimestamp.clock(time), x: 100, y: 560, size: 28, color: NSColor.systemCyan.cgColor, context: context, monospaced: true)

        let current = activeIndex < words.count ? words[activeIndex] : words.last
        let active = current.map { time >= $0.start - 0.12 && time <= $0.end + 0.12 } ?? false
        let displayWord = active ? (current?.word ?? "") : "…"
        drawCenteredText(displayWord, y: 385, size: 64, color: NSColor.white.cgColor, context: context)

        if !words.isEmpty {
            let lower = max(0, activeIndex - 3)
            let upper = min(words.count, activeIndex + 4)
            let nearby = words[lower..<upper].map(\.word).joined(separator: "  ")
            drawCenteredText(nearby, y: 330, size: 23, color: NSColor.white.withAlphaComponent(0.48).cgColor, context: context)
        }

        let fraction = duration > 0 ? min(1, max(0, time / duration)) : 0
        drawWaveform(waveform, fraction: fraction, context: context)

        context.setFillColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        context.fill(CGRect(x: 100, y: 107, width: CGFloat(width - 200), height: 5))
        context.setFillColor(NSColor.systemCyan.cgColor)
        context.fill(CGRect(x: 100, y: 107, width: CGFloat(width - 200) * fraction, height: 5))

        drawText("\(activeIndex + 1) / \(words.count) söz", x: 100, y: 78, size: 17, color: NSColor.white.withAlphaComponent(0.5).cgColor, context: context)
        let total = WordTimestamp.clock(duration)
        drawRightText(total, x: CGFloat(width - 100), y: 78, size: 17, color: NSColor.white.withAlphaComponent(0.5).cgColor, context: context)
    }

    private func drawWaveform(_ values: [CGFloat], fraction: Double, context: CGContext) {
        guard !values.isEmpty else { return }
        let left: CGFloat = 100
        let right: CGFloat = CGFloat(width - 100)
        let centerY: CGFloat = 220
        let maxHeight: CGFloat = 70
        let spacing = (right - left) / CGFloat(values.count)
        let completed = Int(Double(values.count) * fraction)
        context.setLineWidth(max(1.5, spacing * 0.52))
        context.setLineCap(.round)
        for (index, value) in values.enumerated() {
            context.setStrokeColor(index <= completed ? NSColor.systemCyan.cgColor : NSColor.systemPurple.withAlphaComponent(0.45).cgColor)
            let x = left + CGFloat(index) * spacing
            let h = max(3, value * maxHeight)
            context.move(to: CGPoint(x: x, y: centerY - h))
            context.addLine(to: CGPoint(x: x, y: centerY + h))
            context.strokePath()
        }
    }

    private func sampleWaveform(_ url: URL, count: Int) -> [CGFloat] {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return Array(repeating: 0.2, count: count) }
        let total = file.length
        let readSize: AVAudioFrameCount = 2048
        var values = [CGFloat]()
        values.reserveCapacity(count)
        for index in 0..<count {
            let position = min(max(0, total - AVAudioFramePosition(readSize)), AVAudioFramePosition(Double(index) / Double(max(1, count - 1)) * Double(total)))
            file.framePosition = position
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: readSize) else {
                values.append(0)
                continue
            }
            do { try file.read(into: buffer, frameCount: readSize) } catch { values.append(0); continue }
            guard let channel = buffer.floatChannelData?[0] else { values.append(0); continue }
            var peak: Float = 0
            for sample in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channel[sample])) }
            values.append(CGFloat(peak))
        }
        let maximum = max(values.max() ?? 1, 0.001)
        return values.map { min(1, max(0.04, $0 / maximum)) }
    }

    private func drawText(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: CGColor, context: CGContext, monospaced: Bool = false) {
        let fontName = monospaced ? "SFMono-Semibold" : "SFProDisplay-Semibold"
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }

    private func drawCenteredText(_ text: String, y: CGFloat, size: CGFloat, color: CGColor, context: CGContext) {
        let font = CTFontCreateWithName("SFProDisplay-Bold" as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
        context.textPosition = CGPoint(x: (CGFloat(width) - bounds.width) / 2, y: y)
        CTLineDraw(line, context)
    }

    private func drawRightText(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: CGColor, context: CGContext) {
        let font = CTFontCreateWithName("SFMono-Regular" as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
        context.textPosition = CGPoint(x: x - bounds.width, y: y)
        CTLineDraw(line, context)
    }
}

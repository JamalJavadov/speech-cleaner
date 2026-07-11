import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject, @unchecked Sendable {
    @Published var inputURL: URL?
    @Published var outputRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Movies/Speech Cleaner", isDirectory: true)
    @Published var profile: CleaningProfile = .standard {
        didSet {
            minimumLongPause = profile.minimumLongPause
            keptPause = profile.keptPause
        }
    }
    @Published var minimumLongPause: Double = CleaningProfile.standard.minimumLongPause
    @Published var keptPause: Double = CleaningProfile.standard.keptPause
    @Published var createMP4 = true
    @Published var isProcessing = false
    @Published var progress = 0.0
    @Published var status = "Audio faylını əlavə edin"
    @Published var activity: [String] = []
    @Published var result: ProcessingResult?
    @Published var errorMessage: String?

    private let runner = ProcessRunner()
    private lazy var pipeline = AudioPipeline(runner: runner)
    private var player: AVPlayer?

    var modelInstalled: Bool {
        FileManager.default.fileExists(atPath: ToolLocator.modelURL.path)
    }

    func chooseInput() {
        let panel = NSOpenPanel()
        panel.title = "Nitq faylını seçin"
        panel.prompt = "Əlavə et"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .quickTimeMovie]
        if panel.runModal() == .OK, let url = panel.url {
            setInput(url)
        }
    }

    func setInput(_ url: URL) {
        guard !isProcessing else { return }
        inputURL = url
        result = nil
        progress = 0
        activity = []
        errorMessage = nil
        status = "Emala hazırdır"
    }

    func chooseOutputRoot() {
        let panel = NSOpenPanel()
        panel.title = "Nəticə qovluğunu seçin"
        panel.prompt = "Seç"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            outputRoot = url
        }
    }

    func start() {
        guard let inputURL, !isProcessing else { return }
        runner.resetCancellation()
        isProcessing = true
        progress = 0
        result = nil
        errorMessage = nil
        activity = []

        let configuration = ProcessingConfiguration(
            inputURL: inputURL,
            outputRoot: outputRoot,
            profile: profile,
            minimumLongPause: minimumLongPause,
            keptPause: keptPause,
            createMP4: createMP4
        )
        let pipeline = pipeline

        Task.detached(priority: .userInitiated) { [self] in
            do {
                let result = try pipeline.process(configuration) { value, message in
                    Task { @MainActor [self] in
                        self.progress = value
                        self.status = message
                        if self.activity.last != message { self.activity.append(message) }
                    }
                }
                await MainActor.run {
                    self.result = result
                    self.isProcessing = false
                    self.progress = 1
                    self.status = "Hazırdır"
                    NSSound(named: "Glass")?.play()
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.status = "Emal tamamlanmadı"
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancel() {
        runner.cancel()
        status = "Dayandırılır…"
    }

    func playSource() {
        guard let inputURL else { return }
        play(inputURL)
    }

    func playCleaned() {
        guard let result else { return }
        play(result.cleanedM4A)
    }

    func stopPlayback() {
        player?.pause()
        player = nil
    }

    func revealResults() {
        guard let result else { return }
        NSWorkspace.shared.activateFileViewerSelecting([result.outputDirectory])
    }

    func openMapVideo() {
        guard let url = result?.mapMP4 else { return }
        NSWorkspace.shared.open(url)
    }

    private func play(_ url: URL) {
        player?.pause()
        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        newPlayer.play()
    }
}

import SwiftUI
import Darwin

@main
struct SpeechCleanerApp: App {
    @StateObject private var model = AppModel()

    init() {
        let arguments = CommandLine.arguments
        guard let marker = arguments.firstIndex(of: "--benchmark"), arguments.indices.contains(marker + 1) else { return }
        let input = URL(fileURLWithPath: arguments[marker + 1])
        let output: URL
        if let outputMarker = arguments.firstIndex(of: "--output"), arguments.indices.contains(outputMarker + 1) {
            output = URL(fileURLWithPath: arguments[outputMarker + 1], isDirectory: true)
        } else {
            output = FileManager.default.temporaryDirectory.appendingPathComponent("SpeechCleaner-Benchmark", isDirectory: true)
        }
        let configuration = ProcessingConfiguration(
            inputURL: input,
            outputRoot: output,
            profile: .standard,
            minimumLongPause: CleaningProfile.standard.minimumLongPause,
            keptPause: CleaningProfile.standard.keptPause,
            createMP4: !arguments.contains("--no-mp4")
        )
        let pipeline = AudioPipeline(runner: ProcessRunner())
        do {
            let result = try pipeline.process(configuration) { value, message in
                print(String(format: "[%3.0f%%] %@", value * 100, message))
            }
            print("RESULT_DIRECTORY=\(result.outputDirectory.path)")
            print("SOURCE_DURATION=\(result.sourceDuration)")
            print("FINAL_DURATION=\(result.finalDuration)")
            print("WORD_COUNT=\(result.words.count)")
            print("ELAPSED=\(result.elapsed)")
            exit(EXIT_SUCCESS)
        } catch {
            fputs("Speech Cleaner benchmark xətası: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1040, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Audio əlavə et…") { model.chooseInput() }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(model.isProcessing)
            }
        }
    }
}

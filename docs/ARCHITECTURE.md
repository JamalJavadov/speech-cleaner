# Architecture

Speech Cleaner is a native macOS application with a SwiftUI interface and a sequential, local media-processing pipeline.

## Components

- `SpeechCleanerApp.swift` defines the app lifecycle and headless benchmark entry point.
- `ContentView.swift` contains the SwiftUI interface.
- `AppModel.swift` owns UI state, file selection, playback, cancellation, and pipeline coordination.
- `AudioPipeline.swift` orchestrates FFmpeg, whisper.cpp, exports, and reports.
- `ProcessRunner.swift` executes child processes and captures sanitized failure output.
- `ToolLocator.swift` resolves bundled or Homebrew command-line tools and the local model.
- `WordMapVideoRenderer.swift` renders the waveform and active-word video with AVFoundation and Core Graphics.
- `Models.swift` contains processing profiles, configuration, results, timestamps, and errors.

## Processing sequence

1. Probe the source duration without changing the source.
2. Convert the first audio stream to mono 48 kHz PCM and apply the selected cleanup filters.
3. Detect silence intervals and keep a short, configurable portion of each long pause.
4. Concatenate the preserved speech segments and normalize the output to -16 LUFS with a -1.5 dB true-peak ceiling.
5. Export clean WAV and M4A audio.
6. Convert a temporary 16 kHz copy for local Azerbaijani transcription.
7. Parse word-level timestamps and write CSV, JSON, SRT, and TXT exports.
8. Optionally render the MP4 word map and write a machine-readable processing report.

Temporary intermediate files are created only inside the result folder and removed after processing.

## Privacy boundary

The application has no networking layer. Media is read from a user-selected local URL, processed by local executables, and written to a user-selected local directory. The repository excludes common audio/video formats and model files to reduce the risk of accidentally committing private or very large artifacts.

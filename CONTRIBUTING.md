# Contributing to Speech Cleaner

Thank you for helping improve Speech Cleaner.

## Development setup

1. Install macOS 14 or newer on an Apple Silicon Mac.
2. Install dependencies with `brew install ffmpeg whisper-cpp`.
3. Place `ggml-medium-q5_0.bin` in `~/Library/Application Support/Speech Cleaner/Models/`.
4. Build with `swift build` or run `./scripts/build-app.sh`.

## Before opening a pull request

- Keep processing local and preserve the original input file.
- Do not commit recordings, models, build output, credentials, or user data.
- Keep UI copy accessible and consistent with the Azerbaijani interface.
- Run `swift build -c release` and test the affected workflow with a disposable audio sample.
- Explain the behavior change and include screenshots for visible UI changes.

## Issues

Use the provided GitHub templates. Include macOS version, Mac model, dependency versions, reproducible steps, and sanitized logs. Do not attach private recordings unless you intentionally have the right to publish them.

## Pull requests

Keep pull requests focused. Describe the problem, the solution, verification performed, and any performance or privacy impact.

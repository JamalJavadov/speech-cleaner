# LinkedIn post

I’m excited to share **Speech Cleaner**, an open-source native macOS app I built to make spoken-audio editing faster — with a special focus on Azerbaijani speech.

Voiceover cleanup often means repeating the same manual steps: cutting long pauses, reducing background noise, balancing loudness, transcribing speech, and preparing timestamped assets for editing. Speech Cleaner brings that workflow into one privacy-first desktop tool.

What it does:

• shortens long pauses while preserving natural spacing between words
• reduces steady background noise and normalizes speech loudness
• transcribes Azerbaijani speech locally and creates word-level timestamps
• exports clean WAV and M4A audio, CSV/JSON timing data, SRT/TXT transcripts, and an optional waveform MP4
• keeps the entire workflow on the Mac — recordings are never uploaded

The app is built with **SwiftUI, AppKit, AVFoundation, Core Graphics, FFmpeg, whisper.cpp, and the Whisper multilingual model**. It also includes a headless benchmark mode for measuring the full production pipeline.

On an Apple M4 Pro, a 6:12 Azerbaijani voiceover completed the full workflow — including transcription and MP4 rendering — in about 68 seconds, or roughly 5.4× real-time.

The project is now open source. I’d be happy to hear feedback from macOS developers, audio creators, and anyone working with Azerbaijani language technology.

GitHub: https://github.com/JamalJavadov/speech-cleaner

#OpenSource #Swift #SwiftUI #macOS #AudioProcessing #SpeechRecognition #Whisper #FFmpeg #Azerbaijan #DeveloperTools

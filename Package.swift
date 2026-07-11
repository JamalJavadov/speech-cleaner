// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpeechCleaner",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SpeechCleaner", targets: ["SpeechCleaner"])
    ],
    targets: [
        .executableTarget(
            name: "SpeechCleaner",
            path: "Sources/SpeechCleaner"
        )
    ],
    swiftLanguageModes: [.v5]
)

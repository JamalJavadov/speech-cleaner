import Foundation

struct ProcessResult: Sendable {
    let output: String
    let exitCode: Int32
    let elapsed: TimeInterval
}

final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Process?
    private var cancelled = false

    func resetCancellation() {
        lock.lock()
        cancelled = false
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = current
        lock.unlock()
        if let process, process.isRunning {
            process.interrupt()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                if process.isRunning { process.terminate() }
            }
        }
    }

    func run(_ executable: String, _ arguments: [String], step: String) throws -> ProcessResult {
        lock.lock()
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled { throw PipelineError.cancelled }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("speech-cleaner-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        process.standardOutput = handle
        process.standardError = handle

        lock.lock()
        current = process
        lock.unlock()

        let started = Date()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: logURL)
            lock.lock()
            current = nil
            lock.unlock()
            throw PipelineError.processFailed(step, error.localizedDescription)
        }
        try? handle.close()

        let data = (try? Data(contentsOf: logURL)) ?? Data()
        try? FileManager.default.removeItem(at: logURL)
        let output = String(data: data, encoding: .utf8) ?? ""

        lock.lock()
        current = nil
        let isCancelled = cancelled
        lock.unlock()

        if isCancelled { throw PipelineError.cancelled }
        if process.terminationStatus != 0 {
            throw PipelineError.processFailed(step, output)
        }
        return ProcessResult(output: output, exitCode: process.terminationStatus, elapsed: Date().timeIntervalSince(started))
    }
}

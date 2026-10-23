import Foundation

/// Local breadcrumbs only: no API accepts arbitrary messages or request/response bodies.
/// Main-actor confinement serializes writes. Failures never interrupt dictation.
@MainActor
final class DiagnosticLog {
    enum Event: String, Codable {
        case launch, duplicateInstance, ready, terminationRequested, cleanTermination
        case windowClosed, reopenRequested, windowReopened, sleep, wake
        case recordingRequested, recordingStarted, recordingStopped, recordingLimitReached, recordingFailed
        case recordingPausedForSleep, wakeProcessingStarted, recordingReplaced, recordingBlockedLocked
        case microphoneDenied, processingBlockedLocked, audioInvalid, processingStarted, retryStarted
        case transcribing, emptyChunk, refining, processingSucceeded, processingFailed, processingCancelled
        case recordingDeleted, audioExported, audioExportFailed, insertionSkipped, pasteRequested
    }
    struct Failure: Codable {
        enum Kind: String, Codable { case network, http, incomplete, implausible, noSpeech, system }
        let kind: Kind
        let code: Int?
        let chunk: Int?

        static func classify(_ error: Error, chunk: Int? = nil) -> Failure {
            guard let error = error as? DictationFailure else {
                return Failure(kind: .system, code: (error as NSError).code, chunk: chunk)
            }
            switch error {
            case .chunk(let context, let underlying): return classify(underlying, chunk: context.index)
            case .transport(_, let underlying): return Failure(kind: .network, code: (underlying as NSError).code, chunk: chunk)
            case .response(_, let diagnostic): return Failure(kind: .http, code: diagnostic.http, chunk: chunk)
            case .incompleteRefinement: return Failure(kind: .incomplete, code: nil, chunk: chunk)
            case .implausibleRefinement: return Failure(kind: .implausible, code: nil, chunk: chunk)
            case .noSpeech: return Failure(kind: .noSpeech, code: nil, chunk: chunk)
            }
        }
    }
    private struct Entry: Codable {
        let timestamp: String
        let session: UUID
        let pid: Int32
        let build: String
        let event: Event
        let operation: UUID?
        let index: Int?
        let total: Int?
        let seconds: Double?
        let failure: Failure?
    }
    static let build = "2026-10-23-glass-1"
    nonisolated static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MiniTypeless", isDirectory: true)
    }
    let directory: URL
    private let session = UUID()
    private let limit: Int
    private let backups: Int
    private let enabled: Bool
    private(set) var writeFailed = false
    private let clock = ISO8601DateFormatter()

    init(directory: URL = DiagnosticLog.defaultDirectory, enabled: Bool = true,
         limit: Int = 262_144, backups: Int = 3) {
        self.directory = directory
        self.enabled = enabled
        self.limit = max(1024, limit)
        self.backups = max(1, backups)
        clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    private func file(_ index: Int) -> URL {
        directory.appendingPathComponent(index == 0 ? "events.jsonl" : "events.\(index).jsonl")
    }

    func record(_ event: Event, operation: UUID? = nil, index: Int? = nil,
                total: Int? = nil, seconds: Double? = nil, failure: Failure? = nil) {
        guard enabled else { return }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let entry = Entry(timestamp: clock.string(from: Date()), session: session,
                              pid: ProcessInfo.processInfo.processIdentifier, build: Self.build,
                              event: event, operation: operation, index: index, total: total,
                              seconds: seconds.flatMap { $0.isFinite ? $0 : nil }, failure: failure)
            var data = try JSONEncoder().encode(entry)
            data.append(0x0A)
            let size = (try? fm.attributesOfItem(atPath: file(0).path)[.size] as? NSNumber)?.intValue ?? 0
            if size + data.count > limit {
                if fm.fileExists(atPath: file(backups).path) { try fm.removeItem(at: file(backups)) }
                for index in stride(from: backups - 1, through: 0, by: -1) {
                    if fm.fileExists(atPath: file(index).path) { try fm.moveItem(at: file(index), to: file(index + 1)) }
                }
            }
            if !fm.fileExists(atPath: file(0).path) {
                guard fm.createFile(atPath: file(0).path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                    writeFailed = true
                    return
                }
            }
            let handle = try FileHandle(forWritingTo: file(0))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
            writeFailed = false
        } catch {
            writeFailed = true
        }
    }
}

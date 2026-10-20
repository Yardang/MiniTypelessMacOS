import AVFoundation
import Foundation

struct RecordedAudio {
    let url: URL
    let duration: TimeInterval
}

enum RecordingStopReason { case user, timeLimit }

@MainActor
protocol RecordingDevice: AnyObject {
    var currentTime: TimeInterval { get }
    var finished: ((Bool) -> Void)? { get set }
    func record(forDuration duration: TimeInterval) -> Bool
    func stop()
}

@MainActor
private final class MicrophoneRecorder: NSObject, RecordingDevice, AVAudioRecorderDelegate {
    private let recorder: AVAudioRecorder
    var finished: ((Bool) -> Void)?
    var currentTime: TimeInterval { recorder.currentTime }

    init(url: URL) throws {
        recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
        ])
        super.init()
        recorder.delegate = self
    }
    func record(forDuration duration: TimeInterval) -> Bool { recorder.record(forDuration: duration) }
    func stop() { recorder.stop() }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.finished?(flag) }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.finished?(false) }
    }
}

/// Owns the microphone, hard duration limit and exactly-once stop notification.
/// Completed audio stays available until explicitly discarded by its owner.
@MainActor
final class RecordingController {
    static let maximumDuration: TimeInterval = 600
    typealias Scheduler = (TimeInterval, @escaping @MainActor () -> Void) -> (() -> Void)
    private let makeDevice: (URL) throws -> RecordingDevice
    private let schedule: Scheduler
    private var device: RecordingDevice?
    private var cancelTimer: (() -> Void)?
    private var generation = UUID()
    let url: URL
    var onStopped: ((RecordedAudio, RecordingStopReason) -> Void)?
    var onFailure: (() -> Void)?
    private(set) var completed: RecordedAudio?
    var isRecording: Bool { device != nil }

    init(url: URL = FileManager.default.temporaryDirectory.appendingPathComponent("MiniTypeless-\(UUID()).wav"),
         makeDevice: ((URL) throws -> RecordingDevice)? = nil,
         schedule: Scheduler? = nil) {
        self.url = url
        self.makeDevice = makeDevice ?? { try MicrophoneRecorder(url: $0) }
        self.schedule = schedule ?? { interval, action in
            let timer = Timer(timeInterval: interval, repeats: false) { _ in
                Task { @MainActor in action() }
            }
            RunLoop.main.add(timer, forMode: .common)
            return { timer.invalidate() }
        }
    }

    func start() throws {
        // A new take must not silently overwrite a recoverable completed take.
        guard completed == nil else { throw CocoaError(.fileWriteFileExists) }
        discard()
        let token = UUID()
        generation = token
        let next = try makeDevice(url)
        device = next
        next.finished = { [weak self] success in
            guard let self, self.generation == token, self.isRecording else { return }
            if success { self.stop(.timeLimit) }
            else { self.discard(); self.onFailure?() }
        }
        guard next.record(forDuration: Self.maximumDuration) else {
            discard()
            throw CocoaError(.fileWriteUnknown)
        }
        cancelTimer = schedule(Self.maximumDuration) { [weak self] in
            guard let self, self.generation == token else { return }
            self.stop(.timeLimit)
        }
    }

    func stop(_ reason: RecordingStopReason = .user) {
        guard let device else { return }
        let elapsed = device.currentTime
        self.device = nil
        device.finished = nil
        cancelTimer?()
        cancelTimer = nil
        device.stop()
        // AVAudioRecorder can reset currentTime on its own duration callback.
        let file = try? AVAudioFile(forReading: url)
        let duration = file.map { Double($0.length) / $0.processingFormat.sampleRate } ?? elapsed
        let audio = RecordedAudio(url: url, duration: duration)
        completed = audio
        onStopped?(audio, reason)
    }

    func discard() {
        generation = UUID()
        device?.finished = nil
        device?.stop()
        device = nil
        cancelTimer?()
        cancelTimer = nil
        completed = nil
        try? FileManager.default.removeItem(at: url)
    }

    func exportCompleted(to destination: URL) throws {
        guard let completed else { throw CocoaError(.fileNoSuchFile) }
        guard destination.standardizedFileURL != completed.url.standardizedFileURL else { return }
        // The save panel authorizes replacement at this user-selected path.
        try Data(contentsOf: completed.url).write(to: destination, options: .atomic)
    }
}

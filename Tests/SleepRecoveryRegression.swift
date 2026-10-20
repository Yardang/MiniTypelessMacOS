import AppKit

@MainActor
final class StandbyRecorder: RecordingDevice {
    var currentTime: TimeInterval = 3
    var finished: ((Bool) -> Void)?
    let url: URL
    let failStart: Bool
    init(_ url: URL, failStart: Bool) { self.url = url; self.failStart = failStart }
    func record(forDuration duration: TimeInterval) -> Bool {
        precondition(duration == 600)
        try! AudioChunks.encodePCM(Data(repeating: 1, count: 96000)).write(to: url)
        return !failStart
    }
    func stop() {}
}

@MainActor
final class StandbyRig {
    var device: StandbyRecorder?
    var timer: (() -> Void)?
    var createFails = false
    var startFails = false
    var allowed = true
    var holdPermission = false
    var pendingPermission: ((Bool) -> Void)?
    var cloudFails = false
    var calls = 0
    var permissionCalls = 0
    lazy var recording = RecordingController(makeDevice: { [unowned self] url in
        if createFails { throw CocoaError(.fileWriteUnknown) }
        let device = StandbyRecorder(url, failStart: startFails)
        self.device = device
        return device
    }, schedule: { [unowned self] _, callback in self.timer = callback; return {} })
    lazy var app = SecureProbe(recording: recording, pipeline: DictationPipeline { [unowned self] request in
        calls += 1
        if cloudFails { throw URLError(.networkConnectionLost) }
        let object: [String: Any] = request.url!.path.contains("multimodal")
            ? ["output": ["text": "睡前的一句话。"]]
            : ["choices": [["finish_reason": "stop", "message": ["content": "睡前的一句话。"]]]]
        return (try JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }, persistUsage: { _ in }, requestMicrophone: { [unowned self] callback in
        permissionCalls += 1
        if holdPermission { pendingPermission = callback } else { callback(allowed) }
    })
    var window: NSWindow?
    func setup(unlocked: Bool = true) {
        window = app.makeWindow()
        if unlocked { app.prepareWorkflowTest() }
    }
    func cleanup() {
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        window?.orderOut(nil)
    }
}

@main
@MainActor
struct SleepRecoveryRegression {
    static func pause() async { try? await Task.sleep(nanoseconds: 20_000_000) }
    static func finish(_ rig: StandbyRig) async {
        for _ in 0..<1000 {
            if !rig.app.workflowTestState.busy { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        fatalError("Workflow timeout")
    }
    static func main() async throws {
        _ = NSApplication.shared
        // AC-SEC-01 + AC-SLP-01: fail before recording, not after speaking.
        do {
            let rig = StandbyRig(); rig.setup(unlocked: false); defer { rig.cleanup() }
            rig.app.stopWorkflowTest(); await pause()
            precondition(!rig.recording.isRecording && rig.permissionCalls == 0 && rig.calls == 0)
            precondition(rig.app.workflowTestState.status.contains("Touch ID"))
            rig.app.prepareWorkflowTest(); rig.app.sleepWorkflowTest(); rig.app.wakeWorkflowTest()
            precondition(rig.app.unlockedWorkflowTest)
            rig.app.stopWorkflowTest(); await pause()
            precondition(rig.recording.isRecording)
            rig.app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            precondition(!rig.app.unlockedWorkflowTest)
        }
        // AC-SLP-02/03/04: sleep ends audio, stale timer/delegate + duplicate wake cannot double upload.
        do {
            let rig = StandbyRig(); rig.setup(); defer { rig.cleanup() }
            rig.app.stopWorkflowTest(); await pause()
            let oldTimer = rig.timer!, oldFinished = rig.device!.finished!
            let original = try Data(contentsOf: rig.recording.url)
            rig.app.sleepWorkflowTest(); rig.app.sleepWorkflowTest()
            precondition(!rig.recording.isRecording && rig.recording.completed != nil)
            precondition(rig.app.deferredWorkflowTest && rig.calls == 0)
            let kept = try Data(contentsOf: rig.recording.url); precondition(kept == original)
            oldTimer(); oldFinished(true)
            rig.app.stopWorkflowTest(); await pause(); precondition(rig.calls == 0)
            rig.app.wakeWorkflowTest(); rig.app.wakeWorkflowTest(); await finish(rig)
            precondition(rig.calls == 2 && rig.app.workflowTestState.result == "睡前的一句话。")
            precondition(!rig.app.deferredWorkflowTest && !rig.app.recoveryTestPending)
        }
        // AC-REC-01/02: all start failures preserve old bytes; successful Fn replaces exactly once.
        do {
            let rig = StandbyRig(); rig.setup(); defer { rig.cleanup() }
            rig.app.stopWorkflowTest(); await pause(); rig.app.stopWorkflowTest(); await finish(rig)
            let previousResult = rig.app.workflowTestState.result
            rig.cloudFails = true
            rig.app.stopWorkflowTest(); await pause(); rig.app.stopWorkflowTest(); await finish(rig)
            let oldURL = rig.recording.url, oldBytes = try Data(contentsOf: rig.recording.url)
            for mode in 0..<3 {
                rig.allowed = mode != 0; rig.createFails = mode == 1; rig.startFails = mode == 2
                rig.app.stopWorkflowTest(); await pause()
                precondition(!rig.recording.isRecording && rig.app.recoveryTestPending)
                let retained = try Data(contentsOf: oldURL); precondition(retained == oldBytes)
            }
            rig.allowed = true; rig.createFails = false; rig.startFails = false
            rig.app.stopWorkflowTest(); await pause()
            precondition(rig.recording.isRecording && rig.recording.url != oldURL)
            precondition(!FileManager.default.fileExists(atPath: oldURL.path))
            precondition(!rig.app.recoveryTestPending && rig.app.workflowTestState.result == previousResult)
            rig.cloudFails = false
            rig.app.stopWorkflowTest(); await finish(rig)
            precondition(rig.app.workflowTestState.result == "睡前的一句话。")
        }
        // AC-REC-03: permission callback arriving after sleep may not start a microphone.
        do {
            let rig = StandbyRig(); rig.setup(); defer { rig.cleanup() }
            rig.holdPermission = true; rig.app.stopWorkflowTest()
            rig.app.sleepWorkflowTest(); rig.pendingPermission?(true); await pause()
            precondition(!rig.recording.isRecording && rig.calls == 0)
            rig.app.wakeWorkflowTest(); await pause(); precondition(rig.calls == 0)
        }
        // Delete or actual exit invalidates the deferred recording.
        for exit in [false, true] {
            let rig = StandbyRig(); rig.setup(); defer { rig.cleanup() }
            rig.app.stopWorkflowTest(); await pause(); rig.app.sleepWorkflowTest()
            if exit { rig.app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
            else { rig.app.deleteWorkflowTest() }
            rig.app.wakeWorkflowTest(); await pause()
            precondition(rig.calls == 0 && !rig.app.deferredWorkflowTest && rig.recording.completed == nil)
        }
        // The inverse deadline/sleep race: a scheduled task canceled before sending cannot run later.
        do {
            let rig = StandbyRig(); rig.setup(); defer { rig.cleanup() }
            rig.app.stopWorkflowTest(); await pause()
            rig.timer?(); rig.app.sleepWorkflowTest(); rig.app.wakeWorkflowTest(); await pause()
            precondition(rig.calls == 0 && rig.app.recoveryTestPending)
        }
        // A failed wake upload is retained; further wake notifications never retry it.
        do {
            let rig = StandbyRig(); rig.setup(); defer { rig.cleanup() }
            rig.cloudFails = true
            rig.app.stopWorkflowTest(); await pause(); rig.app.sleepWorkflowTest()
            rig.app.wakeWorkflowTest(); await finish(rig)
            precondition(rig.calls == 1 && rig.app.recoveryTestPending)
            rig.app.sleepWorkflowTest(); rig.app.wakeWorkflowTest(); await pause()
            precondition(rig.calls == 1)
            rig.app.stopWorkflowTest(); await pause()
            precondition(rig.recording.isRecording && !rig.app.recoveryTestPending)
        }
        print("PASS: sleep/wake session, one deferred upload, duplicate/deadline races, transactional replacement failures/success, unlock gate, permission cancellation, deletion/exit invalidation, failed wake without automatic retry.")
    }
}

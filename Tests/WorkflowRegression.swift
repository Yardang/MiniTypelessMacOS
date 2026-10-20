import AppKit
import AVFoundation
import Foundation

@MainActor
final class FakeRecorder: RecordingDevice {
    var currentTime: TimeInterval
    var finished: ((Bool) -> Void)?
    var requestedDuration: TimeInterval?
    let url: URL
    init(url: URL, seconds: TimeInterval) { self.url = url; currentTime = seconds }
    func record(forDuration duration: TimeInterval) -> Bool {
        requestedDuration = duration
        let pcm = Data(repeating: 0, count: Int(currentTime * 32000))
        try! AudioChunks.encodePCM(pcm).write(to: url)
        return true
    }
    func stop() {}
}

@main
struct WorkflowRegression {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        // Complete ten-minute sample preservation, metadata padding, and size caps.
        let pcm = Data((0..<(600 * 32000)).map { UInt8(truncatingIfNeeded: $0) })
        let wav = AudioChunks.encodePCM(pcm)
        let chunks = try AudioChunks.split(wav)
        precondition(chunks.map(\.duration) == [240, 240, 120])
        precondition(chunks.allSatisfy { $0.wav.count < 10_000_000 })
        precondition(chunks.reduce(Data()) { $0 + $1.wav.dropFirst(44) } == pcm)
        var metadata = wav
        metadata.insert(contentsOf: Data([74, 85, 78, 75, 1, 0, 0, 0, 42, 0]), at: 12)
        let metadataChunks = try AudioChunks.split(metadata)
        precondition(metadataChunks.reduce(0) { $0 + $1.duration } == 600)
        for malformed in [Data(), Data(wav.prefix(40)), AudioChunks.encodePCM(Data([1])), AudioChunks.encodePCM(Data(repeating: 0, count: 600 * 32000 + 2))] {
            do { _ = try AudioChunks.split(malformed); fatalError("Accepted invalid audio") } catch {}
        }

        // Accept Apple's own WAV metadata/header layout without recording a microphone.
        let nativeURL = FileManager.default.temporaryDirectory.appendingPathComponent("MiniTypeless-native-test-\(UUID()).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        do {
            let file = try AVAudioFile(forWriting: nativeURL, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000)!
            buffer.frameLength = 16000
            memset(buffer.int16ChannelData![0], 0, 32000)
            try file.write(from: buffer)
        }
        let nativeChunks = try AudioChunks.split(Data(contentsOf: nativeURL))
        try FileManager.default.removeItem(at: nativeURL)
        precondition(nativeChunks.count == 1 && nativeChunks[0].duration == 1)

        let codex = InsertionDestination(pid: 10, bundleID: "com.openai.codex", name: "Codex")
        let own = InsertionDestination(pid: 20, bundleID: "com.minitypeless.app", name: "Mini Typeless")
        let other = InsertionDestination(pid: 30, bundleID: "md.obsidian", name: "Obsidian")
        let browser = InsertionDestination(pid: 40, bundleID: "test.browser", name: "Browser")
        precondition(InsertionDestinationPolicy.capture(current: own, started: codex, ownPID: 20) == codex)
        precondition(InsertionDestinationPolicy.capture(current: other, started: codex, ownPID: 20) == other)
        precondition(InsertionDestinationPolicy.decide(target: codex, current: codex, ownPID: 20) == .current)
        precondition(InsertionDestinationPolicy.decide(target: codex, current: own, ownPID: 20) == .restore(codex))
        for (target, current) in [(codex, other), (browser, browser)] {
            guard case .reject = InsertionDestinationPolicy.decide(target: target, current: current, ownPID: 20) else { fatalError("Unexpected redirect") }
        }
        guard case .reject = InsertionDestinationPolicy.decide(target: nil, current: codex, ownPID: 20) else { fatalError("Missing target") }

        // Drive the real app coordinator through its production stop callback and pipeline.
        for automatic in [false, true] {
            let rig = Rig(seconds: automatic ? 600 : 2)
            var requests: [URLRequest] = []
            var audioCalls = 0
            let pipeline = DictationPipeline { request in
                requests.append(request)
                if request.url!.path.contains("multimodal") {
                    audioCalls += 1
                    return response(request, object: ["output": ["text": "片段\(audioCalls)。"], "usage": ["input_tokens": 10, "output_tokens": 2]])
                }
                return response(request, object: ["choices": [["finish_reason": "stop", "message": ["content": (1...audioCalls).map { "片段\($0)。" }.joined(separator: "\n")]]]])
            }
            let logDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MiniTypeless-workflow-log-\(UUID())")
            defer { try? FileManager.default.removeItem(at: logDirectory) }
            let app = SecureProbe(recording: rig.controller, pipeline: pipeline, persistUsage: { _ in },
                                  diagnostics: DiagnosticLog(directory: logDirectory))
            let window = app.makeWindow()
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            app.prepareWorkflowTest()
            try rig.controller.start()
            precondition(rig.scheduledDuration == 600 && rig.device?.requestedDuration == 600)
            let lateDelegate = rig.device!.finished
            window.close()
            _ = app.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            precondition(rig.controller.isRecording, "Closing/reopening must not stop recording")
            if automatic { rig.fire!() } else { app.stopWorkflowTest() }
            window.close()
            _ = app.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            precondition(app.workflowTestState.busy, "Closing/reopening must not cancel processing")
            // A timer and AVAudioRecorder delegate can both report the same stop.
            lateDelegate?(true)
            rig.fire?()
            await settle(app)
            precondition(requests.count == (automatic ? 4 : 2))
            precondition(app.workflowTestState.result == (1...audioCalls).map { "片段\($0)。" }.joined(separator: "\n"))
            precondition(!FileManager.default.fileExists(atPath: rig.controller.url.path))
            let body = try JSONSerialization.jsonObject(with: requests.last!.httpBody!) as! [String: Any]
            precondition(body["max_tokens"] as! Int >= 1200)
            let finalResult = app.workflowTestState.result
            window.close()
            _ = app.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            precondition(app.workflowTestState.result == finalResult, "Closing/reopening must retain results")
            let logText = try String(contentsOf: logDirectory.appendingPathComponent("events.jsonl"), encoding: .utf8)
            let logEntries = try logText.split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
            precondition(logEntries.filter { $0["event"] as? String == "transcribing" }.count == audioCalls)
            precondition(logEntries.filter { $0["event"] as? String == "processingSucceeded" }.count == 1)
            precondition(!logText.contains("synthetic-test-key") && !logText.contains("片段"), "No key or transcript in persisted workflow log")
            window.orderOut(nil)
        }

        // Cancel/sleep in either network stage; even a transport that ignores
        // cancellation and returns success must not publish a completed result.
        for stage in ["asr", "refinement"] {
            for sleep in [false, true] {
                let rig = Rig(seconds: 2)
                var continuation: CheckedContinuation<(Data, URLResponse), Error>?
                var request: URLRequest?
                let app = SecureProbe(recording: rig.controller, pipeline: DictationPipeline { next in
                    if stage == "refinement", next.url!.path.contains("multimodal") {
                        return response(next, object: ["output": ["text": "已完成的原始转写"]])
                    }
                    request = next
                    return try await withCheckedThrowingContinuation { continuation = $0 }
                }, persistUsage: { _ in })
                let window = app.makeWindow(); app.prepareWorkflowTest()
                try rig.controller.start(); app.stopWorkflowTest()
                for _ in 0..<1000 {
                    if continuation != nil { break }
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                precondition(continuation != nil, "Mock request never reached suspended stage")
                if sleep {
                    app.sleepWorkflowTest()
                    precondition(app.unlockedWorkflowTest)
                    app.wakeWorkflowTest()
                } else { app.cancelWorkflowTest() }
                let late: [String: Any] = stage == "asr"
                    ? ["output": ["text": "迟到内容"]]
                    : ["choices": [["finish_reason": "stop", "message": ["content": "迟到整理结果"]]]]
                continuation!.resume(returning: response(request!, object: late))
                try await Task.sleep(nanoseconds: 20_000_000)
                precondition(!app.workflowTestState.busy && app.workflowTestState.result == nil)
                precondition(app.workflowTestState.raw == (stage == "asr" ? nil : "已完成的原始转写"))
                precondition(FileManager.default.fileExists(atPath: rig.controller.url.path))
                precondition(app.recoveryTestPending)
                app.deleteWorkflowTest()
                window.orderOut(nil)
            }
        }

        // A canceled old operation returns after a newer dictation has succeeded.
        // Its response must not overwrite the new result or restore the old UI state.
        do {
            let rig = Rig(seconds: 2)
            var oldContinuation: CheckedContinuation<(Data, URLResponse), Error>?
            var oldRequest: URLRequest?
            var calls = 0
            let app = SecureProbe(recording: rig.controller, pipeline: DictationPipeline { request in
                calls += 1
                if calls == 1 {
                    oldRequest = request
                    return try await withCheckedThrowingContinuation { oldContinuation = $0 }
                }
                if request.url!.path.contains("multimodal") {
                    return response(request, object: ["output": ["text": "新一轮录音。"]])
                }
                return response(request, object: ["choices": [["finish_reason": "stop", "message": ["content": "新一轮录音。"]]]])
            }, persistUsage: { _ in })
            let window = app.makeWindow(); app.prepareWorkflowTest()
            try rig.controller.start(); app.stopWorkflowTest()
            for _ in 0..<1000 {
                if oldContinuation != nil { break }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            precondition(oldContinuation != nil)
            app.cancelWorkflowTest()
            app.deleteWorkflowTest()
            try rig.controller.start(); app.stopWorkflowTest()
            await settle(app)
            precondition(app.workflowTestState.result == "新一轮录音。")
            let finalStatus = app.workflowTestState.status
            oldContinuation!.resume(returning: response(oldRequest!, object: ["output": ["text": "旧录音的迟到结果"]]))
            try await Task.sleep(nanoseconds: 20_000_000)
            precondition(!app.workflowTestState.busy && calls == 3)
            precondition(app.workflowTestState.raw == "新一轮录音。" && app.workflowTestState.result == "新一轮录音。")
            precondition(app.workflowTestState.status == finalStatus)
            window.orderOut(nil)
        }

        // Reproduce -1005 with a 90.4-second take. The full WAV survives ASR
        // and refinement failures, sleep and failed retries; only success/delete
        // clears it. Retry output is retained without reusing the old destination.
        for failureStage in ["asr", "refinement"] {
            let rig = Rig(seconds: 90.4)
            var phase = 0
            var calls = 0
            var uploaded: [Data] = []
            let app = SecureProbe(recording: rig.controller, pipeline: DictationPipeline { request in
                calls += 1
                let isASR = request.url!.path.contains("multimodal")
                if isASR { uploaded.append(request.httpBody!) }
                if phase == 1 && ((failureStage == "asr" && isASR) || (failureStage == "refinement" && !isASR)) {
                    throw URLError(.networkConnectionLost)
                }
                if phase == 2 { throw URLError(.timedOut) }
                let text = phase == 0 ? "此前成功结果。" : "本次恢复结果。"
                if isASR { return response(request, object: ["output": ["text": text]]) }
                return response(request, object: ["choices": [["finish_reason": "stop", "message": ["content": text]]]])
            }, persistUsage: { _ in })
            let window = app.makeWindow(); app.prepareWorkflowTest()
            try rig.controller.start(); app.stopWorkflowTest(); await settle(app)
            phase = 1
            try rig.controller.start()
            let original = try Data(contentsOf: rig.controller.url)
            app.stopWorkflowTest(); await settle(app)
            precondition(app.recoveryTestPending && app.workflowTestState.status.contains("-1005"))
            precondition(app.workflowTestState.result == "此前成功结果。")
            let rawBeforeRetry = app.workflowTestState.raw
            let failedCalls = calls
            try await Task.sleep(nanoseconds: 20_000_000)
            precondition(calls == failedCalls, "Unexpected automatic retry")
            // Direct controller callers must explicitly opt in to replacement.
            do { try rig.controller.start(); fatalError("Overwrote a recoverable take") }
            catch let error as CocoaError { precondition(error.code == .fileWriteFileExists) }
            let retained = try Data(contentsOf: rig.controller.url)
            precondition(retained == original)
            let exported = FileManager.default.temporaryDirectory.appendingPathComponent("MiniTypeless-export-test-\(UUID()).wav")
            let invalidExport = exported.appendingPathComponent("missing/recording.wav")
            do { try rig.controller.exportCompleted(to: invalidExport); fatalError("Invalid export unexpectedly succeeded") }
            catch { precondition(FileManager.default.fileExists(atPath: rig.controller.url.path)) }
            try rig.controller.exportCompleted(to: exported)
            let exportedBytes = try Data(contentsOf: exported)
            precondition(exportedBytes == original)
            app.sleepWorkflowTest()
            precondition(rig.controller.completed != nil && app.recoveryTestPending)
            app.retryWorkflowTest() // No upload while asleep.
            precondition(calls == failedCalls)
            precondition(app.unlockedWorkflowTest)
            app.wakeWorkflowTest() // Failed requests are not automatically replayed.
            precondition(calls == failedCalls)
            phase = 2
            app.retryWorkflowTest(); await settle(app)
            precondition(app.recoveryTestPending && app.workflowTestState.raw == rawBeforeRetry)
            phase = 3
            app.retryWorkflowTest(); await settle(app)
            precondition(app.workflowTestState.result == "本次恢复结果。")
            precondition(app.workflowTestState.status.contains("重试成功"))
            precondition(!app.recoveryTestPending && rig.controller.completed == nil)
            precondition(!FileManager.default.fileExists(atPath: rig.controller.url.path))
            // JSON key order is unspecified; compare the decoded audio payload.
            let bodies = try uploaded.map { try JSONSerialization.jsonObject(with: $0) as! NSDictionary }
            precondition(bodies.allSatisfy { $0.isEqual(bodies[0]) })
            precondition(FileManager.default.fileExists(atPath: exported.path))
            try FileManager.default.removeItem(at: exported)
            window.orderOut(nil)
        }

        do {
            let rig = Rig(seconds: 1)
            let app = SecureProbe(recording: rig.controller,
                pipeline: DictationPipeline { _ in throw URLError(.networkConnectionLost) }, persistUsage: { _ in })
            let window = app.makeWindow(); app.prepareWorkflowTest()
            try rig.controller.start(); app.stopWorkflowTest(); await settle(app)
            precondition(FileManager.default.fileExists(atPath: rig.controller.url.path))
            app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            precondition(!FileManager.default.fileExists(atPath: rig.controller.url.path))
            window.orderOut(nil)
        }

        // Partial ASR failure preserves available text and never sends it to refinement.
        var calls = 0
        var partial = ""
        let failurePipeline = DictationPipeline { request in
            calls += 1
            return response(request, status: calls == 1 ? 200 : 500, object: ["output": ["text": "第一段"]])
        }
        do {
            _ = try await failurePipeline.run(chunks: chunks, key: "synthetic", prompt: "test") { event in
                if case .raw(let text) = event { partial = text }
            }
            fatalError("Accepted partial ASR")
        } catch DictationFailure.chunk {} catch { fatalError("Wrong ASR failure") }
        precondition(calls == 2 && partial == "第一段")

        // Reproduce the reported partial-ASR + HTTP 400 CLIENT_ERROR path in the
        // real coordinator. The third chunk is chosen for this fixture only;
        // the screenshot does not establish the actual failed chunk or cause.
        do {
            let rig = Rig(seconds: 600)
            var failing = false
            var audioCalls = 0
            var refinementCalls = 0
            let pipeline = DictationPipeline { request in
                if request.url!.path.contains("multimodal") {
                    audioCalls += 1
                    if failing && audioCalls == 3 {
                        return response(request, status: 400, object: [
                            "code": "CLIENT_ERROR", "message": "Synthetic unspecified rejection",
                            "request_id": "synthetic-partial-asr-400"
                        ])
                    }
                    return response(request, object: ["output": ["text": failing ? "本次片段\(audioCalls)" : "此前结果"]])
                }
                refinementCalls += 1
                return response(request, object: ["choices": [["finish_reason": "stop", "message": ["content": "此前成功结果"]]]])
            }
            let app = SecureProbe(recording: rig.controller, pipeline: pipeline, persistUsage: { _ in })
            let window = app.makeWindow()
            app.prepareWorkflowTest()
            try rig.controller.start()
            rig.fire!()
            await settle(app)
            precondition(app.workflowTestState.result == "此前成功结果" && refinementCalls == 1)
            failing = true
            audioCalls = 0
            try rig.controller.start()
            rig.fire!()
            await settle(app)
            precondition(audioCalls == 3 && refinementCalls == 1)
            precondition(app.workflowTestState.raw == "本次片段1\n本次片段2")
            precondition(app.workflowTestState.result == "此前成功结果")
            precondition(app.workflowTestState.status.contains("HTTP 400"))
            precondition(app.workflowTestState.status.contains("转写片段 3/3（120.0 秒）"))
            precondition(app.workflowTestState.status.contains("Synthetic unspecified rejection"))
            precondition(app.workflowTestState.status.contains("CLIENT_ERROR"))
            precondition(app.workflowTestState.status.contains("synthetic-partial-asr-400"))
            precondition(FileManager.default.fileExists(atPath: rig.controller.url.path))
            precondition(app.recoveryTestPending)
            app.deleteWorkflowTest()
            window.orderOut(nil)
        }

        // An HTTP 200 empty-text response must not discard neighboring speech.
        // This fixture does not establish how the live service handles silence.
        var silenceCalls = 0
        let silence = DictationPipeline { request in
            silenceCalls += 1
            if request.url!.path.contains("multimodal") {
                return response(request, object: ["output": ["text": silenceCalls == 2 ? "" : "有声音。"]])
            }
            return response(request, object: ["choices": [["finish_reason": "stop", "message": ["content": "有声音。\n有声音。"]]]])
        }
        let silenceResult = try await silence.run(chunks: chunks, key: "synthetic", prompt: "test") { _ in }
        precondition(silenceResult.raw == "有声音。\n有声音。" && silenceCalls == 4)

        // Real coordinator: a trailing no-words chunk completes the dictation;
        // a subsequent all-empty recording preserves that successful result.
        do {
            let rig = Rig(seconds: 600)
            var allEmpty = false
            var asrCalls = 0
            var refinementCalls = 0
            let expected = "片段1。\n片段2。"
            let pipeline = DictationPipeline { request in
                if request.url!.path.contains("multimodal") {
                    asrCalls += 1
                    if allEmpty || asrCalls == 3 {
                        return response(request, status: 400, object: ["code": "CLIENT_ERROR", "message": "ASR_RESPONSE_HAVE_NO_WORDS"])
                    }
                    return response(request, object: ["output": ["text": "片段\(asrCalls)。"]])
                }
                refinementCalls += 1
                return response(request, object: ["choices": [["finish_reason": "stop", "message": ["content": expected]]]])
            }
            let app = SecureProbe(recording: rig.controller, pipeline: pipeline, persistUsage: { _ in })
            let window = app.makeWindow()
            app.prepareWorkflowTest()
            try rig.controller.start()
            rig.fire!()
            await settle(app)
            precondition(asrCalls == 3 && refinementCalls == 1)
            precondition(app.workflowTestState.result == expected && app.workflowTestState.raw == expected)
            allEmpty = true
            try rig.controller.start()
            rig.fire!()
            await settle(app)
            precondition(asrCalls == 6 && refinementCalls == 1)
            precondition(app.workflowTestState.result == expected && app.workflowTestState.raw == nil)
            precondition(app.workflowTestState.status.contains("未识别到可转写的文字"))
            precondition(!app.workflowTestState.status.contains("HTTP 400"))
            precondition(app.recoveryTestPending)
            app.deleteWorkflowTest()
            window.orderOut(nil)
        }

        // Synthetic diagnostics keep real results intact. Cancellation/sleep
        // invalidates late responses and prevents the remaining probe requests.
        for mode in ["complete", "cancel", "sleep"] {
            let rig = Rig(seconds: 2)
            var diagnostic = false
            var held: CheckedContinuation<(Data, URLResponse), Error>?
            var heldRequest: URLRequest?
            var calls = 0
            let pipeline = DictationPipeline { request in
                calls += 1
                if diagnostic && heldRequest == nil {
                    heldRequest = request
                    return try await withCheckedThrowingContinuation { held = $0 }
                }
                if request.url!.path.contains("multimodal") {
                    return response(request, object: ["output": ["text": "保留的录音结果。"]])
                }
                precondition(!diagnostic, "Diagnostic must not refine")
                return response(request, object: ["choices": [["finish_reason": "stop", "message": ["content": "保留的录音结果。"]]]])
            }
            let app = SecureProbe(recording: rig.controller, pipeline: pipeline, persistUsage: { _ in })
            let window = app.makeWindow()
            app.prepareWorkflowTest()
            try rig.controller.start()
            app.stopWorkflowTest()
            await settle(app)
            let previous = app.workflowTestState
            diagnostic = true
            let reportURL = FileManager.default.temporaryDirectory.appendingPathComponent("MiniTypeless-diagnostic-regression-\(UUID()).txt")
            let testCase = ASRDiagnosticCase(name: "合成测试", audio: chunks[2])
            app.startDiagnosticTest(cases: [testCase, testCase], reportURL: reportURL)
            for _ in 0..<1000 {
                if held != nil { break }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            precondition(held != nil && calls == 3)
            if mode == "cancel" { app.cancelWorkflowTest() }
            if mode == "sleep" { app.sleepWorkflowTest() }
            let reportAtCancel = app.diagnosticTestReport
            held!.resume(returning: response(heldRequest!, status: 400, object: ["code": "CLIENT_ERROR", "message": "synthetic-test-key late diagnostic detail"]))
            if mode == "complete" { await settle(app) }
            else { try await Task.sleep(nanoseconds: 20_000_000) }
            precondition(!app.workflowTestState.busy)
            precondition(app.workflowTestState.result == previous.result && app.workflowTestState.raw == previous.raw)
            precondition(calls == (mode == "complete" ? 4 : 3))
            precondition(!app.diagnosticTestReport.contains("synthetic-test-key"))
            if mode != "complete" { precondition(app.diagnosticTestReport == reportAtCancel) }
            let savedReport = try String(contentsOf: reportURL, encoding: .utf8)
            precondition(savedReport == app.diagnosticTestReport)
            try FileManager.default.removeItem(at: reportURL)
            window.orderOut(nil)
        }

        // Token-truncated refinement is not a successful dictation result.
        let truncation = DictationPipeline { request in
            if request.url!.path.contains("multimodal") { return response(request, object: ["output": ["text": String(repeating: "长录音。", count: 1000)]]) }
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            precondition(body["max_tokens"] as! Int > 1200)
            return response(request, object: ["choices": [["finish_reason": "length", "message": ["content": "不完整"]]]])
        }
        do {
            _ = try await truncation.run(chunks: [chunks[0]], key: "synthetic", prompt: "test") { _ in }
            fatalError("Accepted truncated refinement")
        } catch DictationFailure.incompleteRefinement {} catch { fatalError("Wrong refinement failure") }

        // Discard is used for delete/sleep; it must not accidentally trigger an upload.
        let discarded = Rig(seconds: 1)
        var completions = 0
        discarded.controller.onStopped = { _, _ in completions += 1 }
        try discarded.controller.start()
        let oldTimer = discarded.fire!
        let oldDelegate = discarded.device!.finished!
        discarded.controller.discard()
        try discarded.controller.start()
        oldTimer(); oldDelegate(true)
        precondition(discarded.controller.isRecording && completions == 0)
        discarded.controller.discard()
        print("PASS: 10-minute audio, real stop-to-result workflow, duplicate stop, cancel/sleep in both stages, old response after newer success, partial failure including HTTP 400 CLIENT_ERROR, truncation, target routing, stale callbacks.")
    }

    @MainActor
    static func settle(_ app: SecureProbe) async {
        for _ in 0..<1000 {
            if !app.workflowTestState.busy { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        fatalError("Workflow did not finish")
    }

    static func response(_ request: URLRequest, status: Int = 200, object: [String: Any]) -> (Data, URLResponse) {
        (try! JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
final class Rig {
    var device: FakeRecorder?
    var fire: (@MainActor () -> Void)?
    var scheduledDuration: TimeInterval?
    let seconds: TimeInterval
    lazy var controller = RecordingController(makeDevice: { [unowned self] url in
        let device = FakeRecorder(url: url, seconds: self.seconds)
        self.device = device
        return device
    }, schedule: { [unowned self] duration, action in
        self.scheduledDuration = duration
        self.fire = action
        return {}
    })
    init(seconds: TimeInterval) { self.seconds = seconds }
}

import Foundation

@main
struct NoSpeechRegression {
    static let empty: [String: Any] = ["code": "CLIENT_ERROR", "message": "ASR_RESPONSE_HAVE_NO_WORDS", "request_id": "synthetic-no-words"]

    static func response(_ request: URLRequest, _ http: Int, _ object: [String: Any]) -> (Data, URLResponse) {
        (try! JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: request.url!, statusCode: http, httpVersion: nil, headerFields: nil)!)
    }

    @MainActor
    static func main() async throws {
        let data = try JSONSerialization.data(withJSONObject: empty)
        precondition(ServiceDiagnostic(http: 400, data: data, key: "synthetic").isEmptyASRResponse)
        for http in [200, 401, 403, 429, 500] {
            precondition(!ServiceDiagnostic(http: http, data: data, key: "synthetic").isEmptyASRResponse)
        }
        for object: [String: Any] in [
            ["code": "OTHER_ERROR", "message": "ASR_RESPONSE_HAVE_NO_WORDS"],
            ["code": "CLIENT_ERROR", "message": "prefix ASR_RESPONSE_HAVE_NO_WORDS"],
            ["code": "CLIENT_ERROR", "message": "ASR_RESPONSE_HAVE_NO_WORDS with another error"],
            ["code": "CLIENT_ERROR"],
            ["message": "ASR_RESPONSE_HAVE_NO_WORDS"],
            ["code": "CLIENT_ERROR", "message": "ASR_RESPONSE_HAVE_NO_WORDS", "output": ["text": "contradictory text"]]
        ] {
            let rejectedData = try JSONSerialization.data(withJSONObject: object)
            precondition(!ServiceDiagnostic(http: 400, data: rejectedData, key: "synthetic").isEmptyASRResponse)
        }
        let audio = AudioChunk(wav: AudioChunks.encodePCM(Data(repeating: 1, count: 32000)), duration: 1)
        let chunks = [audio, audio, audio]
        // The cloud-reported empty chunk may occur anywhere. Every other chunk
        // reaches refinement exactly once and in its original order.
        for emptyIndex in 1...3 {
            var calls = 0
            var refining = 0
            var emptyEvents: [Int] = []
            let expected = (1...3).filter { $0 != emptyIndex }.map { "片段\($0)。" }.joined(separator: "\n")
            let pipeline = DictationPipeline { request in
                calls += 1
                if calls <= 3 {
                    return calls == emptyIndex ? response(request, 400, empty)
                        : response(request, 200, ["output": ["text": "片段\(calls)。"]])
                }
                precondition(request.url!.path.contains("chat/completions"))
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                let messages = body["messages"] as! [[String: String]]
                precondition(messages[1]["content"]!.contains(expected))
                return response(request, 200, ["choices": [["finish_reason": "stop", "message": ["content": expected]]]])
            }
            let result = try await pipeline.run(chunks: chunks, key: "synthetic", prompt: "test") { event in
                if case .emptyChunk(let index, let total) = event { precondition(total == 3); emptyEvents.append(index) }
                if case .refining = event { refining += 1 }
            }
            precondition(calls == 4 && refining == 1 && emptyEvents == [emptyIndex])
            precondition(result.raw == expected && result.refined == expected)
        }

        // Entirely empty dictation (including a mix of HTTP 200 and the observed
        // HTTP 400 signature) ends without any refinement request.
        var allEmptyCalls = 0
        let allEmpty = DictationPipeline { request in
            allEmptyCalls += 1
            return allEmptyCalls == 2 ? response(request, 200, ["output": ["text": " \n"]])
                : response(request, 400, empty)
        }
        do {
            _ = try await allEmpty.run(chunks: chunks, key: "synthetic", prompt: "test") { _ in }
            fatalError("All-empty audio became a successful result")
        } catch DictationFailure.noSpeech {} catch { fatalError("Wrong all-empty outcome") }
        precondition(allEmptyCalls == 3)

        // A recognized empty chunk cannot conceal a later unrelated error.
        var calls = 0
        var partial = ""
        let unknown = DictationPipeline { request in
            calls += 1
            if calls == 1 { return response(request, 200, ["output": ["text": "已有语音"]]) }
            return response(request, 400, calls == 2 ? empty : ["code": "CLIENT_ERROR", "message": "request timeout"])
        }
        do {
            _ = try await unknown.run(chunks: chunks, key: "synthetic", prompt: "test") { event in
                if case .raw(let text) = event { partial = text }
            }
            fatalError("Unknown error was ignored")
        } catch DictationFailure.chunk(let context, _) { precondition(context.index == 3) }
        precondition(calls == 3 && partial == "已有语音")

        // This exception belongs only to ASR, never to the refinement endpoint.
        var refinementCalls = 0
        let refinementFailure = DictationPipeline { request in
            refinementCalls += 1
            return refinementCalls == 1 ? response(request, 200, ["output": ["text": "有声音"]])
                : response(request, 400, empty)
        }
        do {
            _ = try await refinementFailure.run(chunks: [audio], key: "synthetic", prompt: "test") { _ in }
            fatalError("Refinement error was ignored")
        } catch DictationFailure.response(let stage, _) { precondition(stage == "整理") }

        // Diagnostic output must keep the original HTTP 400 and reason, rather
        // than relabeling a tolerated no-words response as HTTP 200 success.
        var report = ""
        try await ASRDiagnosticRunner(pipeline: allEmpty).run(cases: [ASRDiagnosticCase(name: "静音", audio: audio)], key: "synthetic") { event in
            if case .line(let line) = event { report += line }
        }
        precondition(report.contains("已识别为无文字片段") && report.contains("HTTP 400") && report.contains("ASR_RESPONSE_HAVE_NO_WORDS"))

        // Cancellation still wins over a late, otherwise-tolerated no-words reply.
        var held: CheckedContinuation<(Data, URLResponse), Error>?
        var heldRequest: URLRequest?
        var lateCalls = 0
        let latePipeline = DictationPipeline { request in
            lateCalls += 1
            heldRequest = request
            return try await withCheckedThrowingContinuation { held = $0 }
        }
        let task = Task { try await latePipeline.run(chunks: chunks, key: "synthetic", prompt: "test") { _ in } }
        while held == nil { await Task.yield() }
        task.cancel()
        held!.resume(returning: response(heldRequest!, 400, empty))
        do { _ = try await task.value; fatalError("Canceled no-words reply continued") }
        catch is CancellationError {}
        precondition(lateCalls == 1)
        print("PASS: exact no-words signature, empty chunk at every position, all-empty audio, unrelated/refinement failures, honest diagnostics, cancellation of late no-words response.")
    }
}

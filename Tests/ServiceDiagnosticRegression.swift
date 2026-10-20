import Foundation

@main
struct ServiceDiagnosticRegression {
    @MainActor
    static func main() async throws {
        let key = "synthetic-private-key-123"
        func diagnostic(_ object: [String: Any], http: Int = 400) -> ServiceDiagnostic {
            ServiceDiagnostic(http: http, data: try! JSONSerialization.data(withJSONObject: object), key: key)
        }
        let top = diagnostic(["code": "CLIENT_ERROR", "request_id": "test-request-123",
                              "message": "No valid audio fragment found"])
        precondition(top.code == "CLIENT_ERROR" && top.requestID == "test-request-123")
        precondition(top.message == "No valid audio fragment found")
        let nested = diagnostic(["error": ["code": "InvalidInput", "message": "request timeout after 23 seconds."]])
        precondition(nested.message == "request timeout after 23 seconds.")
        let alternative = diagnostic(["error_message": "empty audio", "request_id": "not a valid id"])
        precondition(alternative.message == "empty audio" && alternative.requestID == nil)
        let dangerous = diagnostic(["code": key, "request_id": key,
            "message": "No speech; \(key) Bearer other-secret api_key=another-secret sk-othersecret https://example.invalid/?token=secret data:audio/wav;base64,UklGRmF1ZGlv \(String(repeating: "A", count: 100))\nnext\u{001B}"])
        let displayed = dangerous.summary
        for secret in [key, "other-secret", "another-secret", "sk-othersecret", "example.invalid", "UklGRmF1ZGlv", String(repeating: "A", count: 100), "\u{001B}"] {
            precondition(!displayed.contains(secret), "Diagnostic leaked a sensitive field")
        }
        precondition(displayed.contains("No speech") && displayed.contains("next"))
        precondition(diagnostic(["message": String(repeating: "文字 ", count: 1000)]).message!.count < 520)
        precondition(ServiceDiagnostic(http: 502, data: Data("<html>secret</html>".utf8), key: key).message == nil)
        precondition(ServiceDiagnostic(http: 400, data: Data(repeating: 65, count: 70_000), key: key).message == nil)
        let wrapped = DictationFailure.chunk(ASRChunkContext(index: 3, total: 3, seconds: 120),
            DictationFailure.response("转写", top))
        precondition(DictationFailure.describe(wrapped).contains("片段 3/3（120.0 秒）"))
        precondition(DictationFailure.describe(wrapped).contains("No valid audio"))
        let timeout = DictationFailure.chunk(ASRChunkContext(index: 2, total: 3, seconds: 240),
            DictationFailure.transport("转写", URLError(.timedOut)))
        precondition(DictationFailure.describe(timeout).contains("等待超时"))

        let source = try Data(contentsOf: URL(fileURLWithPath: "MiniTypelessSecure/Resources/DiagnosticSpeech.wav"))
        let cases = try ASRDiagnosticCase.standard(speechWAV: source)
        precondition(cases.count == 3 && cases[1].audio.duration == 120 && cases[2].audio.duration == 240)
        precondition(cases[1].audio.wav.dropFirst(44).allSatisfy { $0 == 0 })
        let speechPCM = Data(cases[0].audio.wav.dropFirst(44))
        let spacedPCM = Data(cases[2].audio.wav.dropFirst(44))
        precondition(speechPCM.contains { $0 != 0 })
        precondition(spacedPCM.subdata(in: 32000..<(32000 + speechPCM.count)) == speechPCM)
        precondition(spacedPCM.subdata(in: (180 * 32000)..<(180 * 32000 + speechPCM.count)) == speechPCM)
        precondition(spacedPCM[(32000 + speechPCM.count)..<(180 * 32000)].allSatisfy { $0 == 0 })

        var calls = 0
        var lines: [String] = []
        var usageSeconds: [Double] = []
        let pipeline = DictationPipeline { request in
            calls += 1
            precondition(request.url!.path.contains("multimodal-generation"), "Probe called refinement")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
            precondition(request.value(forHTTPHeaderField: "X-DashScope-SSE") == "disable")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            precondition(body["model"] as! String == "qwen-audio-3.1-asr-flash")
            let rejected = calls == 2
            let object: [String: Any] = rejected
                ? ["code": "CLIENT_ERROR", "message": "synthetic unknown rejection \(key)"]
                : ["output": ["text": "Synthetic transcript must not be in report"]]
            return (try JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: request.url!, statusCode: rejected ? 400 : 200, httpVersion: nil, headerFields: nil)!)
        }
        try await ASRDiagnosticRunner(pipeline: pipeline).run(cases: cases, key: key) { event in
            switch event {
            case .line(let line): lines.append(line)
            case .usage(_, let seconds): usageSeconds.append(seconds)
            }
        }
        let report = lines.joined(separator: "\n")
        precondition(calls == 3 && lines.count == 6 && usageSeconds == [cases[0].audio.duration, 240])
        precondition(report.contains("CLIENT_ERROR") && report.contains("120.0 秒"))
        precondition(!report.contains(key) && !report.contains("Synthetic transcript"))
        print("PASS: error context, diagnostic redaction, malformed responses, synthetic audio integrity, three ASR-only probes, no transcript or key in report.")
    }
}

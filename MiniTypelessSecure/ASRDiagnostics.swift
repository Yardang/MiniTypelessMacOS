#if DEBUG
import Foundation

struct ASRDiagnosticCase {
    let name: String
    let audio: AudioChunk

    static func standard(speechWAV: Data) throws -> [ASRDiagnosticCase] {
        let speech = try AudioChunks.split(speechWAV)
        guard speech.count == 1, speech[0].duration > 0, speech[0].duration < 15 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let pcm = Data(speech[0].wav.dropFirst(44))
        var spaced = Data(repeating: 0, count: 240 * 32000)
        // The same public synthetic phrase near the beginning and after a long
        // silent gap, with additional trailing silence. No microphone input.
        spaced.replaceSubrange(32000..<(32000 + pcm.count), with: pcm)
        spaced.replaceSubrange((180 * 32000)..<(180 * 32000 + pcm.count), with: pcm)
        return [
            ASRDiagnosticCase(name: "短语音对照", audio: speech[0]),
            ASRDiagnosticCase(name: "120 秒纯静音", audio: AudioChunk(
                wav: AudioChunks.encodePCM(Data(repeating: 0, count: 120 * 32000)), duration: 120)),
            ASRDiagnosticCase(name: "240 秒语音与长静音间隔", audio: AudioChunk(
                wav: AudioChunks.encodePCM(spaced), duration: 240))
        ]
    }
}

enum ASRDiagnosticEvent {
    case line(String)
    case usage([String: Any], TimeInterval)
}

@MainActor
struct ASRDiagnosticRunner {
    let pipeline: DictationPipeline

    func run(cases: [ASRDiagnosticCase], key: String,
             onEvent: (ASRDiagnosticEvent) -> Void) async throws {
        for (index, item) in cases.enumerated() {
            try Task.checkCancellation()
            onEvent(.line("开始 \(index + 1)/\(cases.count)：\(item.name)（\(String(format: "%.1f", item.audio.duration)) 秒）"))
            let started = Date()
            let outcome: String
            do {
                let transcript = try await pipeline.transcribe(chunk: item.audio, key: key,
                    context: ASRChunkContext(index: index + 1, total: cases.count, seconds: item.audio.duration)) { event in
                        if case .usage(let object, _, let seconds) = event { onEvent(.usage(object, seconds)) }
                    }
                switch transcript {
                case .text(let text):
                    outcome = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "HTTP 200，返回空文字" : "HTTP 200，返回 \(text.count) 字（识别内容不写入报告）"
                case .noWords(let diagnostic):
                    outcome = "已识别为无文字片段；正常录音会继续处理其他片段。云端原始状态：\(diagnostic.summary)"
                }
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                outcome = DictationFailure.describe(error)
            }
            try Task.checkCancellation()
            onEvent(.line("结果：\(outcome)；请求耗时 \(String(format: "%.1f", Date().timeIntervalSince(started))) 秒\n"))
        }
    }
}
#endif

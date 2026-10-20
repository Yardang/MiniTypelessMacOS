import Foundation

/// Only selected, redacted error fields leave the HTTP layer. Never retain a
/// request body, authorization header, audio payload, or entire server response.
struct ServiceDiagnostic {
    let http: Int
    let code: String?
    let requestID: String?
    let message: String?
    let isEmptyASRResponse: Bool

    init(http: Int, data: Data, key: String) {
        self.http = http
        let object = data.count <= 65_536
            ? (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) : nil
        let error = object?["error"] as? [String: Any]
        code = Self.identifier(error?["code"] ?? object?["code"], key: key)
        requestID = Self.identifier(object?["request_id"], key: key)
        let detail = error?["message"] as? String ?? error?["error_message"] as? String
            ?? object?["message"] as? String ?? object?["error_message"] as? String
        message = detail.map { Self.redact($0, key: key) }.flatMap { $0.isEmpty ? nil : $0 }
        // Match the exact signature observed with qwen-audio-3.1-asr-flash.
        // Do not classify generic CLIENT_ERROR or substring matches as silence.
        let output = object?["output"] as? [String: Any]
        let hasText = (output?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        isEmptyASRResponse = http == 400 && code == "CLIENT_ERROR" && !hasText
            && detail?.trimmingCharacters(in: .whitespacesAndNewlines) == "ASR_RESPONSE_HAVE_NO_WORDS"
    }

    private static func identifier(_ value: Any?, key: String) -> String? {
        guard let text = value as? String, !text.isEmpty, text.count <= 80,
              key.isEmpty || !text.contains(key),
              text.unicodeScalars.allSatisfy({ CharacterSet(charactersIn:
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) }) else { return nil }
        return text
    }

    static func redact(_ value: String, key: String) -> String {
        var text = value
        if !key.isEmpty { text = text.replacingOccurrences(of: key, with: "[已隐藏密钥]") }
        // Redact before truncating, so a cut-off credential cannot survive.
        for pattern in [
            #"(?i)data:[^\s\"'<>]+"#,
            #"(?i)https?://[^\s\"'<>]+"#,
            #"(?i)\bbearer\s+[^\s,;\"']+"#,
            #"(?i)\b(?:api[_ -]?key|authorization|access[_ -]?token)\b\s*[:=]\s*[\"']?[^,\s;\"']+"#,
            #"(?i)\bsk-[a-z0-9_-]+"#,
            #"[A-Za-z0-9+/=_-]{64,}"#
        ] {
            text = text.replacingOccurrences(of: pattern, with: "[已隐藏]", options: .regularExpression)
        }
        text = String(text.unicodeScalars.map { scalar -> Character in
            if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return " "
            }
            return Character(scalar)
        })
        text = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return text.count > 500 ? String(text.prefix(500)) + "…（已截短）" : text
    }

    var summary: String {
        let reason: String
        switch http {
        case 400: reason = "云端拒绝了请求"
        case 401, 403: reason = "认证或访问权限被拒绝"
        case 429: reason = "请求过于频繁或额度受限"
        case 500...599: reason = "云端服务暂时不可用"
        default: reason = "服务未返回可用文字"
        }
        var fields = ["HTTP \(http)"]
        if let code { fields.append("错误代码：\(code)") }
        if let requestID { fields.append("请求 ID：\(requestID)") }
        let detail = message.map { "；云端说明：\($0)" } ?? "；云端未提供可显示的详细说明"
        return "\(reason)（\(fields.joined(separator: "，"))）\(detail)"
    }
}

struct ASRChunkContext {
    let index: Int
    let total: Int
    let seconds: TimeInterval
    var summary: String { String(format: "转写片段 %d/%d（%.1f 秒）", index, total, seconds) }
}

extension DictationFailure {
    static func describe(_ error: Error) -> String {
        switch error {
        case DictationFailure.chunk(let context, let underlying):
            return "\(context.summary)：\(describe(underlying))"
        case DictationFailure.response(let stage, let diagnostic):
            return "\(stage)失败：\(diagnostic.summary)"
        case DictationFailure.transport(let stage, let underlying):
            let code = (underlying as? URLError)?.code
            let reason: String
            switch code {
            case .timedOut: reason = "等待超时"
            case .networkConnectionLost: reason = "连接在请求过程中中断"
            case .notConnectedToInternet: reason = "当前没有网络连接"
            default: reason = "网络请求失败"
            }
            return "\(stage)\(reason)（系统代码 \((underlying as NSError).code)）"
        case DictationFailure.incompleteRefinement:
            return "整理输出未完整结束"
        case DictationFailure.implausibleRefinement:
            return "整理结果未通过保守检查"
        case DictationFailure.noSpeech:
            return "本次录音未识别到可转写的文字，未调用整理模型"
        default:
            return "处理未完成（系统代码 \((error as NSError).code)）"
        }
    }
}

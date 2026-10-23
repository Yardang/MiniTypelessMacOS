import Foundation

/// Presentation only. Recording files, request identity and insertion policy remain in their owners.
struct PresentationState {
    enum Phase { case locked, idle, recording, transcribing, refining, ready, needsCopy, pasteRequested, failed, cancelled, waitingWake }
    struct Result { let text: String; let date: Date }
    var phase: Phase = .locked
    var startedAt: Date?
    var result: Result?
    var previous: Result?
    var raw: String?
    var rawComplete = false

    mutating func begin(at date: Date = Date()) {
        if let result { previous = result }
        result = nil
        raw = nil
        rawComplete = false
        startedAt = date
        phase = .recording
    }
    mutating func complete(_ text: String) {
        result = Result(text: text, date: startedAt ?? Date())
        phase = .ready
    }
    var copyText: String? { result?.text ?? raw }
    var copyTitle: String { result == nil ? "复制原文" : "复制文字" }
    var title: String {
        switch phase {
        case .locked: return "先解锁，再开始"
        case .idle: return "准备就绪"
        case .recording: return "正在录音"
        case .transcribing: return "正在转写"
        case .refining: return "正在整理文字"
        case .ready: return "文字已生成"
        case .needsCopy: return "文字已生成，未插入"
        case .pasteRequested: return "已请求插入，文字仍可复制"
        case .failed: return raw == nil ? "处理失败，尚未生成文字" : (rawComplete ? "原文已保留，整理未完成" : "转写中断，原文可能不完整")
        case .cancelled: return "处理已取消"
        case .waitingWake: return "睡前录音已保留"
        }
    }
    var placeholder: String {
        switch phase {
        case .locked: return "用 Touch ID 解锁本次运行，\n然后在输入框中按 Fn 开始说话。"
        case .idle: return "把光标放到输入框，\n按 Fn 开始，再按 Fn 结束。"
        case .recording: return "正在听你说话。\n再按 Fn 结束，最长 10 分钟。"
        case .transcribing, .refining: return "正在处理本次录音…"
        case .waitingWake: return "开盖唤醒后会自动处理一次。"
        default: return "本次没有可复制的文字。\n可查看原因，或重试保留的录音。"
        }
    }
    var needsAttention: Bool { phase == .failed || phase == .cancelled || phase == .needsCopy || phase == .locked }
}

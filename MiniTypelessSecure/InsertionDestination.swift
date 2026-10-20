import AppKit

struct InsertionDestination: Equatable {
    let pid: pid_t
    let bundleID: String
    let name: String

    static func current() -> Self? {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return nil }
        return Self(pid: app.processIdentifier, bundleID: bundleID, name: app.localizedName ?? bundleID)
    }
}

enum DestinationDecision: Equatable {
    case current
    case restore(InsertionDestination)
    case reject(String)
}

/// Freeze the intended app at Fn-stop (or retain Fn-start when stopped in our UI).
/// A third app is never silently redirected or given the recorded text.
struct InsertionDestinationPolicy {
    static let supported: Set<String> = ["com.openai.codex", "com.openai.chat", "md.obsidian", "com.anthropic.claudefordesktop"]
    static let compatibilityApps: Set<String> = ["com.openai.codex", "com.openai.chat"]

    static func capture(current: InsertionDestination?, started: InsertionDestination?, ownPID: pid_t) -> InsertionDestination? {
        guard let current else { return nil }
        return current.pid == ownPID ? started : current
    }

    static func decide(target: InsertionDestination?, current: InsertionDestination?, ownPID: pid_t) -> DestinationDecision {
        guard let target else { return .reject("录音时未选择接收应用；请用“尝试插入最新结果”选择输入框。") }
        guard supported.contains(target.bundleID) else {
            return .reject("目标应用“\(target.name)”（\(target.bundleID)）尚未支持自动插入。")
        }
        guard let current else { return .reject("无法确认当前前台应用，未插入。") }
        if current == target { return .current }
        if current.pid == ownPID { return .restore(target) }
        return .reject("等待处理时已切换到“\(current.name)”；原目标是“\(target.name)”，未自动插入。")
    }
}

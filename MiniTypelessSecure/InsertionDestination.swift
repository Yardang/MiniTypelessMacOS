import AppKit
import Carbon

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
    static let compatibilityApps: Set<String> = ["com.openai.codex", "com.openai.chat"]

    static func capture(current: InsertionDestination?, started: InsertionDestination?, ownPID: pid_t) -> InsertionDestination? {
        guard let current else { return nil }
        return current.pid == ownPID ? started : current
    }

    static func decide(target: InsertionDestination?, current: InsertionDestination?, ownPID: pid_t) -> DestinationDecision {
        guard let target else { return .reject("录音时未选择接收应用；请用“尝试插入最新结果”选择输入框。") }
        guard target.pid != ownPID else {
            return .reject("请先选择外部应用的输入框。")
        }
        guard let current else { return .reject("无法确认当前前台应用，未插入。") }
        if current == target { return .current }
        if current.pid == ownPID { return .restore(target) }
        return .reject("等待处理时已切换到“\(current.name)”；原目标是“\(target.name)”，未自动插入。")
    }
}

// Native registration consumes the shortcut; no synthetic V leaks into the target.
@MainActor
final class ResultPasteShortcut {
    private var key: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    func start() -> Bool {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            var identity = EventHotKeyID()
            guard let event, GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &identity) == noErr,
                identity.signature == 0x4D545056, identity.id == 1 else { return OSStatus(eventNotHandledErr) }
            guard let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<ResultPasteShortcut>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { owner.action?() }
            return noErr
        }, 1, &spec, context, &handler)
        guard installed == noErr else { return false }
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(controlKey | optionKey | cmdKey),
            EventHotKeyID(signature: 0x4D545056, id: 1), GetApplicationEventTarget(), 0, &key)
        if status != noErr { stop() }
        return status == noErr
    }
    func stop() {
        if let key { UnregisterEventHotKey(key) }; key = nil
        if let handler { RemoveEventHandler(handler) }; handler = nil
    }
}

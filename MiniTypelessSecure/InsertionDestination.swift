import AppKit
import Carbon
import ApplicationServices

struct InsertionDestination: Equatable {
    let pid: pid_t
    let bundleID: String
    let name: String

    static func current() -> Self? {
        let workspacePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        func owner(_ attribute: String) -> KeyboardOwner {
            var value: CFTypeRef?
            let code = AXUIElementCopyAttributeValue(system, attribute as CFString, &value)
            if code == .noValue || code == .attributeUnsupported { return .unavailable }
            guard code == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return .failed }
            var pid: pid_t = 0
            guard AXUIElementGetPid(value as! AXUIElement, &pid) == .success, pid > 0 else { return .failed }
            return .process(pid)
        }
        // A nonactivating quick panel can receive keys while Workspace still names
        // the background app. Require both system sources before overriding it.
        guard let pid = KeyboardDestinationPolicy.resolve(workspace: workspacePID,
                  application: owner(kAXFocusedApplicationAttribute), element: owner(kAXFocusedUIElementAttribute)),
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              let bundleID = app.bundleIdentifier else { return nil }
        return Self(pid: pid, bundleID: bundleID, name: app.localizedName ?? bundleID)
    }
}

enum KeyboardOwner: Equatable {
    case process(pid_t)
    case unavailable
    case failed
}

/// Missing metadata can retain the existing route. Contradictory or failed
/// queries must never silently route a quick-panel dictation to the background.
enum KeyboardDestinationPolicy {
    static func resolve(workspace: pid_t?, application: KeyboardOwner, element: KeyboardOwner) -> pid_t? {
        switch (application, element) {
        case (.process(let app), .process(let input)): return app == input ? app : nil
        case (.unavailable, .unavailable): return workspace
        case (.process(let pid), .unavailable), (.unavailable, .process(let pid)):
            return pid == workspace ? pid : nil
        default: return nil
        }
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

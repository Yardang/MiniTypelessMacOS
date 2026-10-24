import AppKit
import ApplicationServices

struct InputFocusSnapshot<Element: Equatable> {
    let element: Element
    let selection: NSRange
    let source: String

    func matches(_ other: Self) -> Bool {
        element == other.element && selection == other.selection
    }
}

enum InputFocusResult<Element: Equatable> {
    case found(InputFocusSnapshot<Element>)
    case unavailable
    case rejected
    case limitReached
}

// The lookup policy is independent of AX IPC so missing focus, stale focus, and
// unsafe targets can be reproduced in tests without touching another app.
struct InputFocusReader<Element: Equatable> {
    let app: Element
    let system: Element
    let focusedElement: (Element) -> Element?
    let focusedWindow: (Element) -> Element?
    let children: (Element) -> [Element]
    let isFocused: (Element) -> Bool
    let role: (Element) -> String
    let subrole: (Element) -> String
    let selection: (Element) -> NSRange?
    let belongsToApp: (Element) -> Bool

    private func snapshot(_ element: Element, source: String) -> InputFocusResult<Element> {
        guard belongsToApp(element), subrole(element) != kAXSecureTextFieldSubrole,
              [kAXTextAreaRole, kAXTextFieldRole].contains(role(element)),
              let range = selection(element), range.location != NSNotFound,
              range.location >= 0, range.length >= 0 else { return .rejected }
        return .found(InputFocusSnapshot(element: element, selection: range, source: source))
    }

    func resolve(deadline: Date, nodeLimit: Int = 200) -> InputFocusResult<Element> {
        var sawNonTextFocus = false
        var focusedContainers: [Element] = []
        guard Date() < deadline else { return .limitReached }
        // System keyboard focus is authoritative when present. The application's
        // own focused editor may belong to a background main window.
        let systemFocus = focusedElement(system)
        let candidates: [(Element?, String)] = systemFocus.map { [($0, "系统焦点")] }
            ?? [(focusedElement(app), "应用焦点")]
        for (candidate, source) in candidates {
            guard Date() < deadline else { return .limitReached }
            guard let element = candidate else { continue }
            guard belongsToApp(element), subrole(element) != kAXSecureTextFieldSubrole else { return .rejected }
            if [kAXTextAreaRole, kAXTextFieldRole].contains(role(element)) {
                return snapshot(element, source: source)
            }
            // A focused web area or container may expose the actual editor below it.
            // Do not treat the container itself as an editable field.
            guard [kAXWindowRole, kAXGroupRole, kAXScrollAreaRole, "AXWebArea"].contains(role(element)) else { return .rejected }
            focusedContainers.append(element)
            sawNonTextFocus = true
        }

        guard Date() < deadline else { return .limitReached }
        // Prefer the actual focused subtree: quick windows may not expose AXFocusedWindow.
        var pending = focusedContainers
        if pending.isEmpty, let window = focusedWindow(app), belongsToApp(window) { pending = [window] }
        if pending.isEmpty { return sawNonTextFocus ? .rejected : .unavailable }
        var visited: [Element] = []
        var candidate: InputFocusSnapshot<Element>?
        while let element = pending.popLast() {
            guard Date() < deadline, visited.count < nodeLimit else { return .limitReached }
            if visited.contains(element) { continue }
            visited.append(element)
            guard belongsToApp(element) else { continue }
            if isFocused(element) {
                if subrole(element) == kAXSecureTextFieldSubrole { return .rejected }
                let elementRole = role(element)
                if [kAXTextAreaRole, kAXTextFieldRole].contains(elementRole) {
                    guard case .found(let found) = snapshot(element, source: "窗口内焦点"), candidate == nil else {
                        return .rejected
                    }
                    candidate = found
                } else if ![kAXWindowRole, kAXGroupRole, kAXScrollAreaRole, "AXWebArea"].contains(elementRole) {
                    // A focused button or other control is not an insertion target.
                    return .rejected
                }
            }
            let next = children(element)
            guard next.count + pending.count + visited.count <= nodeLimit else { return .limitReached }
            pending.append(contentsOf: next.reversed())
        }
        if let candidate { return .found(candidate) }
        return sawNonTextFocus ? .rejected : .unavailable
    }
}

struct AXInputElement: Equatable {
    let raw: AXUIElement
    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.raw, rhs.raw) }
}

final class AXInputFocusLookup {
    private let pid: pid_t
    private let app: AXInputElement
    private let system = AXInputElement(raw: AXUIElementCreateSystemWide())
    private(set) var appFocusCode = AXError.failure
    private(set) var systemFocusCode = AXError.failure

    init(pid: pid_t) {
        self.pid = pid
        app = AXInputElement(raw: AXUIElementCreateApplication(pid))
    }

    private func value(_ element: AXInputElement, _ attribute: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element.raw, 0.1)
        var result: CFTypeRef?
        let code = AXUIElementCopyAttributeValue(element.raw, attribute as CFString, &result)
        if attribute == kAXFocusedUIElementAttribute {
            if element == app { appFocusCode = code }
            if element == system { systemFocusCode = code }
        }
        return code == .success ? result : nil
    }

    private func element(_ parent: AXInputElement, _ attribute: String) -> AXInputElement? {
        guard let result = value(parent, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return AXInputElement(raw: result as! AXUIElement)
    }

    func enableElectronAccessibility() {
        AXUIElementSetMessagingTimeout(app.raw, 0.1)
        _ = AXUIElementSetAttributeValue(app.raw, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    func resolve(deadline: Date) -> InputFocusResult<AXInputElement> {
        let reader = InputFocusReader(
            app: app, system: system,
            focusedElement: { self.element($0, kAXFocusedUIElementAttribute) },
            focusedWindow: { self.element($0, kAXFocusedWindowAttribute) },
            children: { element in
                // Read a bounded number of child references; never read their text values.
                AXUIElementSetMessagingTimeout(element.raw, 0.1)
                var count: CFIndex = 0
                guard AXUIElementGetAttributeValueCount(element.raw, kAXChildrenAttribute as CFString, &count) == .success,
                      count > 0 else { return [] }
                var result: CFArray?
                guard AXUIElementCopyAttributeValues(element.raw, kAXChildrenAttribute as CFString, 0, min(count, 201), &result) == .success,
                      let values = result as? [AXUIElement] else { return [] }
                return values.map { AXInputElement(raw: $0) }
            },
            isFocused: { self.value($0, kAXFocusedAttribute) as? Bool == true },
            role: { self.value($0, kAXRoleAttribute) as? String ?? "" },
            subrole: { self.value($0, kAXSubroleAttribute) as? String ?? "" },
            selection: { element in
                guard let value = self.value(element, kAXSelectedTextRangeAttribute),
                      CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
                let axValue = value as! AXValue
                var range = CFRange()
                guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range),
                      range.location >= 0, range.length >= 0 else { return nil }
                return NSRange(location: range.location, length: range.length)
            },
            belongsToApp: { element in
                var owner: pid_t = 0
                return AXUIElementGetPid(element.raw, &owner) == .success && owner == self.pid
            }
        )
        return reader.resolve(deadline: deadline)
    }
}

struct ManualPastePolicy {
    static func allowsUnknownFocus<Element>(_ result: InputFocusResult<Element>, appCode: AXError,
        systemCode: AXError, explicit: Bool, automaticCompatibility: Bool) -> Bool {
        guard case .unavailable = result, appCode == .noValue, systemCode == .noValue else { return false }
        return explicit || automaticCompatibility
    }
}

// Strict metadata-only probe. Never request AXValue, titles, URLs or selected text.
struct FocusProbeSnapshot: Codable {
    enum App: String, Codable { case claude, safari, codex, chatgpt, wechat, miniTypeless, other, absent
        static func classify(_ bundle: String?) -> Self {
            switch bundle {
            case "com.anthropic.claudefordesktop": return .claude
            case "com.apple.Safari": return .safari
            case "com.openai.codex": return .codex
            case "com.openai.chat": return .chatgpt
            case "com.tencent.xinWeChat": return .wechat
            case "com.minitypeless.app": return .miniTypeless
            case nil: return .absent
            default: return .other
            }
        }
    }
    enum Role: String, Codable { case text, secure, web, group, window, button, application, other
        static func classify(_ role: String?, _ subrole: String?) -> Self {
            if subrole == kAXSecureTextFieldSubrole { return .secure }
            switch role {
            case kAXTextFieldRole, kAXTextAreaRole: return .text
            case "AXWebArea": return .web
            case kAXGroupRole, kAXScrollAreaRole: return .group
            case kAXWindowRole: return .window
            case kAXButtonRole: return .button
            case kAXApplicationRole: return .application
            default: return .other
            }
        }
    }
    struct Element: Codable {
        let code: Int32
        let pid: Int32?
        let app: App
        let role: Role?
        let selectionCode: Int32?
    }
    let trusted: Bool
    let workspacePID: Int32?
    let workspaceApp: App
    let systemApp: Element
    let systemFocus: Element
    let workspaceWindow: Element
    let workspaceFocus: Element
    let claudeWindow: Element
    let claudeFocus: Element

    static func capture() -> Self {
        func value(_ element: AXUIElement, _ attribute: String) -> (AXError, CFTypeRef?) {
            AXUIElementSetMessagingTimeout(element, 0.1)
            var result: CFTypeRef?
            let code = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
            return (code, result)
        }
        func describe(_ root: AXUIElement?, _ attribute: String) -> Element {
            guard let root else { return Element(code: AXError.noValue.rawValue, pid: nil, app: .absent, role: nil, selectionCode: nil) }
            let (code, object) = value(root, attribute)
            guard code == .success, let object, CFGetTypeID(object) == AXUIElementGetTypeID() else {
                return Element(code: code.rawValue, pid: nil, app: .absent, role: nil, selectionCode: nil)
            }
            let element = object as! AXUIElement
            var pid: pid_t = 0
            let owner = AXUIElementGetPid(element, &pid)
            return Element(code: code.rawValue, pid: owner == .success ? pid : nil,
                app: .classify(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier),
                role: .classify(value(element, kAXRoleAttribute).1 as? String, value(element, kAXSubroleAttribute).1 as? String),
                selectionCode: value(element, kAXSelectedTextRangeAttribute).0.rawValue)
        }
        let front = NSWorkspace.shared.frontmostApplication
        let root = front.map { AXUIElementCreateApplication($0.processIdentifier) }
        let claude = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.anthropic.claudefordesktop" }
            .map { AXUIElementCreateApplication($0.processIdentifier) }
        let system = AXUIElementCreateSystemWide()
        return Self(trusted: AXIsProcessTrusted(), workspacePID: front?.processIdentifier,
            workspaceApp: .classify(front?.bundleIdentifier), systemApp: describe(system, kAXFocusedApplicationAttribute),
            systemFocus: describe(system, kAXFocusedUIElementAttribute), workspaceWindow: describe(root, kAXFocusedWindowAttribute),
            workspaceFocus: describe(root, kAXFocusedUIElementAttribute), claudeWindow: describe(claude, kAXFocusedWindowAttribute),
            claudeFocus: describe(claude, kAXFocusedUIElementAttribute))
    }
}

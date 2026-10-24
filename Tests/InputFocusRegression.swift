import Foundation
import ApplicationServices

private final class FocusFixture {
    var focus: [String: String] = [:]
    var windows = ["app": "window"]
    var children = ["window": ["editor"]]
    var focused: Set<String> = []
    var roles = ["window": kAXWindowRole, "editor": kAXTextAreaRole]
    var subroles: [String: String] = [:]
    var selections = ["editor": NSRange(location: 3, length: 0)]
    var foreign: Set<String> = []

    var reader: InputFocusReader<String> {
        InputFocusReader(app: "app", system: "system",
            focusedElement: { self.focus[$0] }, focusedWindow: { self.windows[$0] },
            children: { self.children[$0] ?? [] }, isFocused: { self.focused.contains($0) },
            role: { self.roles[$0] ?? "" }, subrole: { self.subroles[$0] ?? "" },
            selection: { self.selections[$0] }, belongsToApp: { !self.foreign.contains($0) })
    }

    func resolve() -> InputFocusResult<String> { reader.resolve(deadline: Date().addingTimeInterval(2)) }
}

@main
struct InputFocusRegression {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }
    private static func snapshot(_ fixture: FocusFixture) -> InputFocusSnapshot<String> {
        guard case .found(let found) = fixture.resolve() else { fatalError("Expected confirmed input") }
        return found
    }
    private static func rejected(_ fixture: FocusFixture) -> Bool {
        if case .rejected = fixture.resolve() { return true }; return false
    }

    static func main() {
        let fixture = FocusFixture()
        fixture.focus["app"] = "editor"
        require(snapshot(fixture).source == "应用焦点", "Existing app-focus route must continue working")
        fixture.focus.removeAll()
        fixture.focus["system"] = "editor"
        require(snapshot(fixture).source == "系统焦点", "Missing app focus must fall back to system focus")
        fixture.focus.removeAll()
        fixture.focused.insert("editor")
        require(snapshot(fixture).source == "窗口内焦点", "Missing app/system focus must find an explicitly focused editor")
        fixture.focused.removeAll()
        if case .unavailable = fixture.resolve() {} else { fatalError("Never choose an unfocused editor") }

        fixture.focus["app"] = "editor"
        fixture.subroles["editor"] = kAXSecureTextFieldSubrole
        require(rejected(fixture), "Reject password field from direct focus")
        fixture.focus.removeAll()
        fixture.focused.insert("editor")
        require(rejected(fixture), "Reject password field from window traversal")
        fixture.subroles.removeAll()
        fixture.focus["system"] = "editor"
        fixture.foreign.insert("editor")
        require(rejected(fixture), "System focus belonging to another app must not be used")
        fixture.foreign.removeAll()
        fixture.selections.removeAll()
        require(rejected(fixture), "A text field without a selection is not confirmed")
        fixture.selections["editor"] = NSRange(location: 3, length: 0)

        fixture.focus.removeAll()
        fixture.children["window"] = ["editor", "second"]
        fixture.roles["second"] = kAXTextAreaRole
        fixture.focused.insert("second")
        fixture.selections["second"] = NSRange(location: 0, length: 0)
        require(rejected(fixture), "Ambiguous focused editors must be rejected")
        fixture.focused.remove("second")
        fixture.children["window"] = ["editor"]
        let first = snapshot(fixture)
        fixture.selections["editor"] = NSRange(location: 4, length: 0)
        require(!first.matches(snapshot(fixture)), "Selection movement must invalidate confirmation")
        fixture.focus["app"] = "second"
        require(!first.matches(snapshot(fixture)), "Element movement must invalidate confirmation")

        fixture.focus.removeAll()
        fixture.focused = ["editor"]
        fixture.roles["editor"] = kAXButtonRole
        require(rejected(fixture), "A focused button must never be treated as an editor")
        fixture.roles["editor"] = kAXTextAreaRole
        fixture.focus["app"] = "container"
        fixture.roles["container"] = "AXWebArea"
        fixture.children["container"] = ["editor"]
        require(snapshot(fixture).source == "窗口内焦点", "A focused container must resolve to its focused editor")
        fixture.children["container"] = ["editor"]
        fixture.windows.removeAll()
        require(snapshot(fixture).element == "editor", "Quick window / web focus subtree works without focused window")
        fixture.focus["app"] = "button"; fixture.roles["button"] = kAXButtonRole
        require(rejected(fixture), "Known button must not fall through to another editor")
        fixture.focus["app"] = "container"
        fixture.subroles["editor"] = kAXSecureTextFieldSubrole
        require(rejected(fixture), "Reject secure child in focused web subtree")
        fixture.subroles.removeAll()
        for result: InputFocusResult<String> in [.rejected, .limitReached, .found(InputFocusSnapshot(element: "x", selection: NSRange(location: 0, length: 0), source: "test"))] {
            require(!ManualPastePolicy.allowsUnknownFocus(result, appCode: .noValue, systemCode: .noValue, explicit: true, automaticCompatibility: true), "Explicit request must not bypass rejection, timeout, or changed confirmation")
        }
        let missing: InputFocusResult<String> = .unavailable
        require(ManualPastePolicy.allowsUnknownFocus(missing, appCode: .noValue, systemCode: .noValue, explicit: true, automaticCompatibility: false), "Explicit missing-focus fallback")
        require(!ManualPastePolicy.allowsUnknownFocus(missing, appCode: .noValue, systemCode: .noValue, explicit: false, automaticCompatibility: false), "No automatic unknown-focus expansion")
        require(!ManualPastePolicy.allowsUnknownFocus(missing, appCode: .apiDisabled, systemCode: .noValue, explicit: true, automaticCompatibility: false), "Permission failures cannot be bypassed")
        if case .limitReached = fixture.reader.resolve(deadline: .distantPast) {} else { fatalError("Enforce time limit") }
        fixture.focus.removeAll()
        fixture.windows["app"] = "window"
        if case .limitReached = fixture.reader.resolve(deadline: .distantFuture, nodeLimit: 1) {} else { fatalError("Enforce traversal limit") }
        print("PASS: input-focus and manual-fallback cases, including missing app focus, system/window fallbacks, and unsafe/stale target rejection.")
    }
}

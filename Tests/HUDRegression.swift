import AppKit

@main
@MainActor
struct HUDRegression {
    static func require(_ value: Bool, _ message: String) {
        if !value { print("FAIL: \(message)"); exit(1) }
    }
    static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let hud = StatusHUD()
        hud.panel.alphaValue = 0 // Exercise visibility without covering the user's desktop.
        var state = PresentationState()
        state.begin(); state.complete("Synthetic recoverable result"); state.phase = .needsCopy
        var copies: [String] = []
        var views = 0
        var copySucceeds = false
        hud.onCopy = { text in copies.append(text); return copySucceeds }
        hud.onView = { views += 1 }
        hud.update(state, sleeping: false)
        require(hud.open.title == "复制", "Complete uninserted result must offer Copy")
        hud.open.performClick(nil)
        require(copies == ["Synthetic recoverable result"] && views == 0 && !hud.open.isHidden, "Failure must allow retry without opening window")
        copySucceeds = true
        hud.open.performClick(nil)
        require(copies.count == 2 && views == 0 && hud.open.isHidden, "Copy must use current result without opening window")
        require(hud.panel.isVisible, "Missing initial needsCopy feedback")
        try await Task.sleep(nanoseconds: 3_300_000_000)
        require(!hud.panel.isVisible, "Insertion failure HUD must dismiss after three seconds")
        require(state.copyText == "Synthetic recoverable result", "Dismissal lost recoverable text")
        hud.update(state, sleeping: false)
        require(!hud.panel.isVisible, "Unchanged state resurfaced dismissed feedback")
        for phase: PresentationState.Phase in [.failed, .cancelled, .locked, .ready, .pasteRequested] {
            state.phase = phase; hud.update(state, sleeping: false)
            require(hud.panel.isVisible && !hud.open.isHidden, "Outcome must initially offer View: \(phase)")
            try await Task.sleep(nanoseconds: 3_300_000_000)
            require(!hud.panel.isVisible, "Outcome remained visible: \(phase)")
            hud.update(state, sleeping: false)
            require(!hud.panel.isVisible, "Outcome resurfaced: \(phase)")
        }
        for phase: PresentationState.Phase in [.recording, .transcribing, .refining] {
            state.phase = .failed; hud.update(state, sleeping: false)
            state.phase = phase; hud.update(state, sleeping: false)
            try await Task.sleep(nanoseconds: 3_300_000_000)
            require(hud.panel.isVisible && hud.open.isHidden, "Stale timeout hid active phase: \(phase)")
        }
        require(copies.count == 2, "Recording/processing must not copy stale text")
        var empty = PresentationState()
        empty.previous = state.result
        empty.raw = "Partial raw text"
        empty.phase = .needsCopy
        hud.update(empty, sleeping: false)
        require(hud.open.title == "查看", "No complete current result must not copy previous or partial text")
        hud.open.performClick(nil)
        require(views == 1 && copies.count == 2, "Missing result must retain View behavior")
        hud.notice("Synthetic recording start failure")
        require(hud.open.title == "查看", "Notice must clear stale Copy action")
        hud.open.performClick(nil)
        require(views == 2 && copies.count == 2, "Notice must open details, never copy old text")
        require(hud.panel.isVisible && !hud.open.isHidden, "Notice missing")
        try await Task.sleep(nanoseconds: 3_300_000_000)
        require(!hud.panel.isVisible, "Notice must also expire")
        hud.notice("Synthetic permission failure")
        state.begin(); hud.update(state, sleeping: false)
        try await Task.sleep(nanoseconds: 3_300_000_000)
        require(hud.panel.isVisible, "Notice timeout hid next recording")
        require(!hud.panel.canBecomeKey && !hud.panel.canBecomeMain, "HUD must remain passive")
        hud.update(state, sleeping: true)
        require(!hud.panel.isVisible, "Sleeping must hide the HUD")
        hud.hide()
        print("PASS: HUD outcomes/notices expire, same-state refresh stays hidden, active phases survive stale timers, result retained")
    }
}

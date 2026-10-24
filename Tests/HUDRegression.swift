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
        hud.update(state, sleeping: false)
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
        hud.notice("Synthetic recording start failure")
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

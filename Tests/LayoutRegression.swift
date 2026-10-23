import AppKit

@main
@MainActor
struct LayoutRegression {
    static func require(_ ok: Bool, _ message: String) { precondition(ok, message) }
    static func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let suiteName = "MiniTypeless.ThemeTest." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        require(InterfaceTheme.load(from: preferences) == .system, "Default must follow system")
        for theme in InterfaceTheme.allCases {
            theme.save(to: preferences)
            require(InterfaceTheme.load(from: preferences) == theme, "Theme preference did not persist")
        }
        require(InterfaceTheme.system.appearance == nil, "System theme must inherit live appearance")
        require(InterfaceTheme.light.appearance?.name == .aqua && InterfaceTheme.dark.appearance?.name == .darkAqua, "Explicit themes mismatch")
        let app = SecureProbe()
        let w = app.makeWindow(), ui = app.resultTestUI
        w.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        var semantics = PresentationState(); semantics.begin(); semantics.raw = "部分原文"; semantics.phase = .failed
        require(semantics.copyText == "部分原文" && semantics.copyTitle == "复制原文" && semantics.title.contains("可能不完整"), "Partial text semantics")
        semantics.rawComplete = true
        require(semantics.title.contains("整理未完成"), "Complete raw text semantics")
        semantics.complete("完整结果"); semantics.phase = .pasteRequested
        require(semantics.title.contains("请求") && !semantics.title.contains("插入成功"), "Do not claim receiver acceptance")
        var state = PresentationState()
        state.begin(); state.complete("上次成功的合成文字。")
        state.begin(); state.raw = String(repeating: "合成文字用于检查长文本换行。", count: 300)
        state.phase = .failed
        var checks = 0
        for theme in InterfaceTheme.allCases {
        w.appearance = theme.appearance
        for size in [NSSize(width: 500, height: 430), NSSize(width: 580, height: 550), NSSize(width: 900, height: 760)] {
            for prior in [false, true] {
                for success in [false, true] {
                    var current = state
                    if success { current.complete(state.raw!) }
                    ui.previousExpanded = prior
                    w.setContentSize(size)
                    ui.render(current, busy: false, recoveryAvailable: !success, insertionPending: false, detailMessage: String(repeating: "网络连接已中断。", count: 100))
                    w.contentView!.layoutSubtreeIfNeeded()
                    let content = w.contentView!
                    for b in success ? [ui.copy, ui.insert, ui.more] : [ui.copy, ui.retry, ui.export, ui.discard] {
                        let frame = b.convert(b.bounds, to: content)
                        require(!b.isHidden && content.bounds.contains(frame), "Action clipped: \(b.title), \(size), prior=\(prior): \(frame)")
                        require(frame.height >= 28 && frame.width > 18, "Action collapsed: \(b.title) \(frame)")
                    }
                    require(ui.bodyScroll.frame.height >= 85, "Body collapsed")
                    require(ui.text.bounds.width > 400, "Body has no reading width")
                    require(ui.text.textContainer!.containerSize.width <= ui.text.bounds.width + 1, "Body does not wrap")
                    require(ui.text.frame.height > ui.bodyScroll.contentView.bounds.height, "Long text must scroll")
                    require(ui.previousArea.isHidden == !prior, "Previous disclosure mismatch")
                    checks += 1
                }
            }
        }
        }
        // Disclosure is reversible, including custom sizes and refreshes while expanded.
        var history = PresentationState(); history.begin(); history.complete("上一段。")
        history.begin(); history.complete("本次。")
        func renderHistory() {
            ui.render(history, busy: false, recoveryAvailable: false, insertionPending: false, detailMessage: "")
            w.contentView!.layoutSubtreeIfNeeded()
        }
        ui.previousExpanded = false; renderHistory()
        for size in [NSSize(width: 580, height: 430), NSSize(width: 640, height: 480), NSSize(width: 720, height: 700)] {
            w.setContentSize(size)
            let original = w.frame
            for _ in 0..<3 {
                ui.previousExpanded = true; renderHistory()
                require(abs(w.frame.maxY - original.maxY) < 1, "Expanding moved the window top")
                renderHistory(); renderHistory()
                ui.previousExpanded = false; renderHistory()
                require(abs(w.frame.height - original.height) < 1 && abs(w.frame.width - original.width) < 1, "Collapsing did not restore original size")
                require(abs(w.frame.maxY - original.maxY) < 1, "Collapsing moved the window top")
            }
        }
        w.setContentSize(NSSize(width: 580, height: 430)); let beforeNewTake = w.frame.size
        ui.previousExpanded = true; renderHistory()
        w.setFrameOrigin(NSPoint(x: w.frame.minX + 40, y: w.frame.minY + 30))
        let movedTop = w.frame.maxY, movedLeft = w.frame.minX
        history.begin(); ui.previousExpanded = false; renderHistory()
        require(w.frame.size == beforeNewTake, "New take did not restore collapsed size")
        require(abs(w.frame.maxY - movedTop) < 1 && abs(w.frame.minX - movedLeft) < 1, "Collapse reverted a user move")
        // The actual menu opens settings, where normal configuration and costs remain available.
        app.showSettingsTest()
        let settings = app.settingsTestWindow!
        settings.orderOut(nil); settings.contentView!.layoutSubtreeIfNeeded()
        let picker = descendants(settings.contentView!).compactMap { $0 as? NSPopUpButton }.first
        require(picker?.itemTitles == InterfaceTheme.allCases.map(\.title), "Appearance choices missing")
        let titles = descendants(w.contentView!).compactMap { ($0 as? NSButton)?.title }
        require(!titles.contains(where: { $0.contains("30 条") || $0.contains("迁移") || $0.contains("API Key") }), "Developer/setup controls leaked into result window")
        let hud = StatusHUD()
        require(!hud.panel.canBecomeKey && !hud.panel.canBecomeMain, "HUD can steal keyboard focus")
        require(hud.panel.styleMask.contains(.nonactivatingPanel), "HUD activates app")
        var recording = PresentationState(); recording.begin(at: Date().addingTimeInterval(-32))
        hud.renderContent(recording); hud.panel.contentView!.layoutSubtreeIfNeeded()
        let hudView = hud.panel.contentView!
        let timerFrame = hud.recordingTime.convert(hud.recordingTime.bounds, to: hudView)
        let hintFrame = hud.recordingHint.convert(hud.recordingHint.bounds, to: hudView)
        require(abs(timerFrame.midX - hudView.bounds.midX) < 1, "Recording timer must be centered")
        require(hintFrame.minX > timerFrame.maxX && hudView.bounds.contains(hintFrame), "Fn hint must fit on the right")
        require(hud.recordingHint.font!.pointSize < hud.recordingTime.font!.pointSize, "Fn hint should be visually secondary")
        recording.phase = .failed; hud.renderContent(recording)
        require(hud.recordingTime.isHiddenOrHasHiddenAncestor && !hud.open.isHiddenOrHasHiddenAncestor, "Failure must restore status/actions")
        for phase: PresentationState.Phase in [.transcribing, .refining, .ready, .failed, .cancelled, .needsCopy, .pasteRequested, .locked, .waitingWake] {
            var status = PresentationState(); status.phase = phase
            hud.renderContent(status); hudView.layoutSubtreeIfNeeded()
            let expected = phase == .pasteRequested ? "已请求插入" : status.title
            let statusLabel = descendants(hudView).compactMap { $0 as? NSTextField }.first { $0.stringValue == expected }!
            let frame = statusLabel.convert(statusLabel.bounds, to: hudView)
            require(statusLabel.alignment == .center && abs(frame.midX - timerFrame.midX) < 1, "Status must share timer center: \(phase)")
            require(hudView.bounds.contains(frame), "Status clipped")
            if !hud.open.isHidden {
                let buttonFrame = hud.open.convert(hud.open.bounds, to: hudView)
                require(buttonFrame.minX > frame.maxX, "View action overlaps status")
            }
        }
        var preview = PresentationState(); preview.begin(); preview.complete("明天下午三点，我们讨论 Mini Typeless 的界面。\n\n希望它平时安静地待在后台，需要时能方便地找到文字。")
        preview.previous = .init(text: "上一段合成结果。", date: Date().addingTimeInterval(-240)); preview.phase = .needsCopy
        ui.previousExpanded = false; w.setContentSize(NSSize(width: 580, height: 430))
        ui.render(preview, busy: false, recoveryAvailable: false, insertionPending: false, detailMessage: "目标输入框不可用。")
        w.contentView!.layoutSubtreeIfNeeded()
        if let path = ProcessInfo.processInfo.environment["MINITYPELESS_PREVIEW_PATH"], let bitmap = w.contentView!.bitmapImageRepForCachingDisplay(in: w.contentView!.bounds) {
            w.contentView!.cacheDisplay(in: w.contentView!.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        }
        print("PASS: \(checks) real window layouts, long text scrolling, previous disclosure, settings access, no daily developer controls, nonactivating HUD.")
    }
}

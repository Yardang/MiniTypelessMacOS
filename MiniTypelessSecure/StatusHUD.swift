import AppKit

private final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Visual feedback only: never activates the app or changes the insertion destination.
@MainActor
final class StatusHUD {
    let panel: NSPanel
    private let label = QuietStyle.label("", size: 13)
    private let icon = NSImageView()
    private let spinner = NSProgressIndicator()
    private let recordingContent = NSView()
    private var statusContent: NSStackView!
    let recordingTime = QuietStyle.label("00:00", size: 15)
    let recordingHint = QuietStyle.label("Fn 结束", size: 11)
    let open = QuietStyle.button("查看")
    private var lastPhase: PresentationState.Phase?
    private var dismiss: DispatchWorkItem?

    init() {
        panel = PassivePanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 48), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isReleasedWhenClosed = false; panel.appearance = InterfaceTheme.load().appearance
        let surface = QuietStyle.glassSurface(radius: 24)
        panel.contentView = surface.surface
        let glass = surface.content
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        recordingTime.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        recordingTime.textColor = QuietStyle.ink; recordingTime.alignment = .center
        recordingTime.setAccessibilityLabel("录音时长")
        recordingHint.alignment = .right
        let dot = QuietStyle.label("●", size: 9); dot.textColor = QuietStyle.red
        let wave = NSImageView(image: NSImage(systemSymbolName: "waveform", accessibilityDescription: "正在录音")!)
        wave.contentTintColor = QuietStyle.secondary; wave.imageScaling = .scaleProportionallyUpOrDown
        wave.widthAnchor.constraint(equalToConstant: 36).isActive = true
        wave.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let leading = QuietStyle.row([dot, wave], spacing: 12)
        let divider = NSBox(); divider.boxType = .separator
        recordingContent.translatesAutoresizingMaskIntoConstraints = false; glass.addSubview(recordingContent)
        for view in [leading, divider, recordingTime, recordingHint] {
            view.translatesAutoresizingMaskIntoConstraints = false; recordingContent.addSubview(view)
            view.centerYAnchor.constraint(equalTo: recordingContent.centerYAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            recordingContent.leadingAnchor.constraint(equalTo: glass.leadingAnchor), recordingContent.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            recordingContent.topAnchor.constraint(equalTo: glass.topAnchor), recordingContent.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            leading.leadingAnchor.constraint(equalTo: recordingContent.leadingAnchor, constant: 22),
            divider.leadingAnchor.constraint(equalTo: recordingContent.leadingAnchor, constant: 100), divider.widthAnchor.constraint(equalToConstant: 1), divider.heightAnchor.constraint(equalToConstant: 18),
            recordingTime.centerXAnchor.constraint(equalTo: recordingContent.centerXAnchor), recordingTime.widthAnchor.constraint(equalToConstant: 58),
            recordingHint.trailingAnchor.constraint(equalTo: recordingContent.trailingAnchor, constant: -22), recordingHint.widthAnchor.constraint(equalToConstant: 50)
        ])
        recordingContent.isHidden = true
        let row = QuietStyle.row([icon, spinner, label, QuietStyle.spacer(), open], spacing: 8)
        statusContent = row
        row.translatesAutoresizingMaskIntoConstraints = false; glass.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 16), row.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -16), row.centerYAnchor.constraint(equalTo: glass.centerYAnchor)])
    }
    func renderContent(_ state: PresentationState) {
        recordingContent.isHidden = state.phase != .recording
        statusContent.isHidden = state.phase == .recording
        let processing = state.phase == .transcribing || state.phase == .refining
        if processing { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        spinner.isHidden = !processing; icon.isHidden = processing
        icon.image = NSImage(systemSymbolName: state.phase == .recording ? "waveform" : (state.needsAttention ? "exclamationmark.circle" : "checkmark"), accessibilityDescription: state.title)
        icon.contentTintColor = state.phase == .recording ? QuietStyle.red : QuietStyle.color(state.phase)
        if state.phase == .recording {
            let seconds = max(0, min(600, Int(Date().timeIntervalSince(state.startedAt ?? Date()))))
            recordingTime.stringValue = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        } else {
            label.stringValue = state.phase == .pasteRequested ? "已请求插入" : state.title
        }
        open.isHidden = state.phase == .recording || processing
    }
    func update(_ state: PresentationState, sleeping: Bool) {
        guard !sleeping, state.phase != .idle else { hide(); return }
        renderContent(state)
        guard lastPhase != state.phase else { return }
        dismiss?.cancel(); lastPhase = state.phase
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame { panel.setFrameOrigin(NSPoint(x: frame.midX - 150, y: frame.minY + 28)) }
        panel.orderFrontRegardless()
        if state.phase == .ready || state.phase == .pasteRequested {
            let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
            dismiss = work; DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        }
    }
    func notice(_ message: String) {
        dismiss?.cancel(); lastPhase = nil
        recordingContent.isHidden = true; statusContent.isHidden = false
        spinner.stopAnimation(nil); spinner.isHidden = true; icon.isHidden = false
        icon.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: message)
        icon.contentTintColor = QuietStyle.red; label.stringValue = message; open.isHidden = false
        if let frame = NSScreen.main?.visibleFrame { panel.setFrameOrigin(NSPoint(x: frame.midX - 150, y: frame.minY + 28)) }
        panel.orderFrontRegardless()
    }
    func hide() { dismiss?.cancel(); dismiss = nil; panel.orderOut(nil); lastPhase = nil }
}

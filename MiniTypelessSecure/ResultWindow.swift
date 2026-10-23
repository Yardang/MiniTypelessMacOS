import AppKit

@MainActor
enum QuietStyle {
    static let blue = NSColor(srgbRed: 0.32, green: 0.45, blue: 0.63, alpha: 1)
    static let green = NSColor(srgbRed: 0.41, green: 0.57, blue: 0.50, alpha: 1)
    static let red = NSColor(srgbRed: 0.68, green: 0.43, blue: 0.46, alpha: 1)
    static let sand = NSColor(srgbRed: 0.70, green: 0.65, blue: 0.49, alpha: 1)
    static let ink = NSColor(srgbRed: 0.13, green: 0.18, blue: 0.25, alpha: 1)
    static let secondary = NSColor(srgbRed: 0.36, green: 0.42, blue: 0.51, alpha: 1)
    static func color(_ phase: PresentationState.Phase) -> NSColor {
        switch phase {
        case .ready, .pasteRequested: return green
        case .failed: return red
        case .needsCopy, .cancelled, .waitingWake, .locked: return sand
        default: return blue
        }
    }
    static func label(_ text: String, size: CGFloat = 13) -> NSTextField {
        let v = NSTextField(wrappingLabelWithString: text)
        v.font = .systemFont(ofSize: size)
        v.textColor = secondary
        return v
    }
    static func button(_ text: String, symbol: String? = nil) -> NSButton {
        let b = NSButton(title: text, target: nil, action: nil)
        b.isBordered = false
        b.bezelStyle = .inline
        b.font = .systemFont(ofSize: 14)
        b.contentTintColor = blue
        if let symbol { b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text); b.imagePosition = text.isEmpty ? .imageOnly : .imageLeading }
        b.setAccessibilityLabel(text)
        b.heightAnchor.constraint(equalToConstant: 35).isActive = true
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        return b
    }
    static func row(_ views: [NSView], spacing: CGFloat = 14) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal; s.alignment = .centerY; s.spacing = spacing
        return s
    }
    static func spacer() -> NSView {
        let v = NSView(); v.setContentHuggingPriority(.defaultLow, for: .horizontal); return v
    }
    static func textScroll(_ text: NSTextView) -> NSScrollView {
        text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
        text.font = .systemFont(ofSize: 17); text.textColor = ink
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainerInset = NSSize(width: 0, height: 8)
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let style = NSMutableParagraphStyle(); style.lineSpacing = 4; style.paragraphSpacing = 2
        text.defaultParagraphStyle = style
        let s = NSScrollView(); s.documentView = text; s.drawsBackground = false
        s.hasVerticalScroller = true; s.autohidesScrollers = true
        return s
    }
}

/// A retained native window: all controls expose actions but own no dictation logic.
@MainActor
final class ResultWindow {
    let window: NSWindow
    let text = NSTextView()
    let previousText = NSTextView()
    let status = QuietStyle.label("先解锁，再开始")
    let dot = QuietStyle.label("●", size: 10)
    let timestamp = QuietStyle.label("")
    let detail = QuietStyle.label("")
    let feedback = QuietStyle.label("")
    let copy = QuietStyle.button("复制文字", symbol: "doc.on.doc")
    let insert = QuietStyle.button("尝试插入", symbol: "text.cursor")
    let more = QuietStyle.button("", symbol: "ellipsis")
    let settings = QuietStyle.button("", symbol: "gearshape")
    let close = QuietStyle.button("", symbol: "xmark")
    let unlock = QuietStyle.button("Touch ID 解锁", symbol: "touchid")
    let record = QuietStyle.button("开始录音", symbol: "mic")
    let cancel = QuietStyle.button("取消处理")
    let retry = QuietStyle.button("重试转写")
    let export = QuietStyle.button("另存录音")
    let discard = QuietStyle.button("删除录音")
    let previousToggle = QuietStyle.button("上次成功结果", symbol: "chevron.right")
    let previousCopy = QuietStyle.button("复制上次文字", symbol: "doc.on.doc")
    let previousTime = QuietStyle.label("")
    let recoveryNote = QuietStyle.label("重试会重新上传，可能重复计费。新录音成功开始或退出会清除待重试录音。", size: 11)
    let recovery: NSStackView
    let previousArea: NSStackView
    let previousScroll: NSScrollView
    let bodyScroll: NSScrollView
    var previousExpanded = false

    init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 430), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Mini Typeless"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.isMovableByWindowBackground = true
        window.contentMinSize = NSSize(width: 500, height: 430)
        window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = true
        window.appearance = NSAppearance(named: .aqua)
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(kind)?.isHidden = true }
        let glass = NSVisualEffectView()
        glass.material = .popover; glass.blendingMode = .behindWindow; glass.state = .active
        glass.wantsLayer = true; glass.layer?.cornerRadius = 22; glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true; glass.layer?.borderWidth = 0.5
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        window.contentView = glass
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false; glass.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 28), root.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: glass.topAnchor, constant: 20), root.bottomAnchor.constraint(equalTo: glass.bottomAnchor, constant: -18)
        ])
        let logo = NSImageView(image: NSImage(systemSymbolName: "waveform", accessibilityDescription: "Mini Typeless")!)
        logo.contentTintColor = QuietStyle.blue; logo.widthAnchor.constraint(equalToConstant: 22).isActive = true
        let name = QuietStyle.label("Mini Typeless", size: 14); name.font = .systemFont(ofSize: 14, weight: .medium); name.textColor = QuietStyle.ink
        settings.setAccessibilityLabel("设置、用量与帮助"); settings.toolTip = "设置、用量与帮助"
        more.setAccessibilityLabel("更多操作"); more.toolTip = "更多操作"
        close.setAccessibilityLabel("隐藏窗口"); close.toolTip = "隐藏窗口，Fn 仍可使用"
        let header = QuietStyle.row([logo, name, QuietStyle.spacer(), settings, close])
        root.addArrangedSubview(header)
        let statusRow = QuietStyle.row([dot, status, QuietStyle.spacer(), timestamp], spacing: 8)
        timestamp.setContentCompressionResistancePriority(.required, for: .horizontal)
        root.addArrangedSubview(statusRow)
        detail.maximumNumberOfLines = 2; detail.font = .systemFont(ofSize: 12); detail.isHidden = true
        root.addArrangedSubview(detail)
        bodyScroll = QuietStyle.textScroll(text); root.addArrangedSubview(bodyScroll)
        bodyScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
        let actions = QuietStyle.row([copy, insert, unlock, record, cancel, QuietStyle.spacer(), more], spacing: 16)
        root.addArrangedSubview(actions)
        feedback.font = .systemFont(ofSize: 11); feedback.isHidden = true; root.addArrangedSubview(feedback)
        recovery = QuietStyle.row([retry, export, discard], spacing: 16); recovery.isHidden = true
        root.addArrangedSubview(recovery); recoveryNote.isHidden = true; root.addArrangedSubview(recoveryNote)
        let line = NSBox(); line.boxType = .separator; root.addArrangedSubview(line)
        previousToggle.contentTintColor = QuietStyle.secondary
        let priorHeader = QuietStyle.row([previousToggle, QuietStyle.spacer(), previousTime])
        root.addArrangedSubview(priorHeader)
        previousScroll = QuietStyle.textScroll(previousText)
        previousText.font = .systemFont(ofSize: 14)
        previousScroll.heightAnchor.constraint(equalToConstant: 90).isActive = true
        previousArea = NSStackView(views: [previousScroll, previousCopy]); previousArea.orientation = .vertical
        previousArea.alignment = .leading; previousArea.spacing = 3; previousArea.isHidden = true
        root.addArrangedSubview(previousArea)
        for v in root.arrangedSubviews { v.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        previousScroll.widthAnchor.constraint(equalTo: previousArea.widthAnchor).isActive = true
        window.center()
    }

    func render(_ state: PresentationState, busy: Bool, recoveryAvailable: Bool, insertionPending: Bool, detailMessage: String) {
        status.stringValue = state.title; dot.textColor = QuietStyle.color(state.phase)
        timestamp.stringValue = state.startedAt.map { "本次 · " + Self.time($0) } ?? ""
        let content = state.copyText ?? state.placeholder
        if text.string != content { text.string = content; text.scrollToBeginningOfDocument(nil) }
        text.textColor = state.copyText == nil ? QuietStyle.secondary : QuietStyle.ink
        copy.title = state.copyTitle; copy.isHidden = state.copyText == nil; copy.isEnabled = state.copyText != nil && !busy && state.phase != .recording
        insert.isHidden = state.result == nil; insert.isEnabled = state.result != nil && !busy && !insertionPending
        unlock.isHidden = state.phase != .locked
        record.isHidden = state.phase != .idle && state.phase != .recording
        cancel.isHidden = !busy
        recovery.isHidden = !recoveryAvailable || busy; recoveryNote.isHidden = recovery.isHidden
        detail.isHidden = !state.needsAttention && state.phase != .pasteRequested
        detail.stringValue = state.phase == .needsCopy ? "可直接复制文字，或重新选择输入位置。" : (state.phase == .pasteRequested ? "如果目标输入框没有出现文字，可以直接复制。" : detailMessage)
        detail.toolTip = detailMessage
        previousToggle.isEnabled = state.previous != nil
        previousTime.stringValue = state.previous.map { Self.time($0.date) } ?? "暂无"
        previousText.string = state.previous?.text ?? ""
        previousArea.isHidden = !previousExpanded || state.previous == nil
        previousToggle.image = NSImage(systemSymbolName: previousArea.isHidden ? "chevron.right" : "chevron.down", accessibilityDescription: nil)
        let minHeight: CGFloat = previousArea.isHidden ? 430 : 550
        window.contentMinSize = NSSize(width: 500, height: minHeight)
        if (window.contentView?.bounds.height ?? 0) < minHeight { window.setContentSize(NSSize(width: window.contentView!.bounds.width, height: minHeight)) }
    }
    static func time(_ date: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date) }
}

@MainActor
final class LiveStatusField: NSTextField {
    var changed: (() -> Void)?
    override var stringValue: String { didSet { changed?() } }
}

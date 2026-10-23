import AppKit

private final class SettingsDocumentView: NSView { override var isFlipped: Bool { true } }

/// Settings presentation only; all permissions, credentials and usage remain in the coordinator.
@MainActor
final class SettingsWindow {
    let window: NSWindow
    let close = QuietStyle.button("", symbol: "xmark")
    let themePicker = NSPopUpButton()
    let unlock = QuietStyle.button("Touch ID 解锁", symbol: "touchid")
    let permissions = QuietStyle.button("检查权限", symbol: "checkmark.shield")
    let keyToggle = QuietStyle.button("设置", symbol: "chevron.down")
    let keyTools = NSStackView()
    let saveKey = QuietStyle.button("存入本机钥匙串")
    let notice = QuietStyle.label("", size: 12)
    let usageToggle = QuietStyle.button("查看明细", symbol: "chevron.down")
    let usageTools = NSStackView()
    let usageDetails = QuietStyle.label("", size: 12)
    let todaySummary = QuietStyle.label("")
    let monthSummary = QuietStyle.label("")
    let help = QuietStyle.button("诊断与帮助", symbol: "questionmark.circle")
    let quit = QuietStyle.button("退出 Mini Typeless")
    let scroll = NSScrollView()

    init(autoInsert: NSButton, compatibility: NSButton, keyInput: NSSecureTextField) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 720), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "设置与用量"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.isMovableByWindowBackground = true
        window.contentMinSize = NSSize(width: 500, height: 420)
        window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = true
        window.appearance = InterfaceTheme.load().appearance
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(kind)?.isHidden = true }
        let surface = QuietStyle.glassSurface(radius: 22); window.contentView = surface.surface
        let content = surface.content
        close.setAccessibilityLabel("关闭设置"); close.toolTip = "关闭设置，Fn 仍可使用"
        close.target = window; close.action = #selector(NSWindow.close)
        let header = QuietStyle.windowHeader(title: "设置与用量", close: close)
        header.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(header)
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(scroll)
        let footer = QuietStyle.row([help, QuietStyle.spacer(), quit])
        footer.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(footer)
        let document = SettingsDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = document
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 20
        root.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(root)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28), header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28), header.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor), scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28), footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28), footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            root.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28), root.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28), root.topAnchor.constraint(equalTo: document.topAnchor, constant: 8), root.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16)
        ])
        themePicker.addItems(withTitles: InterfaceTheme.allCases.map(\.title))
        themePicker.selectItem(at: InterfaceTheme.allCases.firstIndex(of: InterfaceTheme.load())!)
        themePicker.setAccessibilityLabel("界面外观")
        autoInsert.title = ""; autoInsert.setAccessibilityLabel("整理成功后尝试自动插入")
        compatibility.title = ""; compatibility.setAccessibilityLabel("无焦点信息时允许兼容粘贴")
        addSection("日常设置", to: root, views: [
            settingRow("外观", control: themePicker),
            settingRow("自动插入", control: autoInsert),
            note("整理后尝试插入原输入框，不自动发送消息。"),
            settingRow("兼容粘贴", control: compatibility),
            note("默认关闭，仅本次运行有效。仅限 Codex / ChatGPT 不提供焦点时，请自行选中输入框。")
        ])
        keyTools.orientation = .vertical; keyTools.alignment = .leading; keyTools.spacing = 8
        keyInput.placeholderString = "自己的百炼北京区 API Key"
        keyInput.setAccessibilityLabel("百炼 API Key")
        keyTools.addArrangedSubview(keyInput); keyTools.addArrangedSubview(saveKey)
        keyInput.widthAnchor.constraint(equalTo: keyTools.widthAnchor).isActive = true
        keyTools.isHidden = true; notice.isHidden = true
        addSection("权限与密钥", to: root, views: [
            settingRow("本次运行", control: unlock),
            settingRow("Fn 与辅助功能", control: permissions),
            settingRow("百炼 API Key", control: keyToggle), keyTools,
            note("密钥保存在本机 Touch ID 钥匙串，已有密钥不会被覆盖。"), notice
        ])
        todaySummary.textColor = QuietStyle.ink; monthSummary.textColor = QuietStyle.ink
        usageTools.orientation = .vertical; usageTools.alignment = .leading; usageTools.spacing = 8
        usageTools.addArrangedSubview(usageDetails); usageDetails.widthAnchor.constraint(equalTo: usageTools.widthAnchor).isActive = true
        usageTools.isHidden = true
        addSection("用量", to: root, views: [
            settingRow("今天", control: todaySummary), settingRow("本月", control: monthSummary),
            note("录音时长 · 预估费用。未扣免费额度，以百炼账单为准。"), QuietStyle.row([usageToggle, QuietStyle.spacer()]), usageTools
        ])
        for view in root.arrangedSubviews { view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        window.center()
    }
    private func settingRow(_ title: String, control: NSView) -> NSView {
        let label = QuietStyle.label(title); label.textColor = QuietStyle.ink
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = QuietStyle.row([label, QuietStyle.spacer(), control], spacing: 12)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        return row
    }
    private func note(_ text: String) -> NSTextField { QuietStyle.label(text, size: 11) }
    private func addSection(_ title: String, to root: NSStackView, views: [NSView]) {
        if !root.arrangedSubviews.isEmpty { let line = NSBox(); line.boxType = .separator; root.addArrangedSubview(line) }
        let group = NSStackView(); group.orientation = .vertical; group.alignment = .leading; group.spacing = 8
        let heading = QuietStyle.label(title, size: 12); heading.font = .systemFont(ofSize: 12, weight: .medium)
        group.addArrangedSubview(heading)
        for view in views { group.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true }
        root.addArrangedSubview(group)
    }
}

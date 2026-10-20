import AppKit

// Compile alongside the app with -D DEBUG -D LAYOUT_TEST. These checks construct
// an offscreen window only; no keychain, microphone, hotkeys, or network are used.
@main
@MainActor
struct LayoutRegression {
    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }

    static func main() {
        _ = NSApplication.shared
        let delegate = SecureProbe()
        let window = delegate.makeWindow()
        delegate.showRecoveryLayoutTest()
        let content = window.contentView!
        let views = descendants(content)
        let buttons = views.compactMap { $0 as? NSButton }
        let copy = buttons.first { $0.title == "复制最新结果" }!
        let insert = buttons.first { $0.title == "尝试插入最新结果" }!
        let compatibility = buttons.first { $0.title == "兼容粘贴（2 秒）" }!
        let recovery = ["重试转写（重新上传）", "另存待重试录音…", "删除待重试录音"].map { title in buttons.first { $0.title == title }! }
        let toggles = ["展开用量与费用预估", "首次使用：保存自己的百炼 API Key", "展开已完成的密钥迁移检查"]
            .map { title in buttons.first { $0.title == title }! }
        let labels = views.compactMap { $0 as? NSTextField }
        labels.first { $0.stringValue.hasPrefix("本次运行耗时：") }!.stringValue =
            "本次运行耗时：\n第 1 段：录音 20.6 秒｜ASR 2.0 秒｜整理 0.9 秒｜处理合计 2.9 秒\n第 2 段：录音 20.9 秒｜ASR 3.0 秒｜整理 0.9 秒｜处理合计 4.0 秒\n第 3 段：录音 9.3 秒｜ASR 1.5 秒｜整理 0.8 秒｜处理合计 2.3 秒"
        labels.first { $0.stringValue.hasPrefix("插入状态：") }!.stringValue =
            "插入状态：转写片段 3/3（120 秒）；云端说明：" + String(repeating: "详细错误信息。", count: 80)
        let sample = String(repeating: "这是一段用于验证换行和滚动的合成文字。", count: 20)
        for view in views.compactMap({ $0 as? NSTextView }) { view.string = sample }
        let bodyScroll = content.subviews.compactMap { $0 as? NSScrollView }.first!
        var checks = 0
        for size in [NSSize(width: 720, height: 520), NSSize(width: 850, height: 770), NSSize(width: 1100, height: 900)] {
            window.setContentSize(size)
            // Gray-code order exercises every disclosure combination with one toggle at a time.
            var previousMask = 0
            for index in 0..<8 {
                let mask = index ^ (index >> 1)
                let changed = mask ^ previousMask
                for bit in 0..<3 where changed & (1 << bit) != 0 { toggles[bit].performClick(nil) }
                previousMask = mask
                content.layoutSubtreeIfNeeded()
                for button in [copy, insert, compatibility] + recovery {
                    let frame = button.convert(button.bounds, to: content)
                    require(content.bounds.contains(frame), "Recovery button clipped at \(size), disclosure \(mask): \(frame)")
                    require(frame.width > 60 && frame.height > 15, "Recovery button collapsed")
                }
                require(bodyScroll.frame.height > 120, "Scrollable body collapsed")
                let document = bodyScroll.documentView!
                require(abs(document.frame.width - bodyScroll.contentView.bounds.width) < 1, "Body requires horizontal scrolling")
                if mask == 7 {
                    require(document.frame.height > bodyScroll.contentView.bounds.height, "Expanded content must be scrollable")
                }
                for text in views.compactMap({ $0 as? NSTextView }) {
                    require(text.bounds.width > 500, "Result text has no usable width")
                    require(text.textContainer!.containerSize.width <= text.bounds.width + 1, "Result text does not wrap")
                }
                checks += 1
            }
            // Gray-code's last mask is 4; return to the collapsed baseline.
            toggles[2].performClick(nil)
        }
        print("PASS: \(checks) window/disclosure layouts; copy and insert remain visible, body scrolls, result text wraps.")
    }
}

import AppKit
import AVFoundation
import ApplicationServices
import LocalAuthentication
import Security
import UniformTypeIdentifiers

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private struct UsageDay: Codable {
    var asrInput = 0
    var asrOutput = 0
    var textInput = 0
    var textOutput = 0
    var audioSeconds = 0.0
    var outputCharacters = 0
    var asrCalls = 0
    var textCalls = 0
    var callsWithoutTokens = 0

    var asrCost: Double { (Double(asrInput) * 0.8 + Double(asrOutput) * 2.7) / 1_000_000 }
    var textCost: Double { (Double(textInput) * 0.8 + Double(textOutput) * 2.7) / 1_000_000 }

    mutating func add(_ other: UsageDay) {
        asrInput += other.asrInput
        asrOutput += other.asrOutput
        textInput += other.textInput
        textOutput += other.textOutput
        audioSeconds += other.audioSeconds
        outputCharacters += other.outputCharacters
        asrCalls += other.asrCalls
        textCalls += other.textCalls
        callsWithoutTokens += other.callsWithoutTokens
    }
}

@MainActor
final class SecureProbe: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let account = "mini-typeless"
    private let oldService = "MiniTypeless-Bailian-ASR"
    private let newService = "MiniTypeless-Bailian-TouchID-v1"
    private let dummyService = "MiniTypeless-Secure-Dummy-v1"
    private let dummy = Data("Mini Typeless 假数据；不是 API Key".utf8)
    private let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
    private let refinementModel = "qwen3.8-flash"
    private let recording: RecordingController
    private let pipeline: DictationPipeline
    private var lifecycle = SessionLifecycle()
    private let requestMicrophone: (@escaping @Sendable (Bool) -> Void) -> Void
    private let diagnostics: DiagnosticLog
    private var recordingStartTarget: InsertionDestination?
    private var recordingTarget: InsertionDestination?
    private var window: NSWindow!
    private var status: LiveStatusField!
    private var resultUI: ResultWindow!
    private var presentation = PresentationState()
    private var settingsNotice = QuietStyle.label("")
    private var settingsWindow: NSWindow?
    private var settingsUI: SettingsWindow?
    private var helpWindow: NSWindow?
    private var developerWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var hud: StatusHUD?
    private var hudTimer: Timer?
    private var showHUD = false
    private var timingView: NSTextField!
    private var usageToggle = NSButton()
    private var usageTools = NSStackView()
    private var usageView = NSTextField()
    private static let usageStorageKey = "MiniTypeless.UsageByDay.v1"
    private let persistUsage: (Data) -> Void
    private var usageByDay: [String: UsageDay] = [:]
    private var timingHistory: [String] = []
    private var resultView = NSTextView()
    private var latestView = NSTextView()
    private var latestSuccess: String?
    private var copyButton = NSButton()
    private var clearButton = NSButton()
    private var insertButton = NSButton()
    private var compatibilityInsertButton = NSButton()
    private var compatibilityPasteCheck = NSButton()
    private var insertionStatus = NSTextField(wrappingLabelWithString: "插入状态：尚未尝试。")
    private var autoInsertCheck = NSButton()
    private var insertionPending = false
    private var insertionGeneration = 0
    private var interactionSerial = 0
    private let supportedInsertApps = InsertionDestinationPolicy.supported
    private var recordButton = NSButton()
    private var processButton = NSButton()
    private var cancelButton = NSButton()
    private var deleteButton = NSButton()
    private var legacyTools = NSStackView()
    private var legacyToggle = NSButton()
    private var keySetupTools = NSStackView()
    private var keySetupToggle = NSButton()
    private var keyInput = NSSecureTextField()
    private var hotkeyMonitors: [Any] = []
    private var hotkeyArmed = false
    private var hotkeyDirty = false
    private var micPermissionPending = false
    private var micPermissionGeneration = 0
    private var activeTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var recoveryPending = false
    private var recoveryTools = NSStackView()
    private var retryButton = NSButton()
    private var exportAudioButton = NSButton()
    private var discardRecoveryButton = NSButton()
    private var currentRaw: String?
    private var buttons: [NSButton] = []
    private var busy = false
    private var dummyValidated = false
    private var sessionKey: String?
    #if DEBUG
    private var diagnosticRunning = false
    private var diagnosticView = NSTextView()
    private var diagnosticReportURL: URL?
    private var evaluationTask: Task<Void, Never>?
    private var evaluationButton = NSButton()
    private var evaluationCancelButton = NSButton()
    #endif

    private let refinementPrompt = """
    你是中文口述文字整理器。下面是待整理文本，请依照如下规则进行忠实整理，最后返回整理后的文字：
    1. 默认忠实保留原文的措辞、口语风格、语气和句子顺序，只在明显重复、改口时改写，不要为了简练而改写原本通顺的句子；
    2. 如果确有必要进行改写，需要在保留原意的基础上，以更整洁、干净的方式呈现语句，不修改任何含义，譬如删除语气词“呃、呀、吧、然后、就是”；
    3. 当有明显引用、注释的表述出现时，增加标点、括号、引号等，使意思更清晰，便于理解；
    4. 有明显的意思分层时，自然分段；仅对明确并列的步骤或条目编号。
    """

    init(recording: RecordingController? = nil, pipeline: DictationPipeline? = nil, persistUsage: ((Data) -> Void)? = nil, diagnostics: DiagnosticLog? = nil,
         requestMicrophone: ((@escaping @Sendable (Bool) -> Void) -> Void)? = nil) {
        self.recording = recording ?? RecordingController()
        self.requestMicrophone = requestMicrophone ?? { AVCaptureDevice.requestAccess(for: .audio, completionHandler: $0) }
        self.pipeline = pipeline ?? DictationPipeline()
        #if LAYOUT_TEST
        self.diagnostics = diagnostics ?? DiagnosticLog(enabled: false)
        #else
        self.diagnostics = diagnostics ?? DiagnosticLog()
        #endif
        self.persistUsage = persistUsage ?? { UserDefaults.standard.set($0, forKey: SecureProbe.usageStorageKey) }
        super.init()
        configureRecording()
    }

    #if LAYOUT_TEST
    func prepareWorkflowTest() {
        sessionKey = "synthetic-test-key"
        if presentation.phase == .locked { presentation.phase = .idle }
        autoInsertCheck.state = .off
    }
    func startDiagnosticTest(cases: [ASRDiagnosticCase], reportURL: URL) {
        startASRDiagnostics(cases: cases, reportURL: reportURL)
    }
    var diagnosticTestReport: String { diagnosticView.string }
    func stopWorkflowTest() { toggleRecording() }
    func retryWorkflowTest() { processRecording() }
    func deleteWorkflowTest() { deleteRecording() }
    var recoveryTestPending: Bool { recoveryPending }
    var presentationTestState: PresentationState { presentation }
    var resultTestUI: ResultWindow { resultUI }
    func setPresentationTestState(_ value: PresentationState) { presentation = value; refreshPresentation() }
    func showSettingsTest() { showSettings() }
    var settingsTestWindow: NSWindow? { settingsWindow }
    var settingsTestUI: SettingsWindow? { settingsUI }
    func setUsageTest() {
        usageByDay = [dayKey(): UsageDay(asrInput: 1_000_000, textOutput: 1_000_000, audioSeconds: 120)]
        refreshUsageView()
    }
    func toggleUsageTest() { toggleUsage() }
    func toggleKeySetupTest() { toggleKeySetup() }
    func emptyKeyFeedbackTest() { keyInput.stringValue = ""; saveOwnKey() }
    func setStatusTest(_ value: String) { status.stringValue = value }
    func showRecoveryLayoutTest() { recoveryTools.isHidden = false }
    func cancelWorkflowTest() { cancelProcessing() }
    func sleepWorkflowTest() { handleSleep() }
    func wakeWorkflowTest() { handleWake() }
    var unlockedWorkflowTest: Bool { sessionKey != nil }
    var deferredWorkflowTest: Bool { lifecycle.deferredAudio != nil }
    var workflowTestState: (busy: Bool, result: String?, raw: String?, status: String) {
        (busy, latestSuccess, currentRaw, status.stringValue)
    }
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        diagnostics.record(.launch)
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            diagnostics.record(.duplicateInstance)
            let alert = NSAlert()
            alert.messageText = "Mini Typeless 已在运行"
            alert.informativeText = "请先退出另一份程序，再打开这一份。多个副本可能同时响应快捷键。"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        clearAudio()
        loadUsage()
        window = makeWindow()
        installPresentationSurfaces()
        installHotkeyMonitors()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        window.makeKeyAndOrderFront(nil)
        diagnostics.record(.ready)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Constructing the window separately lets layout tests run without hotkeys,
    // microphone access, keychain reads, or cloud requests.
    func makeWindow() -> NSWindow {
        resultUI = ResultWindow()
        window = resultUI.window
        window.delegate = self
        status = LiveStatusField(wrappingLabelWithString: "准备就绪。先用 Touch ID 解锁本次运行。")
        status.font = .systemFont(ofSize: 13)
        status.changed = { [weak self] in self?.refreshPresentation() }
        timingView = NSTextField(wrappingLabelWithString: "本次运行耗时：尚无完成的录音。")
        copyButton = resultUI.copy; bind(copyButton, #selector(copyCurrentResult))
        insertButton = resultUI.insert; bind(insertButton, #selector(insertLatestResult))
        retryButton = resultUI.retry; bind(retryButton, #selector(processRecording))
        exportAudioButton = resultUI.export; bind(exportAudioButton, #selector(exportRecoveryAudio))
        discardRecoveryButton = resultUI.discard; bind(discardRecoveryButton, #selector(deleteRecording))
        recoveryTools = resultUI.recovery
        cancelButton = resultUI.cancel; bind(cancelButton, #selector(cancelProcessing))
        recordButton = resultUI.record; bind(recordButton, #selector(toggleRecording))
        bind(resultUI.unlock, #selector(unlockSessionKey))
        bind(resultUI.close, #selector(hideResultWindow))
        bind(resultUI.settings, #selector(showSettings))
        bind(resultUI.more, #selector(showResultMenu))
        bind(resultUI.previousToggle, #selector(togglePreviousResult))
        bind(resultUI.previousCopy, #selector(copyPreviousResult))
        autoInsertCheck = NSButton(checkboxWithTitle: "整理成功后尝试插入原输入框", target: self, action: #selector(autoInsertSettingChanged))
        autoInsertCheck.state = .on
        compatibilityPasteCheck = NSButton(checkboxWithTitle: "兼容模式：无焦点信息时仍粘贴", target: nil, action: nil)
        compatibilityPasteCheck.state = .off
        compatibilityInsertButton = NSButton(title: "兼容粘贴（2 秒）", target: self, action: #selector(compatibilityInsertLatestResult))
        copyButton.isEnabled = false
        refreshPresentation()
        return window
    }

    private func bind(_ button: NSButton, _ action: Selector) { button.target = self; button.action = action }

    private func refreshPresentation() {
        guard let resultUI else { return }
        resultUI.render(presentation, busy: busy, recoveryAvailable: recoveryPending && recording.completed != nil && !lifecycle.isSleeping,
                        insertionPending: insertionPending, detailMessage: status?.stringValue ?? "")
        if showHUD { hud?.update(presentation, sleeping: lifecycle.isSleeping) }
        statusItem?.button?.toolTip = "Mini Typeless · " + presentation.title
        statusItem?.button?.contentTintColor = QuietStyle.color(presentation.phase)
    }

    @objc private func showResultWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func hideResultWindow() { window.close() }
    @objc private func togglePreviousResult() { resultUI.previousExpanded.toggle(); refreshPresentation() }
    @objc private func copyCurrentResult() { copyText(presentation.copyText, message: presentation.result == nil ? "原文已复制" : "文字已复制") }
    @objc private func copyPreviousResult() { copyText(presentation.previous?.text, message: "上次成功文字已复制") }
    private func copyText(_ text: String?, message: String) {
        guard let text else { return }
        let board = NSPasteboard.general; board.clearContents()
        resultUI.feedback.stringValue = board.setString(text, forType: .string) ? message : "复制失败，请重新尝试"
        resultUI.feedback.isHidden = false
    }

    @objc private func showResultMenu() {
        let menu = NSMenu()
        for (title, action) in [("本次详情与原始转写", #selector(showHelp)), ("设置与用量", #selector(showSettings)), ("兼容粘贴（2 秒）", #selector(compatibilityInsertLatestResult)), ("清空保存的文字", #selector(clearLatestResult))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self
            if action == #selector(compatibilityInsertLatestResult) { item.isEnabled = presentation.result != nil && !busy && !recording.isRecording && !insertionPending }
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: resultUI.more.bounds.maxY), in: resultUI.more)
    }

    private func toolWindow(_ title: String) -> (NSWindow, NSStackView) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.appearance = InterfaceTheme.load().appearance
        w.title = title; w.isReleasedWhenClosed = false; w.contentMinSize = NSSize(width: 570, height: 450)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; w.contentView = scroll
        let document = FlippedView(); document.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = document
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(stack)
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)])
        w.center(); return (w, stack)
    }
    private func fitTools(_ stack: NSStackView) {
        for v in stack.arrangedSubviews { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }
    @objc private func changeInterfaceTheme(_ sender: NSPopUpButton) {
        guard InterfaceTheme.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        let theme = InterfaceTheme.allCases[sender.indexOfSelectedItem]
        theme.save()
        for window in [window, settingsWindow, helpWindow, developerWindow, hud?.panel].compactMap({ $0 }) {
            window.appearance = theme.appearance
        }
        refreshPresentation()
    }
    @objc private func showSettings() {
        if settingsWindow == nil {
            let ui = SettingsWindow(autoInsert: autoInsertCheck, compatibility: compatibilityPasteCheck, keyInput: keyInput)
            settingsUI = ui; settingsWindow = ui.window
            ui.themePicker.target = self; ui.themePicker.action = #selector(changeInterfaceTheme(_:))
            bind(ui.unlock, #selector(unlockSessionKey)); bind(ui.permissions, #selector(checkHotkeyPermission))
            keySetupToggle = ui.keyToggle; keySetupTools = ui.keyTools
            bind(keySetupToggle, #selector(toggleKeySetup)); bind(ui.saveKey, #selector(saveOwnKey))
            settingsNotice = ui.notice
            usageToggle = ui.usageToggle; usageTools = ui.usageTools; usageView = ui.usageDetails
            bind(usageToggle, #selector(toggleUsage)); refreshUsageView()
            bind(ui.help, #selector(showHelp)); bind(ui.quit, #selector(quitApp))
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showHelp() {
        if helpWindow == nil {
            let (w, root) = toolWindow("诊断与帮助"); helpWindow = w
            root.addArrangedSubview(QuietStyle.label("本次详情", size: 17)); root.addArrangedSubview(status)
            root.addArrangedSubview(insertionStatus); root.addArrangedSubview(timingView)
            root.addArrangedSubview(QuietStyle.label("原始转写与处理详情", size: 17))
            let raw = QuietStyle.textScroll(resultView); raw.heightAnchor.constraint(equalToConstant: 220).isActive = true; root.addArrangedSubview(raw)
            _ = addButton("打开本地诊断日志", #selector(openDiagnosticLogs), to: root)
            root.addArrangedSubview(QuietStyle.label("日志只记录阶段和错误码，不记录音频、文字或密钥。文字只在本次运行内保留。关闭窗口不退出；退出会清除未另存录音和内存中的文字。", size: 12))
            root.addArrangedSubview(QuietStyle.label("UI 预览版 · 2026-10-23", size: 12))
            #if DEBUG
            _ = addButton("开发工具…", #selector(showDeveloperTools), to: root)
            #endif
            fitTools(root)
        }
        helpWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    #if DEBUG
    @objc private func showDeveloperTools() {
        if developerWindow == nil {
            let (w, root) = toolWindow("开发工具（会产生云端用量）"); developerWindow = w
            evaluationButton = addButton("运行 30 条文字整理测试", #selector(runPromptEvaluation), to: root)
            evaluationCancelButton = addButton("取消文字测试", #selector(cancelPromptEvaluation), to: root)
            buttons.append(addButton("检测静音转写（上传合成音频）", #selector(runASRDiagnostics), to: root))
            _ = addButton("取消当前处理", #selector(cancelProcessing), to: root)
            let report = QuietStyle.textScroll(diagnosticView); report.heightAnchor.constraint(equalToConstant: 180).isActive = true; root.addArrangedSubview(report)
            root.addArrangedSubview(QuietStyle.label("历史密钥迁移检查（正常使用无需执行）"))
            buttons.append(addButton("1. 用假数据验证此程序", #selector(testDummy), to: root))
            buttons.append(addButton("2. 复制旧密钥到 Touch ID 项目", #selector(migrate), to: root))
            buttons.append(addButton("3. 用新密钥调用一次百炼", #selector(testAPI), to: root))
            fitTools(root); setBusy(busy)
        }
        developerWindow?.makeKeyAndOrderFront(nil)
    }
    #endif
    @objc private func quitApp() { NSApp.terminate(nil) }

    private func installPresentationSurfaces() {
        hud = StatusHUD(); bind(hud!.open, #selector(showResultWindow))
        hudTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if let self, self.showHUD, self.presentation.phase == .recording { self.hud?.update(self.presentation, sleeping: self.lifecycle.isSleeping) } }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Mini Typeless")
        let menu = NSMenu()
        for (title, action) in [("查看结果", #selector(showResultWindow)), ("设置与用量", #selector(showSettings)), ("诊断与帮助", #selector(showHelp)), ("退出 Mini Typeless", #selector(quitApp))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        statusItem?.menu = menu
        let main = NSMenu(); let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appMenu.addItem(NSMenuItem(title: "退出 Mini Typeless", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")); appItem.submenu = appMenu
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); main.addItem(editItem)
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        edit.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        NSApp.mainMenu = main
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        diagnostics.record(.reopenRequested)
        if !flag, let window {
            window.makeKeyAndOrderFront(nil)
            diagnostics.record(.windowReopened)
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        diagnostics.record(.windowClosed)
    }

    @objc private func openDiagnosticLogs() {
        guard !diagnostics.writeFailed,
              NSWorkspace.shared.open(diagnostics.directory) else {
            status.stringValue = "诊断日志暂不可用，请检查本机日志目录的权限或磁盘空间；录音功能不受影响。"
            return
        }
    }

    @objc private func handleWake() {
        diagnostics.record(.wake)
        let wasSleeping = lifecycle.isSleeping
        let deferred = lifecycle.wake()
        guard wasSleeping else { return }
        if let deferred, recording.completed?.url == deferred, !busy {
            diagnostics.record(.wakeProcessingStarted)
            recoveryPending = false // First upload of this sleep-ended take, not a retry.
            processRecording()
        } else {
            setBusy(busy)
            showInsertionStatus(sessionKey == nil
                ? "已唤醒；请先用 Touch ID 解锁本次运行，再开始录音。"
                : "已唤醒，可以按 Fn 开始录音。新录音成功开始会自动替换待重试录音。")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        diagnostics.record(.terminationRequested)
        lifecycle.invalidateDeferredAudio()
        #if DEBUG
        evaluationTask?.cancel()
        evaluationTask = nil
        #endif
        hudTimer?.invalidate(); hudTimer = nil; hud?.hide()
        sessionKey = nil
        insertionGeneration += 1
        insertionPending = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        hotkeyMonitors.forEach { NSEvent.removeMonitor($0) }
        micPermissionGeneration += 1
        activeRequestID = nil
        activeTask?.cancel()
        activeTask = nil
        clearAudio()
        diagnostics.record(.cleanTermination)
    }

    private func addButton(_ title: String, _ action: Selector, to root: NSStackView) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        root.addArrangedSubview(button)
        return button
    }

    private func configureResultView(_ view: NSTextView) {
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    }

    @objc private func toggleLegacyTools() {
        let expanded = legacyTools.isHidden
        legacyTools.isHidden = !expanded
        legacyToggle.title = expanded ? "收起密钥迁移检查" : "展开已完成的密钥迁移检查"
        updateContentLayout()
    }

    @objc private func toggleKeySetup() {
        let expanded = keySetupTools.isHidden
        keySetupTools.isHidden = !expanded
        keySetupToggle.title = expanded ? "收起" : "设置"
        keySetupToggle.image = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down", accessibilityDescription: nil)
        updateContentLayout()
    }

    private func updateContentLayout() {
        settingsWindow?.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
    }

    @objc private func toggleUsage() {
        let expanded = usageTools.isHidden
        usageTools.isHidden = !expanded
        usageToggle.title = expanded ? "收起明细" : "查看明细"
        usageToggle.image = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down", accessibilityDescription: nil)
        if expanded { refreshUsageView() }
        updateContentLayout()
    }

    private func loadUsage() {
        guard let data = UserDefaults.standard.data(forKey: Self.usageStorageKey),
              let saved = try? JSONDecoder().decode([String: UsageDay].self, from: data) else { return }
        usageByDay = saved
    }

    private func dayKey(_ date: Date = Date()) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func recordUsage(_ response: [String: Any], asr: Bool, audioSeconds: Double = 0) {
        let usage = response["usage"] as? [String: Any]
        let input = (usage?[asr ? "input_tokens" : "prompt_tokens"] as? NSNumber)?.intValue
        let output = (usage?[asr ? "output_tokens" : "completion_tokens"] as? NSNumber)?.intValue
        var change = UsageDay()
        if asr {
            change.asrCalls = 1
            change.audioSeconds = audioSeconds
            change.asrInput = max(0, input ?? 0)
            change.asrOutput = max(0, output ?? 0)
        } else {
            change.textCalls = 1
            change.textInput = max(0, input ?? 0)
            change.textOutput = max(0, output ?? 0)
        }
        if input == nil || output == nil { change.callsWithoutTokens = 1 }
        updateUsage(change)
    }

    private func recordOutputCharacters(_ count: Int) {
        var change = UsageDay()
        change.outputCharacters = count
        updateUsage(change)
    }

    private func updateUsage(_ change: UsageDay) {
        let key = dayKey()
        var day = usageByDay[key] ?? UsageDay()
        day.add(change)
        usageByDay[key] = day
        if let data = try? JSONEncoder().encode(usageByDay) {
            persistUsage(data)
        }
        refreshUsageView()
    }

    private func refreshUsageView() {
        let today = usageByDay[dayKey()] ?? UsageDay()
        let monthKey = String(dayKey().prefix(7))
        var month = UsageDay()
        for (date, day) in usageByDay where date.hasPrefix(monthKey) { month.add(day) }
        let currentDay = Calendar.current.component(.day, from: Date())
        let firstRecordedDay = usageByDay.keys.filter { $0.hasPrefix(monthKey) }.min()
        let firstDay = firstRecordedDay.flatMap { Int($0.suffix(2)) } ?? currentDay
        let elapsedDays = max(1, currentDay - firstDay + 1)
        let daysInMonth = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
        let projected = (month.asrCost + month.textCost) * Double(daysInMonth) / Double(elapsedDays)
        let todayLine = "今天：录音 \(String(format: "%.1f", today.audioSeconds / 60)) 分钟｜输出 \(today.outputCharacters) 字｜ASR \(today.asrInput)/\(today.asrOutput) Token｜整理 \(today.textInput)/\(today.textOutput) Token｜原价约 ¥\(String(format: "%.4f", today.asrCost + today.textCost))"
        let monthLine = "本月：录音 \(String(format: "%.1f", month.audioSeconds / 60)) 分钟｜输出 \(month.outputCharacters) 字｜ASR \(month.asrInput)/\(month.asrOutput) Token｜整理 \(month.textInput)/\(month.textOutput) Token"
        let costLine = "本月原价估算：ASR ¥\(String(format: "%.4f", month.asrCost)) + 整理 ¥\(String(format: "%.4f", month.textCost)) = ¥\(String(format: "%.4f", month.asrCost + month.textCost))；按已记录日均推算整月约 ¥\(String(format: "%.2f", projected))"
        let noteLine = "统计自本版启用后开始；\(month.callsWithoutTokens) 次成功请求未返回完整 Token，未计入价格。"
        usageView.stringValue = [todayLine, monthLine, costLine, noteLine].joined(separator: "\n")
        settingsUI?.todaySummary.stringValue = String(format: "%.1f 分钟 · ¥%.4f", today.audioSeconds / 60, today.asrCost + today.textCost)
        settingsUI?.monthSummary.stringValue = String(format: "%.1f 分钟 · ¥%.4f", month.audioSeconds / 60, month.asrCost + month.textCost)
    }

    private func showSettingsFeedback() {
        settingsNotice.stringValue = status.stringValue
        settingsNotice.isHidden = settingsNotice.stringValue.isEmpty
        updateContentLayout()
    }

    @objc private func saveOwnKey() {
        defer { showSettingsFeedback() }
        let key = keyInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            status.stringValue = "请先粘贴你自己的百炼 API Key。"
            return
        }
        let code = addProtected(Data(key.utf8), service: newService)
        keyInput.stringValue = ""
        switch code {
        case errSecSuccess:
            status.stringValue = "API Key 已存入本机 Touch ID 钥匙串。请点击上方按钮解锁本次运行。"
        case errSecDuplicateItem:
            status.stringValue = "本机已有受保护的 API Key；没有覆盖。请直接解锁本次运行。"
        default:
            status.stringValue = "API Key 保存失败（系统返回码 \(code)）；请检查签名和钥匙串设置。"
        }
    }

    @objc private func autoInsertSettingChanged() {
        defer { showSettingsFeedback() }
        status.stringValue = autoInsertCheck.state == .on
            ? "本次运行已启用整理后尝试插入。停止录音时请选择目标输入框；处理期间可回到本窗口查看进度。"
            : "本次运行已关闭整理后尝试插入。结果仍可手动复制或插入。"
    }

    @objc private func copyLatestResult() {
        guard let latestSuccess else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(latestSuccess, forType: .string) {
            status.stringValue = "最新成功结果已复制。剪贴板内容已由你这次点击替换。"
        } else {
            status.stringValue = "复制失败；最新成功结果仍留在窗口中。"
        }
    }

    @objc private func clearLatestResult() {
        guard !insertionPending else {
            status.stringValue = "请等待插入检查结束，再清空结果。"
            return
        }
        latestSuccess = nil
        presentation.result = nil; presentation.previous = nil; presentation.raw = nil
        if !busy && !recording.isRecording { presentation.phase = sessionKey == nil ? .locked : .idle }
        latestView.string = ""
        copyButton.isEnabled = false
        clearButton.isEnabled = false
        insertButton.isEnabled = false
        compatibilityInsertButton.isEnabled = false
        status.stringValue = "最新成功结果已从窗口清空；剪贴板未改变。"
    }

    private func setInsertionButtonsEnabled(_ enabled: Bool) {
        let available = enabled && !busy && !recording.isRecording && !micPermissionPending
        insertButton.isEnabled = available
        compatibilityInsertButton.isEnabled = available && presentation.result != nil
        refreshPresentation()
    }

    private func insertionFallback(_ message: String) {
        presentation.phase = .needsCopy
        diagnostics.record(.insertionSkipped)
        insertionPending = false
        setInsertionButtonsEnabled(latestSuccess != nil)
        showInsertionStatus(message + " 结果仍在下方；可点击“复制最新结果”。")
    }

    private func showInsertionStatus(_ message: String) {
        status.stringValue = message
        insertionStatus.stringValue = "插入状态：" + message
    }

    @objc private func insertLatestResult() {
        guard presentation.result != nil, latestSuccess != nil, !insertionPending, !busy, !recording.isRecording, !micPermissionPending else { return }
        insertionGeneration += 1
        let token = insertionGeneration
        insertionPending = true
        setInsertionButtonsEnabled(false)
        showInsertionStatus("请在 2 秒内切到 Codex、Obsidian 或 Claude 的目标输入框；正在等待你选择位置。")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self, self.insertionGeneration == token else { return }
            self.queryInsertionTarget(token: token)
        }
    }

    private func attemptAutomaticInsertion(target: InsertionDestination?) {
        guard autoInsertCheck.state == .on else {
            showInsertionStatus("自动插入已关闭，结果可复制或手动插入。")
            return
        }
        guard latestSuccess != nil, !insertionPending, !busy else {
            showInsertionStatus("整理成功，但插入检查未启动；结果仍在下方，可手动插入。")
            return
        }
        insertionGeneration += 1
        let token = insertionGeneration
        insertionPending = true
        setInsertionButtonsEnabled(false)
        let decision = InsertionDestinationPolicy.decide(target: target, current: InsertionDestination.current(),
                                                         ownPID: ProcessInfo.processInfo.processIdentifier)
        switch decision {
        case .reject(let message): insertionFallback(message)
        case .current:
            showInsertionStatus("整理完成；正在确认目标输入框，确认后只插入一次。")
            queryInsertionTarget(token: token)
        case .restore(let target):
            guard let app = NSRunningApplication(processIdentifier: target.pid),
                  app.bundleIdentifier == target.bundleID, !app.isTerminated else {
                insertionFallback("原接收应用已退出，未插入。")
                return
            }
            let serial = interactionSerial
            showInsertionStatus("整理完成；正在返回“\(target.name)”检查输入框。")
            guard app.activate(options: []) else {
                insertionFallback("无法返回原接收应用，未插入。")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, self.insertionGeneration == token, self.insertionPending else { return }
                guard self.interactionSerial == serial, InsertionDestination.current() == target else {
                    self.insertionFallback("返回目标期间输入位置发生变化，未插入。")
                    return
                }
                self.queryInsertionTarget(token: token)
            }
        }
    }

    @objc private func compatibilityInsertLatestResult() {
        guard presentation.result != nil, latestSuccess != nil, !insertionPending, !busy, !recording.isRecording, !micPermissionPending else { return }
        guard AXIsProcessTrusted() else { insertionFallback("辅助功能权限未允许，未粘贴。"); return }
        insertionGeneration += 1
        let token = insertionGeneration
        insertionPending = true
        setInsertionButtonsEnabled(false)
        showInsertionStatus("请在 2 秒内切换并点击目标输入框；兼容粘贴不验证输入框，只请求粘贴，不发送。")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.insertionGeneration == token, self.insertionPending else { return }
            guard let front = NSWorkspace.shared.frontmostApplication,
                  let bundleID = front.bundleIdentifier, self.supportedInsertApps.contains(bundleID) else {
                self.insertionFallback("请先切到 Codex、Obsidian 或 Claude 的输入框；未粘贴。")
                return
            }
            let pid = front.processIdentifier
            let serial = self.interactionSerial
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.insertionGeneration == token, self.insertionPending else { return }
                guard self.interactionSerial == serial,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                    self.insertionFallback("等待粘贴期间输入位置发生变化，未粘贴。")
                    return
                }
                self.pasteLatestOnce(pid: pid, token: token, method: "手动兼容模式（未验证输入框）")
            }
        }
    }

    private func queryInsertionTarget(token: Int) {
        guard AXIsProcessTrusted() else { insertionFallback("辅助功能权限未允许，未插入。"); return }
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier,
              supportedInsertApps.contains(bundleID) else {
            let app = InsertionDestination.current()
            insertionFallback("当前应用“\(app?.name ?? "未知")”（\(app?.bundleID ?? "未知")）尚未支持自动插入。")
            return
        }
        let pid = front.processIdentifier
        let serial = interactionSerial
        // A cold Electron accessibility tree can take longer than a single AX call.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, self.insertionGeneration == token, self.insertionPending else { return }
            self.insertionFallback("输入目标查询超时，未插入。")
        }
        inspectInsertionTarget(pid: pid, token: token, serial: serial, attempt: 0)
    }

    private func inspectInsertionTarget(pid: pid_t, token: Int, serial: Int, attempt: Int) {
        guard insertionGeneration == token, insertionPending else { return }
        guard interactionSerial == serial,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            insertionFallback("查询期间输入位置发生变化，未插入。")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let lookup = AXInputFocusLookup(pid: pid)
            if attempt == 0 { lookup.enableElectronAccessibility() }
            let deadline = Date().addingTimeInterval(1.2)
            let first = lookup.resolve(deadline: deadline)
            var confirmedSource: String?
            var failure = ""
            var canRetry = false
            var canUseCompatibility = false
            switch first {
            case .found(let initial):
                if case .found(let current) = lookup.resolve(deadline: deadline), initial.matches(current) {
                    confirmedSource = current.source
                } else {
                    failure = "输入框或光标未能通过第二次确认，未插入。"
                }
            case .unavailable:
                canRetry = true
                canUseCompatibility = lookup.appFocusCode == .noValue && lookup.systemFocusCode == .noValue
                failure = "应用和系统均未提供可确认的焦点（应用 \(lookup.appFocusCode.rawValue)，系统 \(lookup.systemFocusCode.rawValue)）；未自动插入。可点击“兼容粘贴（2 秒）”后选择输入框。"
            case .rejected:
                failure = "当前焦点不是可确认的普通输入框，未插入。"
            case .limitReached:
                canUseCompatibility = lookup.appFocusCode == .noValue && lookup.systemFocusCode == .noValue
                failure = "焦点查询达到时间或范围限制，未插入。可使用复制或兼容粘贴。"
            }
            DispatchQueue.main.async {
                guard let self = self, self.insertionGeneration == token, self.insertionPending else { return }
                guard self.interactionSerial == serial,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                    self.insertionFallback("查询期间输入位置发生变化，未插入。")
                    return
                }
                if let source = confirmedSource {
                    self.pasteLatestOnce(pid: pid, token: token, method: source)
                } else if canRetry, attempt == 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.inspectInsertionTarget(pid: pid, token: token, serial: serial, attempt: 1)
                    }
                } else {
                    if canUseCompatibility, self.compatibilityPasteCheck.state == .on,
                       InsertionDestinationPolicy.compatibilityApps.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "") {
                        self.pasteLatestOnce(pid: pid, token: token, method: "已启用的兼容模式（未验证输入框）")
                    } else {
                        self.insertionFallback(failure)
                    }
                }
            }
        }
    }

    private func pasteLatestOnce(pid: pid_t, token: Int, method: String) {
        guard let text = latestSuccess else { insertionFallback("结果已清空，未插入。"); return }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
            insertionFallback("无法生成粘贴事件，未插入。")
            return
        }
        let pasteboard = NSPasteboard.general
        guard pasteboard.types?.isEmpty != false || pasteboard.pasteboardItems != nil else {
            insertionFallback("无法完整保存当前剪贴板，未插入。")
            return
        }
        var saved: [[(NSPasteboard.PasteboardType, Data)]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var pairs: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    insertionFallback("无法完整保存当前剪贴板，未插入。")
                    return
                }
                pairs.append((type, data))
            }
            saved.append(pairs)
        }
        // Clipboard providers can take time to supply data. Recheck the destination
        // after that work, before replacing the pasteboard or posting a paste event.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            insertionFallback("准备剪贴板期间前台应用发生变化，未粘贴。")
            return
        }
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            let items = saved.map { pairs -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in pairs { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { pasteboard.writeObjects(items) }
            insertionFallback("临时剪贴板写入失败，未插入。")
            return
        }
        let writtenCount = pasteboard.changeCount
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
        diagnostics.record(.pasteRequested)
        presentation.phase = .pasteRequested
        // The AX lookup is finished. Keep the button disabled until clipboard restoration,
        // but do not let the lookup watchdog overwrite this outcome.
        insertionPending = false
        showInsertionStatus("已通过\(method)请求粘贴一次，未按发送键；若目标未出现文字，可点击“复制最新结果”。")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            if pasteboard.changeCount == writtenCount {
                pasteboard.clearContents()
                let items = saved.map { pairs -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, data) in pairs { item.setData(data, forType: type) }
                    return item
                }
                if !items.isEmpty { pasteboard.writeObjects(items) }
            }
            guard let self = self, self.insertionGeneration == token else { return }
            self.insertionPending = false
            self.setInsertionButtonsEnabled(self.latestSuccess != nil)
        }
    }

    private func installHotkeyMonitors() {
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            DispatchQueue.main.async { self?.handleHotkeyEvent(event) }
        }) {
            hotkeyMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handleHotkeyEvent(event)
            return event
        }) {
            hotkeyMonitors.append(monitor)
        }
    }

    @objc private func checkHotkeyPermission() {
        defer { showSettingsFeedback() }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        status.stringValue = trusted
            ? "快捷键权限已允许。Fn／地球键单独按下并松开可开始／停止录音。"
            : "请在系统设置→隐私与安全性→辅助功能中允许 Mini Typeless Secure，然后退出并重新运行。"
    }

    private func handleHotkeyEvent(_ event: NSEvent) {
        interactionSerial += 1
        guard AXIsProcessTrusted() else { return }
        if event.type != .flagsChanged {
            if hotkeyArmed { hotkeyDirty = true }
            return
        }
        let fnDown = event.modifierFlags.contains(.function)
        let other = !event.modifierFlags.intersection([.command, .control, .shift, .option]).isEmpty
        // kVK_Function = 0x3F. A standalone press/release triggers; combinations do not.
        if event.keyCode == 0x3F && fnDown && !hotkeyArmed {
            hotkeyArmed = true
            hotkeyDirty = other
        } else if hotkeyArmed && !fnDown {
            let trigger = !hotkeyDirty && !other && event.keyCode == 0x3F
            hotkeyArmed = false
            hotkeyDirty = false
            if trigger {
                toggleRecording()
            }
        } else if hotkeyArmed && other {
            hotkeyDirty = true
        }
    }

    @objc private func handleSleep() {
        guard lifecycle.beginSleep() else { return }
        diagnostics.record(.sleep, operation: activeRequestID)
        insertionGeneration += 1
        insertionPending = false
        #if DEBUG
        evaluationTask?.cancel()
        evaluationTask = nil
        evaluationButton.isEnabled = true
        evaluationCancelButton.isEnabled = false
        #endif
        // Keep the already-unlocked in-memory session until actual app exit.
        micPermissionGeneration += 1
        micPermissionPending = false
        if activeRequestID != nil { cancelProcessing() }
        // The stop callback observes isSleeping and defers this first upload.
        if recording.isRecording { recording.stop(.sleep) }
        if recording.completed != nil { recoveryPending = true }
        recordButton.title = "开始录音"
        setBusy(false)
        showInsertionStatus(lifecycle.deferredAudio != nil
            ? "已结束睡前录音，等待唤醒后自动转写。程序保持待机。"
            : "程序保持待机，唤醒后可继续使用；已中断的云端处理可手动重试，也可直接开始新录音。")
    }

    private func setBusy(_ value: Bool) {
        busy = value
        #if DEBUG
        evaluationButton.isEnabled = !value
        #endif
        buttons.forEach { $0.isEnabled = !value }
        recordButton.isEnabled = !value && !lifecycle.isSleeping && !micPermissionPending
        processButton.isEnabled = !value && !lifecycle.isSleeping && !recording.isRecording && recording.completed != nil
        cancelButton.isEnabled = value && activeRequestID != nil
        deleteButton.isEnabled = !value
        refreshRecoveryControls()
        setInsertionButtonsEnabled(latestSuccess != nil)
        refreshPresentation()
    }

    private func finishPipeline() {
        #if DEBUG
        diagnosticRunning = false
        #endif
        activeRequestID = nil
        activeTask = nil
        setBusy(false)
    }

    @objc private func cancelProcessing() {
        guard activeRequestID != nil else { return }
        diagnostics.record(.processingCancelled, operation: activeRequestID)
        activeRequestID = nil
        activeTask?.cancel()
        activeTask = nil
        #if DEBUG
        if diagnosticRunning {
            diagnosticRunning = false
            appendDiagnosticLine("已取消诊断；不再发出后续测试请求，迟到响应不写入报告。")
            setBusy(false)
            status.stringValue = "静音诊断已取消；已完成的报告保留，录音结果未改动。"
            return
        }
        #endif
        recoveryPending = recording.completed != nil
        presentation.phase = .cancelled
        setBusy(false)
        if let raw = currentRaw {
            resultView.string = "原始转写：\n\(raw)\n\n整理结果：\n未整理（已取消）"
        } else {
            resultView.string = ""
        }
        showInsertionStatus("已取消处理；录音保留到本次运行结束，可重试或另存。下一次成功开始录音会自动替换它。迟到结果不会显示。云端可能已处理，重试可能重复计费。")
    }

    private func clearAudio() {
        lifecycle.invalidateDeferredAudio()
        recording.discard()
        recoveryPending = false
        refreshRecoveryControls()
    }

    private func refreshRecoveryControls() {
        recoveryTools.isHidden = !recoveryPending
        let available = recoveryPending && recording.completed != nil && !busy && !lifecycle.isSleeping
        for button in [retryButton, exportAudioButton, discardRecoveryButton] { button.isEnabled = available }
    }

    @objc private func exportRecoveryAudio() {
        guard !busy, recoveryPending, recording.completed != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = "MiniTypeless-待重试录音.wav"
        panel.message = "另存本次录音。临时副本会在成功处理、主动删除或退出程序时清除。"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try recording.exportCompleted(to: destination)
            diagnostics.record(.audioExported)
            status.stringValue = "录音已另存；本次运行中的副本仍可重试。"
        } catch {
            diagnostics.record(.audioExportFailed, failure: .classify(error))
            status.stringValue = "录音另存失败（系统代码 \((error as NSError).code)）；临时副本仍保留，可重试另存。"
        }
    }

    private func configureRecording() {
        recording.onStopped = { [weak self] audio, reason in
            guard let self else { return }
            self.diagnostics.record(reason == .sleep ? .recordingPausedForSleep : (reason == .timeLimit ? .recordingLimitReached : .recordingStopped), seconds: audio.duration)
            self.recordingTarget = InsertionDestinationPolicy.capture(
                current: InsertionDestination.current(), started: self.recordingStartTarget,
                ownPID: ProcessInfo.processInfo.processIdentifier)
            self.buttons.forEach { $0.isEnabled = true }
            self.recordButton.title = "开始录音"
            self.processButton.isEnabled = true
            if self.lifecycle.isSleeping {
                self.presentation.phase = .waitingWake
                self.lifecycle.deferUntilWake(audio.url)
                self.recoveryPending = true
                self.setBusy(false)
                self.status.stringValue = "睡前录音已保留，唤醒后自动处理。"
                return
            }
            self.status.stringValue = reason == .timeLimit
                ? "已达到 10 分钟上限，正在自动转写并整理……"
                : "录音结束，正在自动转写并整理……"
            self.processRecording()
        }
        recording.onFailure = { [weak self] in
            guard let self else { return }
            self.presentation.phase = .failed
            self.diagnostics.record(.recordingFailed)
            self.recordButton.title = "开始录音"
            self.buttons.forEach { $0.isEnabled = true }
            self.processButton.isEnabled = false
            self.setInsertionButtonsEnabled(self.latestSuccess != nil)
            self.status.stringValue = "录音中断，未上传；请检查麦克风后重新录制。"
        }
    }

    @objc private func deleteRecording() {
        guard !busy else { return }
        diagnostics.record(.recordingDeleted)
        micPermissionGeneration += 1
        micPermissionPending = false
        clearAudio()
        recordButton.title = "开始录音"
        buttons.forEach { $0.isEnabled = true }
        setBusy(false)
        setInsertionButtonsEnabled(latestSuccess != nil)
        presentation.phase = sessionKey == nil ? .locked : .idle
        status.stringValue = "本次临时录音已删除；已另存的文件不受影响。"
    }

    @objc private func toggleRecording() {
        diagnostics.record(.recordingRequested)
        showHUD = true
        guard !busy, !insertionPending, !micPermissionPending, !lifecycle.isSleeping else { return }
        if recording.isRecording {
            recording.stop()
            return
        }
        guard sessionKey != nil else {
            diagnostics.record(.recordingBlockedLocked)
            showInsertionStatus("请先点击“用 Touch ID 解锁本次运行”，再按 Fn 开始录音；解锁会保持到程序退出。")
            return
        }
        // Capture before the asynchronous permission callback can change the foreground.
        recordingStartTarget = InsertionDestination.current().flatMap {
            $0.pid == ProcessInfo.processInfo.processIdentifier ? nil : $0
        }
        recordingTarget = nil
        micPermissionPending = true
        micPermissionGeneration += 1
        let permissionGeneration = micPermissionGeneration
        requestMicrophone { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, self.micPermissionGeneration == permissionGeneration else { return }
                self.micPermissionPending = false
                guard allowed else {
                    self.diagnostics.record(.microphoneDenied)
                    self.resultUI.feedback.isHidden = false
                    self.resultUI.feedback.stringValue = "麦克风权限未获允许；本次没有开始新录音。"
                    self.showInsertionStatus("麦克风权限未获允许，请到系统设置中检查。上一段待重试录音仍保留。")
                    self.hud?.notice("麦克风权限未获允许")
                    return
                }
                do {
                    let replaced = self.recording.completed != nil
                    try self.recording.start(replacingCompleted: true)
                    self.presentation.begin()
                    self.resultUI.feedback.isHidden = true
                    self.resultUI.previousExpanded = false
                    self.currentRaw = nil
                    self.resultView.string = ""
                    self.lifecycle.invalidateDeferredAudio()
                    self.recoveryPending = false
                    self.refreshRecoveryControls()
                    if replaced { self.diagnostics.record(.recordingReplaced) }
                    self.diagnostics.record(.recordingStarted)
                    self.recordButton.title = "停止录音"
                    self.buttons.forEach { $0.isEnabled = false }
                    self.processButton.isEnabled = false
                    self.setInsertionButtonsEnabled(false)
                    self.showInsertionStatus("正在录音，最长 10 分钟；再按 Fn 或达到上限后自动处理。若有上一段待重试录音，已自动替换。")
                } catch {
                    self.refreshRecoveryControls()
                    self.diagnostics.record(.recordingFailed, failure: .classify(error))
                    self.resultUI.feedback.isHidden = false
                    self.resultUI.feedback.stringValue = "录音未能启动，上一段内容仍保留。"
                    self.showInsertionStatus("录音启动失败，请检查麦克风；若有上一段待重试录音，仍为你保留。")
                    self.hud?.notice("录音未能启动")
                }
            }
        }
    }

    private func readProtected(_ service: String, reason: String) -> (OSStatus, Data?) {
        let context = LAContext()
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var item: CFTypeRef?
        let code = SecItemCopyMatching(query as CFDictionary, &item)
        return (code, item as? Data)
    }

    @objc private func unlockSessionKey() {
        guard !busy else { return }
        defer { showSettingsFeedback() }
        if sessionKey != nil {
            status.stringValue = "本次运行已经解锁，无需再次验证 Touch ID。"
            return
        }
        let (code, data) = readProtected(newService, reason: "解锁 Mini Typeless 本次运行使用的百炼 API Key")
        guard code == errSecSuccess, let data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            status.stringValue = code == errSecUserCanceled
                ? "已取消 Touch ID；密钥未读取，本次运行仍未解锁。"
                : "密钥读取失败（系统返回码 \(code)）；本次运行仍未解锁。"
            return
        }
        sessionKey = key
        if presentation.phase == .locked { presentation.phase = .idle }
        status.stringValue = "本次运行已解锁。之后录音处理复用内存中的密钥；退出程序后清除；Mac 睡眠不需要重新解锁。"
    }

    private func addProtected(_ data: Data, service: String) -> OSStatus {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &error) else {
            error?.release()
            return errSecParam
        }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessControl as String: access,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: data
        ]
        return SecItemAdd(attrs as CFDictionary, nil)
    }

    @objc private func testDummy() {
        let code = addProtected(dummy, service: dummyService)
        guard code == errSecSuccess || code == errSecDuplicateItem else {
            status.stringValue = "假数据写入失败（系统返回码 \(code)）。未接触真实密钥。"
            return
        }
        let (readCode, data) = readProtected(dummyService, reason: "验证此程序可用 Touch ID 读取假数据")
        dummyValidated = readCode == errSecSuccess && data == dummy
        status.stringValue = dummyValidated
            ? "第 1 步通过：假数据经 Touch ID 读回，内容一致。"
            : "假数据读取未通过（系统返回码 \(readCode)）。未接触真实密钥。"
    }

    private func readLegacy() -> (OSStatus, Data?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: oldService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let code = SecItemCopyMatching(query as CFDictionary, &item)
        return (code, item as? Data)
    }

    @objc private func migrate() {
        guard dummyValidated else {
            status.stringValue = "请先完成第 1 步的假数据验证；尚未读取旧密钥。"
            return
        }
        let (oldCode, oldData) = readLegacy()
        guard oldCode == errSecSuccess, let oldData = oldData, !oldData.isEmpty else {
            status.stringValue = "未读到旧密钥（系统返回码 \(oldCode)）。旧项目未改变。"
            return
        }
        let addCode = addProtected(oldData, service: newService)
        guard addCode == errSecSuccess || addCode == errSecDuplicateItem else {
            status.stringValue = "新项目写入失败（系统返回码 \(addCode)）。旧密钥保留。"
            return
        }
        let (newCode, newData) = readProtected(newService, reason: "验证新项目中的百炼 API Key")
        guard newCode == errSecSuccess, let newData = newData else {
            status.stringValue = "新项目读取未通过（系统返回码 \(newCode)）。旧密钥保留。"
            return
        }
        status.stringValue = newData == oldData
            ? "第 2 步通过：新旧密钥内容一致，旧密钥未删除。"
            : "新旧密钥内容不一致；未覆盖任一项目。请停止测试。"
    }

    @objc private func processRecording() {
        guard !busy, !insertionPending, !micPermissionPending, !lifecycle.isSleeping, !recording.isRecording, let audio = recording.completed else {
            status.stringValue = "没有可处理的已结束录音。"
            return
        }
        let wasRetry = recoveryPending
        recoveryPending = true
        refreshRecoveryControls()
        recordButton.isEnabled = true
        guard let key = sessionKey else {
            diagnostics.record(.processingBlockedLocked)
            status.stringValue = "本次运行尚未解锁；录音未上传。请先点击“用 Touch ID 解锁本次运行”，再点击转写并整理。"
            return
        }
        let chunks: [AudioChunk]
        do { chunks = try AudioChunks.split(Data(contentsOf: audio.url)) }
        catch {
            presentation.phase = .failed
            diagnostics.record(.audioInvalid, failure: .classify(error))
            status.stringValue = "录音为空、损坏或超过 10 分钟；未上传。副本保留，可另存检查，或主动删除后重新录制。"
            return
        }
        // Retain the original until success so a failed request can be retried
        // or exported. No automatic retry of these non-idempotent POST requests.
        let previousRaw = currentRaw
        presentation.phase = .transcribing
        let requestID = UUID()
        let target = recordingTarget
        let started = Date()
        let duration = chunks.reduce(0) { $0 + $1.duration }
        activeRequestID = requestID
        diagnostics.record(wasRetry ? .retryStarted : .processingStarted, operation: requestID, total: chunks.count, seconds: duration)
        if !wasRetry {
            currentRaw = nil
            resultView.string = ""
        }
        insertionStatus.stringValue = "插入状态：等待本次转写和整理完成。"
        setBusy(true)
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.pipeline.run(chunks: chunks, key: key, prompt: self.refinementPrompt) { event in
                    guard self.activeRequestID == requestID else { return }
                    switch event {
                    case .transcribing(let index, let total):
                        self.diagnostics.record(.transcribing, operation: requestID, index: index, total: total)
                        self.status.stringValue = "正在转写第 \(index)/\(total) 个音频片段；完成后会合并整理并尝试插入一次。"
                    case .emptyChunk(let index, let total):
                        self.diagnostics.record(.emptyChunk, operation: requestID, index: index, total: total)
                        self.status.stringValue = "第 \(index)/\(total) 个片段未识别到文字；继续处理其他片段。"
                    case .usage(let object, let asr, let seconds):
                        self.recordUsage(object, asr: asr, audioSeconds: seconds)
                    case .raw(let raw):
                        if !wasRetry || self.currentRaw == nil { self.currentRaw = raw }
                        self.presentation.raw = raw
                        self.presentation.rawComplete = false
                        self.refreshPresentation()
                        self.resultView.string = "已转写内容：\n\(raw)\n\n正在继续处理……"
                    case .refining:
                        self.presentation.rawComplete = true
                        self.presentation.phase = .refining
                        self.diagnostics.record(.refining, operation: requestID)
                        self.status.stringValue = "转写完成，正在整理全文……"
                    }
                }
                guard self.activeRequestID == requestID, !Task.isCancelled else { return }
                self.diagnostics.record(.processingSucceeded, operation: requestID)
                self.clearAudio()
                self.finishPipeline()
                self.currentRaw = result.raw
                self.resultView.string = "原始转写：\n\(result.raw)\n\n整理结果：\n\(result.refined)"
                self.latestSuccess = result.refined
                self.presentation.complete(result.refined)
                self.recordOutputCharacters(result.refined.count)
                self.latestView.string = result.refined
                self.copyButton.isEnabled = true
                self.clearButton.isEnabled = true
                self.setInsertionButtonsEnabled(true)
                let line = String(format: "第 %d 段：录音 %.1f 秒｜ASR %.1f 秒｜整理 %.1f 秒｜处理合计 %.1f 秒", self.timingHistory.count + 1, duration, result.asrSeconds, result.refinementSeconds, Date().timeIntervalSince(started))
                self.timingHistory.append(line)
                self.timingView.stringValue = "本次运行耗时：\n" + self.timingHistory.suffix(3).joined(separator: "\n")
                self.status.stringValue = "转写和整理完成；录音已删除。"
                if wasRetry {
                    self.showInsertionStatus("重试成功，录音临时副本已删除；结果保留在下方。请复制或点击“尝试插入最新结果”选择接收位置。")
                } else {
                    self.attemptAutomaticInsertion(target: target)
                }
            } catch {
                guard self.activeRequestID == requestID, !Task.isCancelled else { return }
                self.diagnostics.record(.processingFailed, operation: requestID, failure: .classify(error))
                if wasRetry, let previousRaw { self.currentRaw = previousRaw }
                self.finishPipeline()
                self.presentation.phase = .failed
                if self.presentation.raw == nil { self.presentation.raw = self.currentRaw }
                let message = DictationFailure.describe(error)
                    + "；本次未插入。录音保留到本次运行结束，可重试或另存；下一次成功开始录音或退出会删除临时副本。不会自动重试，手动重试可能重复计费。"
                if let raw = self.currentRaw {
                    self.resultView.string = "已转写内容（转写中断时可能不完整）：\n\(raw)\n\n本次未完成整理或检查，未插入。\n\(message)"
                } else {
                    self.resultView.string = message
                }
                self.showInsertionStatus(message)
            }
        }
    }

    private func refinementUserMessage(_ raw: String) -> String { DictationPipeline.userMessage(raw) }

    #if DEBUG
    private let evaluationCases: [(id: String, raw: String)] = [
        ("K01", "周五下午三点，哦不对，周六下午三点开会。"),
        ("K02", "预算是一千五，不是一万五。"),
        ("K03", "我不确定要不要取消预约。"),
        ("K04", "如果明天下雨，我们就改成线上。"),
        ("K05", "是两份文件，不是三份。"),
        ("K06", "这个方案可能可行，但我还没测试。"),
        ("K07", "不是发给张老师，是发给王老师。"),
        ("K08", "先不要提交，等我看完再说。"),
        ("K09", "原价二百，折后是一百八十。"),
        ("K10", "我预计十分钟，最多十五分钟。"),
        ("N01", "呃，我们先验证需求，然后再做一个简单版本。"),
        ("N02", "我想说的是，这个入口有点难找，嗯，可能需要更明显。"),
        ("N03", "今天今天先整理一下笔记，明天再写总结。"),
        ("N04", "请把会议时间发给我，我好安排路程。"),
        ("N05", "我在 Codex 写 PRD，也把笔记放进 Obsidian。"),
        ("N06", "微信里这段话有点长，帮我分成两段。"),
        ("N07", "我觉得这个句子可以再简短一些，但别删掉重点。"),
        ("N08", "先记录问题，再去查原因，最后决定要不要修改。"),
        ("N09", "右侧 Option 按一次开始，再按一次停止。"),
        ("N10", "结果出来以后，放到现在正在输入的那个地方。"),
        ("N11", "如果没有找到输入框，就把文字留在程序里。"),
        ("N12", "这段录音我不想长期保存，文字可以以后再考虑。"),
        ("N13", "先测普通话，方言的事情以后再讨论。"),
        ("N14", "麻烦把这句话改得礼貌一点，但意思不要变。"),
        ("N15", "我今天有空，下午两点以后比较方便。"),
        ("N16", "这个文件可能在桌面上，我不太确定。"),
        ("N17", "先把标题写上，正文我等会儿再补。"),
        ("N18", "请按原来的顺序列出来，不要重新排序。"),
        ("N19", "我说完以后，等三到八秒拿到结果也可以。"),
        ("N20", "这个词用英文写，后面的解释还是中文。")
    ]

    @objc private func runASRDiagnostics() {
        guard !busy, !recording.isRecording, !micPermissionPending, !insertionPending else { return }
        do {
            guard let url = Bundle.main.url(forResource: "DiagnosticSpeech", withExtension: "wav") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let cases = try ASRDiagnosticCase.standard(speechWAV: Data(contentsOf: url))
            let reportURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("MiniTypeless-ASR-Diagnostic-\(UUID()).txt")
            startASRDiagnostics(cases: cases, reportURL: reportURL)
        } catch {
            status.stringValue = "合成测试音频不可用；尚未调用云端。"
        }
    }

    private func appendDiagnosticLine(_ line: String) {
        diagnosticView.string += line + "\n"
        guard let url = diagnosticReportURL else { return }
        do { try diagnosticView.string.write(to: url, atomically: true, encoding: .utf8) }
        catch {
            diagnosticReportURL = nil
            diagnosticView.string += "报告未能保存到文件；本窗口中的诊断仍可选中复制。\n"
        }
    }

    private func startASRDiagnostics(cases: [ASRDiagnosticCase], reportURL: URL) {
        guard !busy, !recording.isRecording, !micPermissionPending, !insertionPending else { return }
        guard let key = sessionKey else {
            status.stringValue = "请先用 Touch ID 解锁本次运行，再点击静音诊断；尚未调用云端。"
            return
        }
        guard recording.completed == nil else {
            status.stringValue = "还有尚未处理的录音；请先处理或删除，再运行静音诊断。"
            return
        }
        let requestID = UUID()
        activeRequestID = requestID
        diagnosticRunning = true
        diagnosticReportURL = reportURL
        diagnosticView.string = ""
        appendDiagnosticLine("Mini Typeless 转写诊断 v2（无文字片段兼容）｜\(ISO8601DateFormatter().string(from: Date()))\n模型：qwen-audio-3.1-asr-flash；仅使用程序自带合成音频。\n不保存请求正文、密钥或识别内容；错误说明经过脱敏。\n")
        setBusy(true)
        status.stringValue = "正在检测静音转写；可以取消，不影响最新成功结果。"
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await ASRDiagnosticRunner(pipeline: self.pipeline).run(cases: cases, key: key) { event in
                    guard self.activeRequestID == requestID, !Task.isCancelled else { return }
                    switch event {
                    case .line(let line): self.appendDiagnosticLine(line)
                    case .usage(let object, let seconds): self.recordUsage(object, asr: true, audioSeconds: seconds)
                    }
                }
                guard self.activeRequestID == requestID, !Task.isCancelled else { return }
                self.appendDiagnosticLine("诊断请求已结束。每项结果见上方；未执行整理或插入。")
                self.finishPipeline()
                self.status.stringValue = self.diagnosticReportURL.map { "静音诊断结束；报告：\($0.path)" }
                    ?? "静音诊断结束；报告保留在上方，可选中复制。"
            } catch {
                guard self.activeRequestID == requestID, !Task.isCancelled else { return }
                self.appendDiagnosticLine("诊断中断：\(DictationFailure.describe(error))")
                self.finishPipeline()
                self.status.stringValue = "静音诊断中断；已完成的结果保留在上方。"
            }
        }
    }

    @objc private func runPromptEvaluation() {
        guard evaluationTask == nil, !busy, !recording.isRecording, !micPermissionPending else {
            status.stringValue = "请先结束当前录音或处理，再运行文字测试。"
            return
        }
        guard let key = sessionKey else {
            status.stringValue = "请先用 Touch ID 解锁本次运行；文字测试尚未开始。"
            return
        }
        let reportURL = FileManager.default.temporaryDirectory.appendingPathComponent("MiniTypeless-Prompt-Evaluation-\(UUID().uuidString).md")
        var report = "# Mini Typeless 文字整理测试\n\n模型：\(refinementModel)；共 30 条合成文字；仅测试整理，不录音、不自动插入。\n\n"
        guard (try? report.write(to: reportURL, atomically: true, encoding: .utf8)) != nil else {
            status.stringValue = "无法创建文字测试报告；尚未调用百炼。"
            return
        }
        setBusy(true)
        evaluationButton.isEnabled = false
        evaluationCancelButton.isEnabled = true
        status.stringValue = "正在运行 30 条文字测试；每条调用一次百炼。可点击取消；报告只含样本和结果。"
        evaluationTask = Task { [weak self] in
            guard let self else { return }
            for (index, item) in self.evaluationCases.enumerated() {
                if Task.isCancelled { break }
                let started = Date()
                let body: [String: Any] = [
                    "model": self.refinementModel,
                    "messages": [["role": "system", "content": self.refinementPrompt], ["role": "user", "content": self.refinementUserMessage(item.raw)]],
                    "stream": false, "temperature": 0.1, "max_tokens": 1200, "enable_thinking": false
                ]
                var output = "请求准备失败"
                if let json = try? JSONSerialization.data(withJSONObject: body) {
                    var request = URLRequest(url: self.endpoint)
                    request.httpMethod = "POST"
                    request.httpBody = json
                    request.timeoutInterval = 30
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)
                        let http = (response as? HTTPURLResponse)?.statusCode ?? 0
                        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        if http == 200, let object { self.recordUsage(object, asr: false) }
                        if http == 200,
                           let object,
                           let choices = object["choices"] as? [[String: Any]],
                           let message = choices.first?["message"] as? [String: Any],
                           let text = message["content"] as? String, !text.isEmpty {
                            output = text
                        } else {
                            output = "请求失败（HTTP \(http)）"
                        }
                    } catch {
                        if Task.isCancelled { break }
                        output = "请求失败（系统代码 \((error as NSError).code)）"
                    }
                }
                if Task.isCancelled { break }
                let plausible = self.refinementIsPlausible(raw: item.raw, refined: output)
                report += "## \(item.id)\n原文：\(item.raw)\n结果：\(output)\n耗时：\(String(format: "%.1f", Date().timeIntervalSince(started))) 秒；程序保守检查：\(plausible ? "通过" : "未通过")\n\n"
                try? report.write(to: reportURL, atomically: true, encoding: .utf8)
                self.status.stringValue = "文字测试 \(index + 1)/30；报告：\(reportURL.path)"
            }
            self.status.stringValue = Task.isCancelled
                ? "文字测试已取消；已完成结果保存在：\(reportURL.path)"
                : "30 条文字测试完成；报告：\(reportURL.path)"
            self.evaluationTask = nil
            self.evaluationButton.isEnabled = true
            self.evaluationCancelButton.isEnabled = false
            self.setBusy(false)
        }
    }

    @objc private func cancelPromptEvaluation() {
        evaluationTask?.cancel()
        evaluationCancelButton.isEnabled = false
        status.stringValue = "正在取消文字测试；已完成结果会保留在报告中。"
    }
    #endif

    private func refinementIsPlausible(raw: String, refined: String) -> Bool {
        DictationPipeline.isPlausible(raw: raw, refined: refined)
    }

    @objc private func testAPI() {
        guard !busy else { return }
        let (readCode, data) = readProtected(newService, reason: "本次百炼测试使用 Touch ID 保护的 API Key")
        guard readCode == errSecSuccess, let data = data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            status.stringValue = "新密钥读取失败（系统返回码 \(readCode)）；未调用 API，旧密钥保留。"
            return
        }
        let body: [String: Any] = [
            "model": refinementModel,
            "messages": [
                ["role": "system", "content": "只做轻度中文口述整理，处理明确的自我纠正，只返回整理后的文字。"],
                ["role": "user", "content": "周五下午三点，不对，周六下午三点开会。"]
            ],
            "stream": false, "temperature": 0.1, "max_tokens": 80, "enable_thinking": false
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: body) else {
            status.stringValue = "请求准备失败；未调用 API。"
            return
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = json
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        setBusy(true)
        status.stringValue = "已读取新密钥，正在调用一次百炼……"
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setBusy(false)
                if let error = error {
                    self.status.stringValue = "API 请求失败：\(error.localizedDescription)。旧密钥保留。"
                    return
                }
                let http = (response as? HTTPURLResponse)?.statusCode ?? 0
                let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                if http == 200, let object { self.recordUsage(object, asr: false) }
                guard http == 200, let object,
                      let choices = object["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let text = message["content"] as? String, !text.isEmpty else {
                    self.status.stringValue = "API 未返回可用结果（HTTP \(http)）。请只报告状态码；旧密钥保留。"
                    return
                }
                self.status.stringValue = "第 3 步通过：新密钥完成百炼调用。结果：\(text) 旧密钥仍保留。"
            }
        }.resume()
    }
}

#if !LAYOUT_TEST
@main
@MainActor
struct MiniTypelessSecureMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = SecureProbe()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
#endif

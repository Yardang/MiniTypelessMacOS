import AppKit

@main
@MainActor
struct StabilityRegression {
    static func require(_ value: Bool, _ message: String) {
        precondition(value, message)
    }
    static func entries(_ directory: URL) throws -> [[String: Any]] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .flatMap { try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").map {
                try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
            } }
    }
    static func main() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("MiniTypeless-stability-test-\(UUID())")
        defer { try? fm.removeItem(at: directory) }
        let log = DiagnosticLog(directory: directory)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let probe = SecureProbe(diagnostics: log)
        weak var retainedWindow: NSWindow?
        autoreleasepool {
            let window = probe.makeWindow()
            require(!window.isReleasedWhenClosed, "ARC window must not release itself on close")
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            retainedWindow = window
        }
        for _ in 0..<25 {
            autoreleasepool { retainedWindow?.close() }
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            require(retainedWindow != nil, "Delegate must retain closed window")
            _ = probe.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            require(retainedWindow?.isVisible == true, "Reopen must show retained window")
        }
        retainedWindow?.orderOut(nil)
        _ = probe.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true)
        probe.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        let lifecycle = try entries(directory)
        require(lifecycle.filter { $0["event"] as? String == "windowClosed" }.count == 25, "Log all closes")
        require(lifecycle.filter { $0["event"] as? String == "windowReopened" }.count == 25, "Log actual reopens only")
        require(lifecycle.contains { $0["event"] as? String == "cleanTermination" }, "Record clean exit")

        let privateText = "private-transcript-secret-key-user-path"
        let error = NSError(domain: privateText, code: -1005, userInfo: [NSLocalizedDescriptionKey: privateText])
        log.record(.processingFailed, failure: .classify(DictationFailure.transport(privateText, error)))
        let data = try Data(contentsOf: directory.appendingPathComponent("events.jsonl"))
        require(!String(decoding: data, as: UTF8.self).contains(privateText), "Never serialize arbitrary error fields")
        let errorEntry = try entries(directory).first { $0["event"] as? String == "processingFailed" }!
        let failure = errorEntry["failure"] as! [String: Any]
        require(failure["code"] as? Int == -1005 && failure["kind"] as? String == "network", "Retain safe numeric cause")
        let mode = try fm.attributesOfItem(atPath: directory.appendingPathComponent("events.jsonl").path)[.posixPermissions] as! NSNumber
        require(mode.intValue == 0o600, "Log must be owner readable only")

        require(FocusProbeSnapshot.App.classify("private-application-title") == .other, "Never log arbitrary application labels")
        require(FocusProbeSnapshot.Role.classify("private-field-value", "private-title") == .other, "Never log arbitrary AX strings")
        let element = FocusProbeSnapshot.Element(code: -25212, pid: 123, app: .claude, role: .text, selectionCode: -25212)
        let focus = FocusProbeSnapshot(trusted: true, workspacePID: 456, workspaceApp: .other,
            systemApp: element, systemFocus: element, workspaceWindow: element, workspaceFocus: element,
            claudeWindow: element, claudeFocus: element)
        log.record(.focusProbe, index: 1, total: 3, focus: focus)
        let probeMetadata = try entries(directory).last!["focus"] as! [String: Any]
        require(Set(probeMetadata.keys) == Set(["trusted", "workspacePID", "workspaceApp", "systemApp", "systemFocus", "workspaceWindow", "workspaceFocus", "claudeWindow", "claudeFocus"]), "Probe has only safe metadata keys")
        let field = probeMetadata["claudeFocus"] as! [String: Any]
        require(Set(field.keys) == Set(["code", "pid", "app", "role", "selectionCode"]), "No value, title, URL or selected text")
        let rotated = directory.appendingPathComponent("rotation")
        let small = DiagnosticLog(directory: rotated, limit: 1024, backups: 2)
        for _ in 0..<100 { small.record(.transcribing, operation: UUID(), index: 1, total: 3) }
        let files = try fm.contentsOfDirectory(at: rotated, includingPropertiesForKeys: nil)
        require(files.count == 3, "Bound log retention")
        for file in files {
            require(try Data(contentsOf: file).count <= 1024, "Bound each log file")
        }
        require(try entries(rotated).count > 0, "Rotated logs remain readable")
        let blocked = directory.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        let broken = DiagnosticLog(directory: blocked)
        broken.record(.launch)
        require(broken.writeFailed, "Surface logging failure without crashing")
        let disabled = DiagnosticLog(directory: directory.appendingPathComponent("disabled"), enabled: false)
        disabled.record(.launch)
        require(!fm.fileExists(atPath: disabled.directory.path), "Tests can disable persistence")
        print("PASS: 25 close/reopen cycles; clean exit; private error fields excluded; permissions, rotation, unavailable storage and disabled logging.")
    }
}

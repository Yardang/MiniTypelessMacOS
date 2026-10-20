# 自动化测试入口

在仓库根目录执行 `scripts/test.sh`，运行全部七组离线回归。仅使用合成音频、模拟网络和临时目录，不读取真实密钥或操作麦克风。产物路径由脚本打印，任一失败立即停止。当前验收规则以 [PRD](../docs/PRD.md) 为准；下文较早的人工清单保留其历史范围。

# Layout regression checks

Run from the repository root on macOS with Xcode installed:

```sh
mkdir -p /tmp/minitypeless-layout-tests
xcrun swiftc -D DEBUG -D LAYOUT_TEST \
  -module-cache-path /tmp/minitypeless-layout-tests/module-cache \
  MiniTypelessSecure/*.swift \
  Tests/LayoutRegression.swift \
  -o /tmp/minitypeless-layout-tests/layout-regression
/tmp/minitypeless-layout-tests/layout-regression
```

The test constructs the actual AppKit window offscreen with synthetic multiline text. It checks 24 combinations: three window sizes (including the 720 × 520 minimum) and all eight disclosure states. Copy, insert, and compatibility-paste controls must stay inside the window; expanded content must scroll; result text must have a usable wrapping width. No microphone, keychain, hotkey monitor, cloud call, or clipboard operation is invoked.

Run the focus regression separately:

```sh
xcrun swiftc -module-cache-path /tmp/minitypeless-focus-tests-cache \
  MiniTypelessSecure/InputFocus.swift Tests/InputFocusRegression.swift \
  -o /tmp/minitypeless-focus-regression
/tmp/minitypeless-focus-regression
```

These 15 cases use synthetic accessibility trees, including the reported missing application-focus value. They cover system and focused-window fallback, nonfocused editors, password fields, foreign processes, unavailable selections, ambiguous focus, selection/element movement, and bounded traversal. They test the production resolver without querying live applications.

These geometry checks do not verify macOS permissions or live insertion into another app. For that regression check:

1. Save any result needed from the old app, quit it, and open the separately signed repair build. Unlock the existing key through Touch ID.
2. Focus an ordinary Codex chat input, dictate a short nonsensitive sentence with Fn, stop with Fn, and keep the caret still while processing finishes. Confirm one insertion and no automatic send.
3. If insertion fails, use the persistent bottom insertion status to identify the stage; use the visible copy button as a fallback. Check a cold Codex launch as well as repeated recordings.
4. With compatibility mode off, verify that switching focus or typing during the insertion lookup cancels the insertion, and that unsupported apps and password fields receive no text.
5. Expand usage, resize the window, and confirm the latest result and copy/insert buttons remain accessible while the upper area scrolls.
6. If Codex exposes no focus, click “兼容粘贴（2 秒）”, then switch to and click its ordinary message input within two seconds. Verify one paste and no send. This explicit fallback does not validate the field. The separate compatibility checkbox defaults off each launch and permits automatic fallback only for `com.openai.codex` or `com.openai.chat`, only when both app and system focus reads returned `noValue`, and only while the foreground process and user interaction counter remain unchanged. It does not override a confirmed unsuitable target or a changed selection.

Electron's documented accessibility activation is described in [its accessibility guide](https://www.electronjs.org/docs/latest/tutorial/accessibility). System-wide focus and `AXFocused` are documented in Apple's SDK headers (`AXUIElement.h` and `AXAttributeConstants.h`). `AXError.noValue` is `-25212`; it is distinct from a timeout or disabled accessibility.

## ASR diagnostics regression

```sh
xcrun swiftc -D DEBUG -module-cache-path /tmp/minitypeless-diagnostic-cache \
  MiniTypelessSecure/AudioChunks.swift MiniTypelessSecure/DictationPipeline.swift \
  MiniTypelessSecure/ServiceDiagnostic.swift MiniTypelessSecure/ASRDiagnostics.swift \
  Tests/ServiceDiagnosticRegression.swift -o /tmp/minitypeless-diagnostic-regression
/tmp/minitypeless-diagnostic-regression
```

Checks selected error fields, chunk context, redaction of credentials/URLs/audio, invalid and oversized responses, bundled synthetic speech and its silent intervals, and three ASR-only requests using fake transport. No live request is sent. The workflow suite below additionally checks diagnostic completion, cancellation and sleep using the real app coordinator, preserving existing results and suppressing late report writes. See [live probe instructions](../docs/asr-diagnostics-2026-10-17.md).

## Recording and processing regression

No-speech handling (uses the exact HTTP/code/message signature observed in the live synthetic-silence probe):

```sh
xcrun swiftc -D DEBUG -module-cache-path /tmp/minitypeless-diagnostic-cache \
  MiniTypelessSecure/AudioChunks.swift MiniTypelessSecure/DictationPipeline.swift \
  MiniTypelessSecure/ServiceDiagnostic.swift MiniTypelessSecure/ASRDiagnostics.swift \
  Tests/NoSpeechRegression.swift -o /tmp/minitypeless-no-speech-regression
/tmp/minitypeless-no-speech-regression
```

Tests empty chunks in all positions, all-empty audio, unrelated errors, refinement errors, truthful diagnostic status and cancellation. The app-coordinator suite below also covers successful completion with a trailing empty chunk and preservation of the previous successful result after an all-empty recording. See [evidence and fix scope](../docs/no-speech-fix-2026-10-17.md).

```sh
xcrun swiftc -D DEBUG -D LAYOUT_TEST \
  -module-cache-path /tmp/minitypeless-layout-tests/module-cache \
  MiniTypelessSecure/*.swift Tests/WorkflowRegression.swift \
  -o /tmp/minitypeless-workflow-regression
/tmp/minitypeless-workflow-regression
```

This drives the real app coordinator with injected microphone/timer/network substitutes. It checks Fn/button stop and the ten-minute stop callback through the full transcription/refinement result path, duplicate stop suppression, canceled/sleeping late responses in both ASR and refinement stages, an old response arriving after a newer dictation succeeds, chunk sample integrity, partial failures, truncation, and target-app decisions. It uses synthetic audio and a synthetic key and disables usage persistence. It does not access the microphone, keychain, live network, or pasteboard. The ten-minute timer is advanced by a fake scheduler; this is not a ten-minute physical microphone endurance test.

Manual acceptance for this build:

The HTTP 400 `CLIENT_ERROR` regression uses a synthetic rejection after two successful chunks and checks that partial text remains, the previous successful result stays intact, and refinement is not called for the failed recording. It reproduces local handling only; it does not identify the cause or failed chunk in the user's real recording. The empty-text case simulates HTTP 200 with an empty transcript; it does not prove that the live service accepts silent audio.

1. Quit the older Mini Typeless, open the separate ten-minute repair build, and unlock with Touch ID. Select compatibility mode again if Codex needs it (it still defaults off on launch).
2. Click the Codex/ChatGPT message input. Fn-start, dictate, Fn-stop. Expect transcription, refinement and one paste, with no send.
3. Repeat and return to Mini Typeless while it processes. Expect return to the original app and a fresh focus check. Repeat while switching to a third app: expect a named diagnostic and no paste.
4. Record past two minutes and stop with Fn. Expect no stop at two minutes and a full result. Also test a recording longer than four minutes (multiple ASR requests), and the ten-minute automatic stop. Check the last sentence is present and the recording duration is approximately correct.
5. Cancel during a long transcription; verify no late result or paste appears. Latest previous successful result remains recoverable.
6. Verify copy controls at minimum window size and existing usage totals. No API-key migration should be needed.

## Network recovery regression (2026-10-19)

The workflow suite now injects -1005 at ASR and refinement stages of a synthetic 90.4-second recording. It verifies byte-for-byte retention, no automatic retry, Fn/controller overwrite prevention, WAV export and failed-export retention, sleep/unlock gating, repeated failure preserving raw text, successful manual retry without automatic insertion, and cleanup on success/delete/normal exit. Cancellation and sleep assertions now expect completed audio to remain; a new recording requires explicit deletion of the old take. Layout checks include the bottom recovery row. See [retention policy](../docs/network-recovery-2026-10-19.md).

## Window lifetime and local diagnostics (2026-10-19)

```sh
xcrun swiftc -D DEBUG -D LAYOUT_TEST \
  -module-cache-path /tmp/minitypeless-layout-tests/module-cache \
  MiniTypelessSecure/*.swift Tests/StabilityRegression.swift \
  -o /tmp/minitypeless-stability-regression
/tmp/minitypeless-stability-regression
```

Exercises 25 actual window close/reopen cycles and verifies lifecycle events, clean termination, error-field privacy, file permissions, bounded rotation, unavailable storage and disabled logging. WorkflowRegression additionally closes/reopens during recording, processing and after success, checking preserved state and production event emission without text/key leakage. Test logs use disposable temporary directories; normal workflow/layout tests disable production logging. See [crash evidence and diagnostic limits](../docs/stability-diagnostics-2026-10-19.md).

## Sleep / continuous recording regression (CHG-20261020-01)

`SleepRecoveryRegression.swift` maps to AC-SLP-01/02/03/04, AC-REC-01/02/03 and AC-SEC-01. Tests retain the unlocked session across sleep, first-upload deferral, duplicate notifications, deadline/delegate races, replacement after successful start, failures before replacement, stale permission callbacks, deletion/exit invalidation and failed wake upload without automatic retry. WorkflowRegression covers AC-SLP-05 in both network stages. Earlier assertions requiring sleep re-unlock and blocking Fn for a retryable take were deliberately superseded; their old expectations are not current requirements.

Real system sleep, microphone delivery immediately before sleep and target-app focus after wake remain a short manual acceptance check; fake notifications do not prove hardware behavior.

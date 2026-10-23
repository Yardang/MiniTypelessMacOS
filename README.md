# Mini Typeless for macOS

[中文](#中文) · [English](#english)

项目入口：[产品需求与编号索引](docs/PRD.md) · [开发流程](docs/DEVELOPMENT.md) · [变更记录](CHANGELOG.md) · [测试方法](Tests/README.md)

## 中文

维护状态（2026-10-21）：**Standby Fix 已通过用户三项实机验收**：Fn 转写插入、合盖/开盖自动处理、断网恢复后新录音替换；ChatGPT、Claude、Obsidian 均通过。已验证代码标签：`verified-2026-10-21`。见 [验收记录](docs/changes/CHG-20261020-01.md)。网络故障暂未复现，根因未确认；如再遇连接错误，先查 [网络应急步骤](docs/network-emergency-guide.md)。该结论属于原已验证版本。

UI 迭代（2026-10-23）：**开发完成，实机待验**。采用浅色磨砂结果窗、低饱和状态色和非激活录音胶囊；设置、用量、诊断另开窗口。七组离线回归与 Debug/Release 构建通过，详见 [UI 变更记录](docs/changes/CHG-20261023-01.md)。

外观迭代（2026-10-23）：齿轮 → 外观可选“跟随系统 / 浅色 / 深色”，默认跟随系统并记住选择。macOS 26 使用自适应玻璃，深色模式配浅色文字；旧系统使用原生磨砂。新版独立安装为 UI Preview 2，原版保留。[材质与验证记录](docs/changes/CHG-20261023-02.md)。

小修（2026-10-23）：UI Preview 3 保持已认可的玻璃外观，将录音时长居中、“Fn 结束”缩小放右侧；收起上次结果时恢复展开前的窗口大小。[修正记录](docs/changes/CHG-20261023-03.md)。

提示位置小修（2026-10-23）：UI Preview 4 将转写、整理、成功和失败等胶囊状态小字居中，与录音时长同轴；录音布局与主窗口不变。[记录](docs/changes/CHG-20261023-04.md)。

Mini Typeless 是一个开发中的 macOS 中文语音输入实验。单独按下并松开左下角 **Fn／地球键** 开始录音，再按一次停止；程序随后用阿里云百炼进行语音转写和轻量文字整理，并尝试把结果插入当前输入框。它不会自动发送聊天消息。

### 首次使用

1. 用 Xcode 打开 `MiniTypelessSecure.xcodeproj`。在目标的 **Signing & Capabilities** 中选择你自己的 Team，并启用自动管理签名。若改动 Bundle Identifier，请同步修改 `MiniTypelessSecure/MiniTypelessSecure.entitlements` 中 `keychain-access-groups` 的应用标识，保持两者一致。
2. 在阿里云百炼创建**你自己的北京区 API Key**。运行程序，点击齿轮进入“设置与用量”，展开“首次使用：保存自己的百炼 API Key”，粘贴并点击“存入本机 Touch ID 钥匙串”。如果本机已有密钥，程序不会覆盖它。
3. 点击“用 Touch ID 解锁本次运行”。按界面提示授予麦克风、辅助功能和输入监控权限，然后把光标放到目标输入框，使用 Fn／地球键开始和停止录音。若 macOS 同时切换输入法或打开表情面板，可在“系统设置 → 键盘”中把“按 Fn／地球键”设为“无操作”。

每次重新启动程序需要解锁一次；同次运行跨 Mac 睡眠仍保持解锁。本次运行的后续请求复用内存中的密钥。录音成功处理后删除临时副本；失败或取消时保留已结束录音，供本次运行内手动重试或另存。主动删除或正常退出会清除临时副本，已另存的文件不受影响。识别文字和最新结果只保存在当前窗口的内存里。默认仅在支持的应用中确认输入框焦点后尝试自动插入；失败时可复制结果或主动使用兼容粘贴。最长录音时间为 **10 分钟**；再次按 Fn、点击停止或达到上限都会自动转写、整理并尝试插入。长录音在内存中按最多 4 分钟分段转写，合并后整理并只尝试插入一次。

点击结果窗口右上角 × 只关闭窗口，程序和 Fn 快捷键会继续运行；点击 Dock 图标或菜单栏波形图标可重新打开。要真正退出，可用应用菜单 Command-Q、菜单栏“退出 Mini Typeless”或 Dock 退出。退出后内存中的密钥会清除，下次启动需要再次使用 Touch ID。

程序在停止录音时记住接收应用（若当时在 Mini Typeless，则沿用开始录音时的外部应用）。处理期间回到 Mini Typeless 查看进度，完成后会返回原应用检查输入框；切换到第三个应用则停止自动插入并提示原因。若在同一应用内切换对话，文字会尝试进入处理完成时的当前输入框，请确认所选位置。

转写或整理失败后，底部提供重试、另存和删除操作。下一次 Fn 可以直接开始新录音，成功启动后自动删除旧待重试段；新录音启动失败时旧段保留。需要保留旧段时请先另存。重试会重新上传，可能产生重复费用。重试成功后保留文字，由用户复制或手动插入。空闲时程序允许系统睡眠并保持待机；录音遇到真正的系统睡眠会结束并保留该段，唤醒后自动处理一次，不计入睡眠时长。已经提交云端的请求若因睡眠中断，仍须手动重试，或直接开始新录音。最新规则见 [PRD](docs/PRD.md) 与 [本轮变更](docs/changes/CHG-20261020-01.md)；[断网恢复说明](docs/network-recovery-2026-10-19.md) 保留旧版设计记录。

对于云端明确返回的无文字音频片段，程序继续处理其他片段；若整次录音都没有可转写文字，则提示并结束，不整理或插入。仅兼容已验证的特定响应，其他请求错误仍会明确报错。实测依据与处理边界见 [无文字片段修复记录](docs/no-speech-fix-2026-10-17.md)。

Debug 版本在“诊断与帮助 → 开发工具”中可点击“检测静音转写（上传合成音频）”，用三项合成音频核查静音相关接口行为；不需要录音，不整理、不插入。它会产生接口用量，操作和诊断边界见 [转写诊断说明](docs/asr-diagnostics-2026-10-17.md)。

新增本地运行诊断日志，可在“诊断与帮助”点击“打开本地诊断日志”查看。只记录运行阶段和数字错误码，不记录录音、文字或密钥，最多约 1 MiB；关闭窗口后重开的崩溃修复与日志边界见 [稳定性诊断记录](docs/stability-diagnostics-2026-10-19.md)。

本轮结构检查、故障原因及模块边界见 [架构排查记录](docs/architecture-review-2026-10-17.md)；离线回归方法见 [Tests/README.md](Tests/README.md)。

结果窗口支持调整大小，长文字可滚动，复制、插入和失败恢复按钮保持可见。本次与上次成功结果分开；新录音失败不会把旧文字当成本次内容。仅有原文时明确提示未整理或可能不完整，并提供“复制原文”。上次成功结果可展开、独立复制。设置与费用在齿轮入口；原始转写和详细错误在“更多 → 本次详情与原始转写”。录音/处理胶囊不主动激活窗口；失败只显示提示，点击“查看”再打开主窗。绿色表示文字已生成，沙金表示需要接手，红色表示处理失败；“已请求插入”不等于目标应用已确认接收。插入检查依次查询应用焦点、系统焦点，以及当前焦点窗口内明确标记为焦点的输入框；输入框尚未就绪时最多重查一次，整体查询限时 3 秒。默认须两次确认普通输入框和光标，并确认前台应用及用户输入没有变化，才请求一次粘贴。

若应用不提供焦点信息，可在“更多”菜单主动选择“兼容粘贴（2 秒）”，在两秒内切换并点击目标输入框；程序按你的选择请求一次粘贴，不验证输入框，也不发送消息。另有默认关闭、仅本次运行有效的兼容模式：勾选后，仅当 Codex／ChatGPT（应用标识 `com.openai.codex` 或 `com.openai.chat`）的应用焦点和系统焦点均返回“无值”，且前台应用和用户输入保持不变时，允许自动兼容粘贴。请自行确保光标位于要输入的普通文本框中。

**密钥与费用：** 此仓库不含作者的 API Key。克隆或下载代码不会获得作者的钥匙串项目；每位使用者都需要创建并保存自己的 Key，并自行承担对应的阿里云用量。不要把密钥写入源码、README、提交记录或 Issue。语音转写和文字整理会把本次录音及转写文字发送给百炼；请勿用私人或敏感内容测试。

目前语音转写使用 `qwen-audio-3.1-asr-flash`，文字整理使用 `qwen3.8-flash`。两者分别调用；请在百炼核对两个模型的额度及账户状态。账户欠费时，即使仍有免费额度，请求也可能被拒绝。3.1 版 ASR 的免费额度按 Token 计量，与 3.0 版的音频秒数额度分开。

窗口中的“用量与费用预估”从本版开始，按天在本机记录成功请求返回的 Token 数、录音时长和整理结果字数，不保存文字内容。它按北京区公开原价（两模型均为输入 ¥0.8／百万 Token、输出 ¥2.7／百万 Token）估算今日、本月和按已记录日均推算的整月费用；尚未扣除免费额度，也不包含其他阿里云服务。请求未返回完整 Token、取消后云端仍完成的请求及旧版本用量可能不在统计中，请以百炼账单为准。30 条文字测试和密钥迁移检查中的成功调用也计入整理 Token。

这是实验版本，文字整理偶尔会偏离原意；自动插入也可能因目标应用或系统权限而失败。请检查结果后再使用。Debug 构建提供“运行 30 条文字整理测试”按钮，使用合成文字逐条调用模型，不录音、不插入。两轮测试及限制见 [evaluation/README.md](evaluation/README.md)。

## English

Mini Typeless is an experimental Chinese dictation app for macOS. Press and release the **Fn/Globe** key at the lower left to start recording, then repeat to stop. The app transcribes audio with Alibaba Cloud Bailian, lightly cleans up the text, and attempts to insert it into the active input field. It does not send chat messages automatically.

Appearance: choose System (default), Light, or Dark in Settings. The choice persists locally. macOS 26 uses adaptive glass with matching foreground colors; earlier systems retain native frosted material.

### Getting started

1. Open `MiniTypelessSecure.xcodeproj` in Xcode. Under the target's **Signing & Capabilities**, select your own Team and enable automatic signing. If you change the Bundle Identifier, update the app identifier in `keychain-access-groups` in `MiniTypelessSecure/MiniTypelessSecure.entitlements` to match.
2. Create **your own Beijing-region Bailian API key**. Run the app, open Settings using the gear, expand “首次使用：保存自己的百炼 API Key” (First use: save your own Bailian API key), paste the key, and click “存入本机 Touch ID 钥匙串” (Save to local Touch ID keychain). An existing key is never overwritten by this action.
3. Click “用 Touch ID 解锁本次运行” (Unlock this session with Touch ID). Grant the requested microphone, Accessibility, and Input Monitoring permissions. Focus the target input field, then use Fn/Globe to start and stop recording. If macOS also switches input sources or opens the emoji panel, set “Press Fn/Globe key to” to “Do Nothing” in System Settings → Keyboard.

Unlock once after each app launch; the in-memory session remains unlocked across Mac sleep until the app exits. Temporary audio is deleted after successful processing. Failed or canceled completed recordings remain available within the current run for manual retry or WAV export; explicit deletion or normal exit clears the temporary copy. Transcripts and results remain in window memory. By default, insertion requires confirmed input focus in a supported app; otherwise copy the result or explicitly choose compatibility paste. Recordings are limited to **10 minutes**. Fn-stop, the stop button, and the time limit all start transcription and refinement automatically. Audio is split in memory into chunks of at most four minutes, transcribed in order, then refined and inserted once.

The top-right × hides the result window while the app and Fn shortcut continue running. Reopen it using the Dock or waveform menu-bar item. Quit through Command-Q, the menu-bar Quit item, or the Dock. Quitting clears the in-memory key, so the next launch requires Touch ID again.

Starting a new recording replaces any completed retryable take only after the new microphone recording starts successfully. A failed start preserves the old take. Sleep ends an active recording and defers its first upload until wake; interrupted in-flight requests are not automatically retried. See the [PRD](docs/PRD.md).

The destination app is captured when recording stops; stopping inside Mini Typeless retains the external app selected at recording start. Returning to Mini Typeless while processing allows the app to reactivate the original destination and check its input. Switching to a third app prevents automatic insertion. Within the same app, insertion targets its current input, so keep the intended conversation selected.

See the [architecture review](docs/architecture-review-2026-10-17.md) and [offline regression checks](Tests/README.md).

The frosted result window is resizable, with scrolling text and visible actions. Current and previous successful results are separate; incomplete raw text has an explicit label and copy action. Settings and usage open from the gear; detailed errors and raw transcription open from the More menu. A nonactivating capsule shows recording and processing. Failures do not automatically open the main window. A paste request is not proof that the destination accepted the text. This UI build has passed offline checks; live focus and appearance validation remains pending. Insertion checks try application focus, system-wide focus, then explicitly focused editors inside the focused window. They retry an unavailable target once and stop after a three-second deadline. By default, two matching ordinary-field and selection checks are required, with no foreground-app or user-input change.

The explicit “兼容粘贴（2 秒）” More-menu item lets you switch to and click the intended input within two seconds, then requests one paste without validating the field or sending the message. An optional compatibility mode defaults off each launch. When enabled, it also allows automatic fallback for Codex/ChatGPT (`com.openai.codex` or `com.openai.chat`) if both application and system focus return no value and the foreground process and user interaction counter remain unchanged. In compatibility mode, you are responsible for selecting the intended ordinary text input.

**Keys and costs:** The author's API key is **not** in this repository. Cloning or downloading the project does not copy the author's macOS keychain item. Each user must provide their own key and is responsible for their own Alibaba Cloud usage. Never put a key in source files, README, commits, or issues. The app sends the current audio and transcript to Bailian for transcription and refinement; avoid testing with sensitive content.

The app currently uses `qwen-audio-3.1-asr-flash` for transcription and `qwen3.8-flash` for text refinement. These are separate model calls. Check both quotas and the account balance in Model Studio; overdue accounts may be blocked even with remaining free quota. The 3.1 ASR free quota is measured in tokens, separately from the 3.0 model's audio-seconds quota.

The in-app usage and cost panel stores daily counts locally, starting with this build: reported tokens, recording duration, and output character counts, without transcript content. It estimates today's and this month's list-price cost and projects a full month from the average since tracking started. The estimate does not deduct free quota or include other Alibaba Cloud services. Missing token reports, canceled requests that still complete in the cloud, and older builds may be absent. Use the Alibaba Cloud bill as the source of truth. Successful 30-case evaluations and key-migration API checks also count toward text-model tokens.

This is an experimental build. Text refinement can occasionally change meaning, and insertion can fail depending on the target app or system permissions. Review the output before use. Debug builds include a 30-case synthetic text evaluation that calls the refinement model without recording or inserting. Results and limitations are in [evaluation/README.md](evaluation/README.md).

# Mini Typeless for macOS

[中文](#中文) · [English](#english)

## 中文

Mini Typeless 是一个开发中的 macOS 中文语音输入实验。单独按下并松开左下角 **Fn／地球键** 开始录音，再按一次停止；程序随后用阿里云百炼进行语音转写和轻量文字整理，并尝试把结果插入当前输入框。它不会自动发送聊天消息。

### 首次使用

1. 用 Xcode 打开 `MiniTypelessSecure.xcodeproj`。在目标的 **Signing & Capabilities** 中选择你自己的 Team，并启用自动管理签名。若改动 Bundle Identifier，请同步修改 `MiniTypelessSecure/MiniTypelessSecure.entitlements` 中 `keychain-access-groups` 的应用标识，保持两者一致。
2. 在阿里云百炼创建**你自己的北京区 API Key**。运行程序，展开“首次使用：保存自己的百炼 API Key”，粘贴并点击“存入本机 Touch ID 钥匙串”。如果本机已有密钥，程序不会覆盖它。
3. 点击“用 Touch ID 解锁本次运行”。按界面提示授予麦克风、辅助功能和输入监控权限，然后把光标放到目标输入框，使用 Fn／地球键开始和停止录音。若 macOS 同时切换输入法或打开表情面板，可在“系统设置 → 键盘”中把“按 Fn／地球键”设为“无操作”。

每次重新启动程序或 Mac 睡眠后，需要重新解锁一次。本次运行的后续请求复用内存中的密钥。录音处理完成后删除；识别文字和最新结果只保存在当前窗口的内存里。自动插入仅在程序可以确认焦点的已验证应用中尝试；失败时可从窗口复制结果。最长录音时间为 120 秒。

点击窗口左上角红叉只关闭窗口，程序和 Fn 快捷键会继续运行；点击 Dock 中的图标可重新打开窗口。要真正退出，请在菜单栏选择 **Mini Typeless Secure → 退出**（或按 Command-Q）。退出后内存中的密钥会清除，下次启动需要再次使用 Touch ID。

**密钥与费用：** 此仓库不含作者的 API Key。克隆或下载代码不会获得作者的钥匙串项目；每位使用者都需要创建并保存自己的 Key，并自行承担对应的阿里云用量。不要把密钥写入源码、README、提交记录或 Issue。语音转写和文字整理会把本次录音及转写文字发送给百炼；请勿用私人或敏感内容测试。

目前语音转写使用 `qwen-audio-3.1-asr-flash`，文字整理使用 `qwen3.8-flash`。两者分别调用；请在百炼核对两个模型的额度及账户状态。账户欠费时，即使仍有免费额度，请求也可能被拒绝。3.1 版 ASR 的免费额度按 Token 计量，与 3.0 版的音频秒数额度分开。

窗口中的“用量与费用预估”从本版开始，按天在本机记录成功请求返回的 Token 数、录音时长和整理结果字数，不保存文字内容。它按北京区公开原价（两模型均为输入 ¥0.8／百万 Token、输出 ¥2.7／百万 Token）估算今日、本月和按已记录日均推算的整月费用；尚未扣除免费额度，也不包含其他阿里云服务。请求未返回完整 Token、取消后云端仍完成的请求及旧版本用量可能不在统计中，请以百炼账单为准。30 条文字测试和密钥迁移检查中的成功调用也计入整理 Token。

这是实验版本，文字整理偶尔会偏离原意；自动插入也可能因目标应用或系统权限而失败。请检查结果后再使用。Debug 构建提供“运行 30 条文字整理测试”按钮，使用合成文字逐条调用模型，不录音、不插入。两轮测试及限制见 [evaluation/README.md](evaluation/README.md)。

## English

Mini Typeless is an experimental Chinese dictation app for macOS. Press and release the **Fn/Globe** key at the lower left to start recording, then repeat to stop. The app transcribes audio with Alibaba Cloud Bailian, lightly cleans up the text, and attempts to insert it into the active input field. It does not send chat messages automatically.

### Getting started

1. Open `MiniTypelessSecure.xcodeproj` in Xcode. Under the target's **Signing & Capabilities**, select your own Team and enable automatic signing. If you change the Bundle Identifier, update the app identifier in `keychain-access-groups` in `MiniTypelessSecure/MiniTypelessSecure.entitlements` to match.
2. Create **your own Beijing-region Bailian API key**. Run the app, expand “首次使用：保存自己的百炼 API Key” (First use: save your own Bailian API key), paste the key, and click “存入本机 Touch ID 钥匙串” (Save to local Touch ID keychain). An existing key is never overwritten by this action.
3. Click “用 Touch ID 解锁本次运行” (Unlock this session with Touch ID). Grant the requested microphone, Accessibility, and Input Monitoring permissions. Focus the target input field, then use Fn/Globe to start and stop recording. If macOS also switches input sources or opens the emoji panel, set “Press Fn/Globe key to” to “Do Nothing” in System Settings → Keyboard.

Unlock once after each app launch or Mac sleep; subsequent requests in that session reuse the key in memory. Temporary audio is deleted after processing, and transcripts and results remain in window memory. Insertion is attempted only in verified apps when the input focus can be confirmed; otherwise copy the result from the app. Recordings are limited to 120 seconds.

The red window close button hides the window while the app and Fn shortcut continue running. Click the Dock icon to reopen the window. To quit fully, choose **Mini Typeless Secure → Quit** from the menu bar or press Command-Q. Quitting clears the in-memory key, so the next launch requires Touch ID again.

**Keys and costs:** The author's API key is **not** in this repository. Cloning or downloading the project does not copy the author's macOS keychain item. Each user must provide their own key and is responsible for their own Alibaba Cloud usage. Never put a key in source files, README, commits, or issues. The app sends the current audio and transcript to Bailian for transcription and refinement; avoid testing with sensitive content.

The app currently uses `qwen-audio-3.1-asr-flash` for transcription and `qwen3.8-flash` for text refinement. These are separate model calls. Check both quotas and the account balance in Model Studio; overdue accounts may be blocked even with remaining free quota. The 3.1 ASR free quota is measured in tokens, separately from the 3.0 model's audio-seconds quota.

The in-app usage and cost panel stores daily counts locally, starting with this build: reported tokens, recording duration, and output character counts, without transcript content. It estimates today's and this month's list-price cost and projects a full month from the average since tracking started. The estimate does not deduct free quota or include other Alibaba Cloud services. Missing token reports, canceled requests that still complete in the cloud, and older builds may be absent. Use the Alibaba Cloud bill as the source of truth. Successful 30-case evaluations and key-migration API checks also count toward text-model tokens.

This is an experimental build. Text refinement can occasionally change meaning, and insertion can fail depending on the target app or system permissions. Review the output before use. Debug builds include a 30-case synthetic text evaluation that calls the refinement model without recording or inserting. Results and limitations are in [evaluation/README.md](evaluation/README.md).

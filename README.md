# Mini Typeless for macOS

和AI协作的时候，语音交互的速度远比打字快，而且语音输入可以保留流畅的思绪。Mini Typeless 让你在正在使用的输入框里口述草稿、在保留原本意思的基础上做基本整理，让你无缝与AI协作。

**点进输入框 → 按一下 Fn 开始说 → 再按一下 Fn 结束 → 检查草稿。** 停止录音后，应用通过阿里云百炼把语音转成文字，轻量整理标点和措辞，再尝试插入。一次最长录 10 分钟。

[首次使用](#首次使用) · [产品设计与验证](#产品设计与验证) · [English](#english)

## 可以用在哪里？

比如，你正在 Obsidian 梳理一个想法。把光标放在笔记里，按 Fn 说“下周先约两位用户访谈，再决定要不要改首页”，再按 Fn。这句话就可以作为笔记草稿继续编辑。录音和处理进度通过小浮窗提示，平时可以把主窗口关起来。

- **设备与语言**　本项目面向配有 Touch ID 的 Apple Silicon Mac，工程最低支持 macOS 15。主要使用场景是中文口述。整理模型偶尔会改动措辞，请在发送前核对。
- **输入位置**　本页对应的 main 分支支持在 Obsidian、ChatGPT、Codex 和 Claude 桌面版的普通文本框中尝试自动插入。具体输入框能否被识别，取决于应用提供的焦点信息。在微信、Safari 或未成功插入的场景，打开 Mini Typeless 结果窗，点击复制，再自行粘贴。
- **数据与费用**　录音会上传到百炼做转写，转写文字也会发给百炼做整理。使用者提供自己的 API Key，保存在 Mac 钥匙串中。两步分别消耗账户额度，费用以百炼账单为准。首次体验建议说一句不含私人信息的话。

## 首次使用

这里提供 macOS 应用的源代码。要亲自试用，需要在 Mac 上用 Xcode 构建，并准备可联网使用的百炼北京区 API Key。只想了解产品设计，可以直接阅读下方的验收案例。

1. **下载并打开工程。** 在 GitHub 点击 **Code → Download ZIP**，解压后用 Xcode 打开 `MiniTypelessSecure.xcodeproj`。
2. **在自己的 Mac 上运行。** 选择应用目标，在 **Signing & Capabilities** 勾选自动签名并选择自己的开发 Team，运行目标选 **My Mac**，点击 ▶。若因标识被占用而更改 Bundle Identifier，也要将 `MiniTypelessSecure/MiniTypelessSecure.entitlements` 中钥匙串组的标识同步修改，保留前缀 `$(AppIdentifierPrefix)`。
3. **连接自己的百炼账户。** 确认账户可以调用本分支的语音模型 `qwen-audio-3.1-asr-flash` 和整理模型 `qwen3.8-flash`。在应用的齿轮 →「设置与用量」→「权限与密钥」中设置 API Key，存入钥匙串，再用 Touch ID 解锁本次运行。
4. **试说一句。** 按提示授予麦克风、输入监控和辅助功能权限。在支持的应用里点进普通输入框，按下并松开 Fn／地球键开始录音，再按一次结束。若 Fn 同时打开表情面板，可在 Mac「系统设置 → 键盘」中将地球键动作设为「无操作」。

如果转写或整理失败，可以在结果窗查看原因。这个分支的待重试录音是临时副本，需要留存时，请在退出或开始下一次录音前点击「另存录音」。

## 产品设计与验证

一次真实使用中的问题是：说完一段话后断网，如果只能重新口述，刚才的思路也容易丢失。围绕这个问题，项目验证了断网后保留待重试录音、下一次成功录音后替换旧段的流程；也验证了录音途中合盖、开盖后继续处理。读者可以从实际场景回看需求和验收结果。

- [三项实机验收：Fn 输入、合盖恢复、断网后继续录音](docs/changes/CHG-20261020-01.md)
- [30 条口述样本的文字整理评测](evaluation/README.md)
- [产品需求](docs/PRD.md) · [版本记录](CHANGELOG.md) · [自动化测试](Tests/README.md) · [开发流程](docs/DEVELOPMENT.md)

## English

Mini Typeless is a voice-drafting tool for Apple Silicon Macs running macOS 15 or later. Click a text field, tap Fn to record, then tap Fn again to transcribe and lightly edit your words. Review the draft and send it yourself. This branch targets ordinary text fields in Obsidian, ChatGPT, Codex and Claude Desktop. If insertion fails, copy the text from the result window.

To try it, download the source, open `MiniTypelessSecure.xcodeproj` in Xcode, select your signing team and run on My Mac. Add your own Alibaba Cloud Model Studio Beijing API key in Settings, unlock with Touch ID, and grant microphone, Input Monitoring and Accessibility permissions. Audio and transcript are processed in the cloud and billed to your account. Save any pending recording you want to keep before starting another recording or quitting.

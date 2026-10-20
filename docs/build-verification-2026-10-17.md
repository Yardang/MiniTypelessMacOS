# 修复版交付核对（2026-10-17）

- 当前源码重新构建：Debug 签名构建成功。
- 离线回归：录音到结果完整流程、10 分钟合成音频、取消与迟到响应、分段失败及静音、目标应用策略均通过；15 项焦点检查、24 组布局检查通过。
- 安装位置：`/Users/yardang/Applications/Mini Typeless 10 Minute Workflow Fix.app`。
- 已安装应用全部文件与本轮签名构建一致，签名严格校验通过。
- 与旧版相比，签名身份要求、entitlements 及 Bundle Identifier 保持一致；Touch ID 钥匙串代码未改动，未读取或改写真实 API Key。
- 核查时运行中的程序仍是 `Mini Typeless Focus Compatibility v2.app`，从 2026-10-16 23:33:43 本地时间启动。没有退出或覆盖它。开发期间使用旧版不会修改 Swift 源码；旧程序会照常更新其用量记录。
- 新版尚未启动，避免与旧版同时运行。需先保存旧版窗口中需要的结果，再 Command-Q 退出，打开新版并用 Touch ID 解锁。
- 真麦克风十分钟持续录制、百炼云端长音频效果及 Codex 实际接收粘贴，仍需运行新版验收。兼容模式默认关闭，需按实际情况重新勾选。

已安装可执行文件 SHA-256：`209965ee5d48cccfd3462cc7613eebbae2ef11f3bcaf509e3804c2451cdb7ab5`。

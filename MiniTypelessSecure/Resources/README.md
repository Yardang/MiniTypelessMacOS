# DiagnosticSpeech.wav

公开合成测试语音，不含麦克风录音或用户语音。

文本：`这是合成语音测试，项目名称是蓝鲸。`

生成工具：macOS 本地 `say`（Tingting），再用 `afconvert` 转为 16 kHz、单声道、16-bit little-endian PCM WAV。时长约 3.841563 秒。Debug 静音诊断在内存中用其 PCM 样本构造带间隔的长音频。

离线测试会检查此资源可解析、含非零样本，且拼接后的静音区间及两处语音样本完整。

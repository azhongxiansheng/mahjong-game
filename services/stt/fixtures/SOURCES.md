# STT 测试录音来源与许可（#247）

本目录仅存放**可再分发**的公开测试夹具，**不**存储用户音频、房间录音或任何对局证据。

采样规格（全部）：PCM16 LE / 16 kHz / mono / WAV。

| 文件 | 语言 | 来源 | 许可 | 说明 | SHA-256 |
|---|---|---|---|---|---|
| `en_jfk_16k.wav` | en | [whisper.cpp `samples/jfk.wav`](https://github.com/ggerganov/whisper.cpp/blob/master/samples/jfk.wav)（原录音为美国总统公开演讲片段，公有领域） | Public domain（录音）/ 仓库样本按 whisper.cpp 分发 | ~11s 英文；faster-whisper 官方 smoke 同款内容 | `4d968ac99a1d0d4bc42ae8dd1552f4235e7b952a8121b39797f3dc2ca16123e9` |
| `zh_zhonghuarenmingongheguo_16k.wav` | zh | Wikimedia Commons [`Pronunciation of Zhonghuarenmingongheguo.ogg`](https://commons.wikimedia.org/wiki/File:Pronunciation_of_Zhonghuarenmingongheguo.ogg) | **Public domain** | 中文「中华人民共和国」发音；转 16 kHz mono | `73d420ba966ae6d948b904eed3aa6e3c273946fa10a124f6143ef2e52a79f3e8` |
| `ja_tokyo_16k.wav` | ja | Wikimedia Commons [`Ja-Tokyo.ogg`](https://commons.wikimedia.org/wiki/File:Ja-Tokyo.ogg) | **Public domain** | 日语「東京」发音；转 16 kHz mono | `9e042b01778eaba87656c365a221c51e50d3f9ad00fc92b2480918f64ec31aba` |
| `silence_2s_16k.wav` | — | 本地 `ffmpeg anullsrc` 合成 | 无版权客体 | 2s 静音，VAD 负向 | `4dbd796dfa57d817c2bc996024c5d815075379f8608dda6dccaa52ee60c6e8e3` |
| `noise_150ms_16k.wav` | — | 本地 `ffmpeg anoisesrc` 合成 | 无版权客体 | 150ms 粉噪，短噪声负向 | `2b8bf61f828af6733cb0f8edfc67575d9ccdb5e33612febb83b42f567e1068ba` |

## 校验

```bash
cd services/stt/fixtures
shasum -a 256 *.wav
```

## 约束

- 禁止提交用户麦克风录音、房间回放、带 PII 的素材。
- 夹具仅用于自动化与本机延迟基线；**公共网络四客户端链路未端到端验证**。

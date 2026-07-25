# STT 服务（#247 / E4-05）

公共休闲场权威转写：`faster-whisper` multilingual **small** + Silero VAD（`vad_filter=True`）。

独立 Python 3.11 进程，经**内部 WebSocket** 接收 VoiceRelay/Worker 转发的 PCM16 LE / 16 kHz / mono / 20ms 帧，输出稳定 `utterance_id` 的 `TRANSCRIPT_PARTIAL` / `TRANSCRIPT_FINAL`。

**网络端到端（公网四客户端）未验证。** 本机 listener 集成 ≠ 生产公网链路。

## 非目标

- 不实现 #248 new-api 回退
- 不扩张 Control Plane 匹配 / 根 `Dockerfile` / `main.go` / E7 compose
- 不持久化 PCM 或转写；服务重启不恢复
- 不创建第二个 `grace_deadline`；只遵从 Worker 的 `window_id` 代际与唯一 deadline

## 依赖（锁定）

见 `requirements.txt`：

- `faster-whisper==1.2.1`
- `ctranslate2==4.7.1`
- `websockets==14.2`

```bash
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

模型默认走 Hugging Face 标准缓存（`STT_MODEL_CACHE` 可覆盖；**禁止**在代码写死用户绝对路径）。

## 环境变量（无凭证）

| 变量 | 默认 | 说明 |
|---|---|---|
| `STT_HOST` | `127.0.0.1` | 监听地址 |
| `STT_PORT` | `9100` | 监听端口 |
| `STT_MODEL` | `small` | faster-whisper 模型名 |
| `STT_DEVICE` | `cpu` | `cpu` / `cuda` |
| `STT_COMPUTE_TYPE` | `int8` | 如 `int8` / `float16` |
| `STT_MODEL_CACHE` | （空） | 可选 download_root |
| `STT_MAX_PCM_BYTES` | `960000` | 单 utterance 上限（30s） |
| `STT_MAX_UTTERANCE_MS` | `30000` | 单 utterance 时长上限 |
| `STT_MAX_ACTIVE_UTTERANCES` | `16` | 并发 utterance 上限 |
| `STT_VAD_FILTER` | `1` | final 启用 Silero VAD |

**不要**设置或记录任何 API token / 密钥。

## 启动

```bash
cd services/stt
source .venv/bin/activate   # 或任意装好锁定依赖的 3.11 环境
python -m stt_service
# → stt listening ws://127.0.0.1:9100 ...
```

Godot Worker：

```bash
export TOKEN_SIGNING_SECRET='…≥32 bytes…'
export STT_SERVICE_URL=ws://127.0.0.1:9100
godot --headless --path godot \
  -s res://server/headless_worker_main.gd \
  -- --host=127.0.0.1 --port=9000 --voice-port=9001 --stt-url=ws://127.0.0.1:9100
```

## 内部协议（摘要）

客户端 → 服务：

- `UTTERANCE_START`：`room_id, seat, hand_seq, window_id, utterance_id`
- `AUDIO_CHUNK`：JSON `pcm_b64` + 完整 `room_id/seat/hand_seq/window_id/utterance_id`（**不支持**二进制 STTA）
- `UTTERANCE_COMMIT`：含权威 `ptt_end_server_seq`
- `UTTERANCE_CANCEL` / `WINDOW_CANCEL`：代际 **`room_id + hand_seq + window_id`**（跨房间/跨局隔离；幂等）
- 采集期实时 `AUDIO_CHUNK`（`want_partial`）；权威 `PTT_END` 后仅 `COMMIT`
- 服务断线释放本连接缓冲；**不恢复**旧转写；重连只服务新 utterance

服务 → 客户端：

- `TRANSCRIPT_PARTIAL` / `TRANSCRIPT_FINAL`：字段对齐 ADR（`source=faster_whisper`, `lang`, `text`, `is_final`, …）
- `UTTERANCE_FAILED`：`EMPTY` / `VAD_NO_SPEECH` / `LANG_FILTERED` / `OVERFLOW` / `CANCELLED` …

权威 final 仅 `zh`/`en`/`ja` 非空文本可由 Worker 摄入 RewardWindow；partial **不**进窗口累计。

## 有界内存

| 上限 | 值 | 超限行为 |
|---|---|---|
| 单 utterance PCM | 960_000 bytes（30s） | `OVERFLOW`，释放缓冲 |
| 并发 utterance | 16 | 拒绝 START |
| 生命周期 | 进程内存 | 完成/取消/断线/停止后释放；**不写磁盘** |

## 测试夹具

见 `fixtures/SOURCES.md`（CC0/公有领域；含 SHA-256）。

```bash
cd services/stt
# 快速（假模型/会话边界）
pytest -q tests/test_protocol.py tests/test_session_bounds.py tests/test_ws_integration.py -m 'not slow'

# 真实模型中英日 + VAD + WS（首次会加载 small，较慢）
pytest -q tests -m slow -s
```

### 本机 Godot ↔ Python 链路（可选 slow GUT）

```bash
# 1) 起真实 listener（small / CPU int8 / VAD）
cd services/stt
STT_PORT=19123 STT_PYTHON=/path/to/python3.11 ./scripts/run_godot_e2e_helper.sh

# 2) GUT：SttServiceClient/Bridge 分帧 WAV + 权威 PTT_END
# 默认尝试本机 venv；STT_E2E=0 跳过
cd ../..
STT_E2E=1 godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/server -gselect=test_stt_godot_python_link -gexit
```

**公网四客户端 / 容器部署未验证。** 本机链 ≠ 生产部署。

## 性能基线

仅记录**当前机器实测**（RTF/墙钟），不虚构 SLA。见测试 stdout 中 `[EN]`/`[ZH]`/`[JA]` 行。

## 与 Worker / RewardWindow 的边界

- 取消代际键 = `room_id|hand_seq|window_id`（**不是** `room_id|window_id`）；荣和 `CANCELLED` 时 Worker 幂等 `WINDOW_CANCEL`
- **仅 OPEN** 允许新 `PTT_START`（IDLE/CLOSING/SETTLED/CANCELLED fail-closed）
- partial 广播前再读 live phase/deadline；final 先准入再广播
- STT 传输层有界重连（非 RewardWindow 时钟）；断开后旧 stream 标记 `drop_until_end`，禁止截断续传；只服务**之后**新 utterance
- **取消/排空语义**：Worker window/deadline/cancel 只做逻辑结果取消（立即释放会话与 PCM、不发送迟到 final）；faster-whisper 底层 `to_thread` **不可抢占**，全局 infer slot 须等该线程真正返回后才释放。不引入第二权威超时，也不假装 `asyncio.wait_for` 能中止 CPU 推理。
- partial/final 经 VoiceRelay **仅**广播同房 HUMAN；STT 文本不触发发奖
- 唯一 `grace_deadline_at` / 权威 now 属 #252 RewardWindow 时钟域；STT **不得**使用 Worker 墙钟或自行 `advance_reward_time`
- `context_boundary_server_seq` **不得**用于语音 final 准入
- STT 文本只进 RewardWindow 累计，绝不直接 `ITEM_GRANTED` / 改分

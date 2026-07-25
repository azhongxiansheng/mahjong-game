# STT 服务（#247 / #248 · E4-05 / E4-06）

公共休闲场权威转写：`faster-whisper` multilingual **small** + Silero VAD（`vad_filter=True`）为主路径；主推理异常或逻辑超时后，可对**最终片段**调用 OpenAI-compatible/new-api `/v1/audio/transcriptions` 备份。

独立 Python 3.11 进程，经**内部 WebSocket** 接收 VoiceRelay/Worker 转发的 PCM16 LE / 16 kHz / mono / 20ms 帧，输出稳定 `utterance_id` 的 `TRANSCRIPT_PARTIAL` / `TRANSCRIPT_FINAL`。

**网络端到端（公网四客户端）未验证。** 本机 listener 集成 ≠ 生产公网链路。真实 new-api 供应商 smoke ≠ 公网部署 / 四客户端 e2e。

## 非目标

- 不扩张 Control Plane 匹配 / 根 `Dockerfile` / `main.go` / E7 compose
- 不持久化 PCM 或转写；服务重启不恢复
- 不创建第二个 `grace_deadline`；只遵从 Worker 的 `window_id` 代际与唯一 deadline
- 不实现举报、静音、自动禁言（E6）
- 模型不直接发奖；文本只经既有 RewardWindow 准入

## 依赖（锁定）

见 `requirements.txt`：

- `faster-whisper==1.2.1`
- `ctranslate2==4.7.1`
- `websockets==14.2`
- `httpx==0.28.1`（#248 new-api 备份 HTTP）

```bash
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

模型默认走 Hugging Face 标准缓存（`STT_MODEL_CACHE` 可覆盖；**禁止**在代码写死用户绝对路径）。

## 环境变量

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
| `STT_PRIMARY_TIMEOUT_MS` | `30000` | 主推理逻辑超时（服务拥有；非 RewardWindow 时钟） |
| `STT_NEW_API_ENDPOINT` | （空） | 完整 transcription URL；缺则备份禁用 |
| `STT_NEW_API_MODEL` | （空） | 备份模型名；缺则备份禁用 |
| `STT_NEW_API_TOKEN` | （空） | Bearer token；**禁止**写入日志/文档示例/repr |
| `STT_NEW_API_TIMEOUT_MS` | `10000` | 备份 HTTP 超时 |
| `STT_CIRCUIT_FAILURE_THRESHOLD` | `3` | 熔断打开阈值（仅统计真实备份失败） |
| `STT_CIRCUIT_COOLDOWN_MS` | `30000` | OPEN → HALF_OPEN 冷却 |

**专用 `STT_NEW_API_*` 配置；不要静默复用资产生成用的 `OPENAI_*`。**
缺任一必需 new-api 配置时备份明确禁用，主 faster-whisper 仍可运行。
**不要**在日志、PONG、异常、测试失败信息中记录 token。

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
- `PING` → `PONG`：向后兼容健康摘要（`primary.ok`、`new_api.enabled`、`new_api.circuit`）；**不含** endpoint/model/token/原始错误

服务 → 客户端：

- `TRANSCRIPT_PARTIAL`：`source=faster_whisper`（partial **永不**走 new-api）
- `TRANSCRIPT_FINAL`：`source=faster_whisper` 或 `source=new_api`
- `UTTERANCE_FAILED`：稳定 reason（如 `EMPTY` / `VAD_NO_SPEECH` / `LANG_FILTERED` / `PRIMARY_TIMEOUT` / `PRIMARY_ERROR` / `NEW_API_*` / `OVERFLOW` / `CANCELLED`）；失败消息保持服务级来源字段

权威 final 仅 `zh`/`en`/`ja` 非空文本可由 Worker 摄入 RewardWindow；partial **不**进窗口累计。

## #248 回退策略

1. **仅 final commit 路径**可在主异常 / 主逻辑超时后回退；partial 绝不调用备份。
2. 正常无文本终态（`EMPTY` / `VAD_NO_SPEECH` / `LANG_FILTERED`）**不是**供应商失败，不回退（避免重复计费）。
3. 备份将 PCM16 LE 在内存封装为 WAV multipart 上传；不写磁盘。
4. 同一 `room_id+seat+utterance_id+ptt_end_server_seq` 主备最多一个终态 final；重复 commit 幂等。
5. 主 CPU 逻辑超时后底层线程后台排空并继续占用原 infer 槽；可先采用备结果，迟到主结果只释放资源，不再次提交/广播。
6. 熔断：真实备份 transport/timeout/非 2xx/无效响应计入失败；OPEN 后 eligible 快速失败不发 HTTP；冷却后仅一个 HALF_OPEN 探测。
7. 计时器所有权：STT 拥有主逻辑 timeout、备 HTTP timeout、熔断冷却；#252/Worker 仍唯一拥有 RewardWindow `grace_deadline_at`/相位/取消时钟。

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
# 快速（假模型/会话边界/回退与熔断）
pytest -q tests/test_protocol.py tests/test_session_bounds.py tests/test_ws_integration.py \
  tests/test_circuit_breaker.py tests/test_new_api_fallback.py -m 'not slow'

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
- Godot `SttBridge` 接受 `source=faster_whisper` 与 `source=new_api`；广播保留来源，不重写

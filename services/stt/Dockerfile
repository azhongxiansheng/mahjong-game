# #255 faster-whisper STT 测试镜像。
# 模型二进制不入镜像；运行时经 STT_MODEL_CACHE 卷下载/复用。
# 默认 multilingual small + CPU int8。网络端到端未验证。
FROM python:3.11-slim-bookworm

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# 运行时依赖：单一锁文件输入（精确版本；不含 pytest）。
COPY requirements.runtime.lock.txt /tmp/requirements.runtime.lock.txt
RUN pip install --no-cache-dir -r /tmp/requirements.runtime.lock.txt \
  && rm -f /tmp/requirements.runtime.lock.txt

COPY stt_service/ /app/stt_service/
COPY scripts/healthcheck_ws.py /usr/local/bin/healthcheck_ws.py
RUN chmod +x /usr/local/bin/healthcheck_ws.py \
  && mkdir -p /var/cache/stt-models \
  && chown -R nobody:nogroup /var/cache/stt-models /app

ENV STT_HOST="0.0.0.0"
ENV STT_PORT="9100"
ENV STT_MODEL="small"
ENV STT_DEVICE="cpu"
ENV STT_COMPUTE_TYPE="int8"
ENV STT_MODEL_CACHE="/var/cache/stt-models"
# new-api 备份仅经环境变量；缺省禁用。禁止把 token 写入镜像层。
ENV STT_NEW_API_ENDPOINT=""
ENV STT_NEW_API_MODEL=""
ENV STT_NEW_API_TOKEN=""

EXPOSE 9100

# 首次拉模型可能较慢；start_period 覆盖冷启动。
HEALTHCHECK --interval=5s --timeout=5s --start-period=300s --retries=30 \
  CMD python3 /usr/local/bin/healthcheck_ws.py --mode stt --url ws://127.0.0.1:9100 --timeout 4

USER nobody
CMD ["python", "-m", "stt_service"]

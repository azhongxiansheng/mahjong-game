"""python -m stt_service"""

from __future__ import annotations

import asyncio
import logging
import sys

from .config import SttConfig
from .server import run_server


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    cfg = SttConfig.from_env()
    try:
        asyncio.run(run_server(cfg))
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()

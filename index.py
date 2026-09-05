"""
Vercel Python entrypoint. Vercel's Python runtime detects an ASGI-compatible
`app` object exported from a file under /api and wraps it as a single
serverless function -- this is what keeps the existing FastAPI structure
intact with no per-route rewrite.
"""

import sys
from pathlib import Path

# Make the backend/ directory importable so `from app.main import app` works
# regardless of Vercel's working directory at build time.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.main import app  # noqa: E402

# Vercel looks for a module-level `app` (or `handler`) callable.
__all__ = ["app"]

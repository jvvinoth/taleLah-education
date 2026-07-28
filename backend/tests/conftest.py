"""
Test isolation — pytest must NEVER touch the shared Neon database.

Without this, a local `.env` DATABASE_URL leaks into TestClient startup and
test fixtures get persisted to production (a real TestKid profile once
reached the live app this way). Clearing the env var here forces the
persistence layer into memory-only mode for every test session.
"""
from __future__ import annotations

import os

os.environ["DATABASE_URL"] = ""

from backend.core.config import settings  # noqa: E402

settings.database_url = ""

"""
Test isolation — pytest must NEVER touch the shared Neon database or reach out
to real cloud providers.

Without this, a local `.env` DATABASE_URL leaks into TestClient startup and
test fixtures get persisted to production (a real TestKid profile once
reached the live app this way). Clearing the env var here forces the
persistence layer into memory-only mode for every test session.

We also clear the LLM/ASR/TTS provider keys so the suite is hermetic: the
full-pipeline integration test drives capture→generate→approve→session and
must use the deterministic offline fallbacks, never real (slow, billable,
flaky) network calls.
"""
from __future__ import annotations

import os

os.environ["DATABASE_URL"] = ""

from backend.core.config import settings  # noqa: E402

settings.database_url = ""
# Force every agent/provider onto its offline fallback path.
settings.dashscope_api_key = ""
settings.sarvam_api_key = ""
settings.google_application_credentials = ""
settings.elevenlabs_api_key = ""
# Email + object storage stay on their offline fallbacks (log the code / DB blob).
settings.resend_api_key = ""
settings.r2_access_key_id = ""
settings.r2_secret_access_key = ""

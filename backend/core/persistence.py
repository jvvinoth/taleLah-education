"""TaleLah — Neon (serverless PostgreSQL) persistence layer.

Write-through design:
- The in-memory dicts in v1.py / orchestrator stay the READ path (fast,
  zero churn to the request handlers).
- Every mutation is mirrored to Postgres fire-and-forget (never blocks or
  fails a request).
- On startup the stores are hydrated back from the tables, so profiles,
  stories, sessions and saved memories survive restarts and redeploys.

Degradation ladder: if DATABASE_URL is not Postgres, asyncpg is missing,
or the pool cannot be created, the app runs memory-only exactly as before.
"""
from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, Optional

from pydantic import BaseModel

from .config import settings

try:
    import asyncpg
except ImportError:  # pragma: no cover — asyncpg is in requirements.txt
    asyncpg = None

logger = logging.getLogger(__name__)

# One JSONB document table per entity — visible, queryable tables in the
# Neon console while Pydantic models remain the single source of schema.
DOC_TABLES = (
    "adults",
    "child_profiles",
    "family_speakers",
    "moments",
    "story_packages",
    "story_sessions",
    "saved_memories",
    "traces",
)


class Persistence:
    """asyncpg-backed document store with a sync fire-and-forget facade."""

    def __init__(self) -> None:
        self.pool: Optional["asyncpg.Pool"] = None

    @property
    def enabled(self) -> bool:
        return self.pool is not None

    def _dsn(self) -> Optional[str]:
        url = settings.database_url
        if not url.startswith("postgresql"):
            return None  # e.g. the sqlite dev default → memory-only
        # SQLAlchemy-style scheme → plain libpq DSN for asyncpg
        return url.replace("postgresql+asyncpg://", "postgresql://", 1)

    async def init(self) -> bool:
        """Create the pool and tables. Returns True when persistence is on."""
        dsn = self._dsn()
        if dsn is None:
            logger.info("💾 Persistence off (DATABASE_URL is not Postgres) — memory-only")
            return False
        if asyncpg is None:
            logger.warning("💾 asyncpg not installed — memory-only")
            return False
        try:
            self.pool = await asyncpg.create_pool(
                dsn, min_size=1, max_size=5, timeout=15
            )
            async with self.pool.acquire() as conn:
                for table in DOC_TABLES:
                    await conn.execute(
                        f"CREATE TABLE IF NOT EXISTS {table} ("
                        "  id TEXT PRIMARY KEY,"
                        "  data JSONB NOT NULL,"
                        "  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()"
                        ")"
                    )
                await conn.execute(
                    "CREATE TABLE IF NOT EXISTS media_blobs ("
                    "  package_id TEXT NOT NULL,"
                    "  filename TEXT NOT NULL,"
                    "  data BYTEA NOT NULL,"
                    "  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),"
                    "  PRIMARY KEY (package_id, filename)"
                    ")"
                )
            logger.info("💾 Neon persistence ON — tables ready")
            return True
        except Exception as e:
            logger.warning(f"💾 Persistence unavailable ({e}) — memory-only")
            self.pool = None
            return False

    async def close(self) -> None:
        if self.pool is not None:
            await self.pool.close()
            self.pool = None

    # ── Write path (sync facade, fire-and-forget) ──────────────────────

    def _spawn(self, coro) -> None:
        """Schedule a write without ever blocking/failing the request."""
        try:
            asyncio.get_running_loop().create_task(coro)
        except RuntimeError:  # no loop (unit tests) — drop silently
            coro.close()

    def save(self, table: str, row_id: str, payload: Any) -> None:
        """Upsert one document. payload: BaseModel or JSON-able dict."""
        if not self.enabled:
            return
        data = (
            payload.model_dump(mode="json")
            if isinstance(payload, BaseModel)
            else payload
        )
        self._spawn(self._upsert(table, row_id, json.dumps(data, default=str)))

    def delete(self, table: str, row_id: str) -> None:
        if not self.enabled:
            return
        self._spawn(self._execute(f"DELETE FROM {table} WHERE id = $1", row_id))

    def save_blobs(self, package_id: str, blobs: dict) -> None:
        """Mirror a package's pre-generated audio ({filename: bytes})."""
        if not self.enabled or not blobs:
            return
        self._spawn(self._upsert_blobs(package_id, dict(blobs)))

    def delete_blobs(self, package_id: str) -> None:
        if not self.enabled:
            return
        self._spawn(
            self._execute(
                "DELETE FROM media_blobs WHERE package_id = $1", package_id
            )
        )

    async def _upsert(self, table: str, row_id: str, data_json: str) -> None:
        try:
            async with self.pool.acquire() as conn:
                await conn.execute(
                    f"INSERT INTO {table} (id, data) VALUES ($1, $2::jsonb) "
                    "ON CONFLICT (id) DO UPDATE "
                    "SET data = EXCLUDED.data, updated_at = now()",
                    row_id,
                    data_json,
                )
        except Exception as e:
            logger.warning(f"💾 upsert {table}/{row_id} failed: {e}")

    async def _upsert_blobs(self, package_id: str, blobs: dict) -> None:
        try:
            async with self.pool.acquire() as conn:
                await conn.executemany(
                    "INSERT INTO media_blobs (package_id, filename, data) "
                    "VALUES ($1, $2, $3) "
                    "ON CONFLICT (package_id, filename) DO UPDATE "
                    "SET data = EXCLUDED.data, updated_at = now()",
                    [(package_id, name, blob) for name, blob in blobs.items()],
                )
        except Exception as e:
            logger.warning(f"💾 media upsert {package_id} failed: {e}")

    async def _execute(self, sql: str, *args) -> None:
        try:
            async with self.pool.acquire() as conn:
                await conn.execute(sql, *args)
        except Exception as e:
            logger.warning(f"💾 write failed ({sql.split()[0]}): {e}")

    # ── Read path (startup hydration only) ─────────────────────────────

    async def fetch_all(self, table: str) -> dict:
        """All rows of a document table → {id: data-dict}."""
        if not self.enabled:
            return {}
        async with self.pool.acquire() as conn:
            rows = await conn.fetch(f"SELECT id, data FROM {table}")
        return {r["id"]: json.loads(r["data"]) for r in rows}

    async def fetch_blobs(self) -> dict:
        """All media blobs → {package_id: {filename: bytes}}."""
        if not self.enabled:
            return {}
        async with self.pool.acquire() as conn:
            rows = await conn.fetch(
                "SELECT package_id, filename, data FROM media_blobs"
            )
        out: dict = {}
        for r in rows:
            out.setdefault(r["package_id"], {})[r["filename"]] = bytes(r["data"])
        return out


persistence = Persistence()

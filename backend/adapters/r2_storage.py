"""Cloudflare R2 object storage — S3-compatible, used for profile photos.

Degradation ladder: without R2 credentials every call is a no-op/None and
the caller falls back to Postgres blob storage (persistence.profile_photos).
boto3 is sync, so calls run in the default executor.
"""
from __future__ import annotations

import asyncio
import logging
from typing import Optional

from ..core.config import settings

logger = logging.getLogger(__name__)

try:
    import boto3
    from botocore.config import Config as BotoConfig
except ImportError:  # pragma: no cover — boto3 is in requirements.txt
    boto3 = None


class R2Storage:
    """Thin async wrapper over the R2 S3 API for small binary objects."""

    def __init__(self) -> None:
        self._client = None

    @property
    def enabled(self) -> bool:
        return bool(
            boto3
            and settings.r2_access_key_id
            and settings.r2_secret_access_key
            and (settings.r2_endpoint or settings.r2_account_id)
        )

    def _get_client(self):
        if self._client is None:
            endpoint = settings.r2_endpoint or (
                f"https://{settings.r2_account_id}.r2.cloudflarestorage.com"
            )
            self._client = boto3.client(
                "s3",
                endpoint_url=endpoint,
                aws_access_key_id=settings.r2_access_key_id,
                aws_secret_access_key=settings.r2_secret_access_key,
                config=BotoConfig(region_name="auto", retries={"max_attempts": 2}),
            )
        return self._client

    async def put_bytes(self, key: str, data: bytes, content_type: str) -> bool:
        if not self.enabled:
            return False
        loop = asyncio.get_running_loop()

        def _put() -> None:
            self._get_client().put_object(
                Bucket=settings.r2_bucket_name,
                Key=key,
                Body=data,
                ContentType=content_type,
            )

        try:
            await loop.run_in_executor(None, _put)
            logger.info(f"☁️  R2 put {key} ({len(data)}B)")
            return True
        except Exception as e:  # noqa: BLE001 — storage must not fail requests
            logger.warning(f"☁️  R2 put {key} failed: {e}")
            return False

    async def get_bytes(self, key: str) -> Optional[bytes]:
        if not self.enabled:
            return None
        loop = asyncio.get_running_loop()

        def _get() -> bytes:
            obj = self._get_client().get_object(
                Bucket=settings.r2_bucket_name, Key=key
            )
            return obj["Body"].read()

        try:
            return await loop.run_in_executor(None, _get)
        except Exception:  # noqa: BLE001 — missing key or network → miss
            return None


r2_storage = R2Storage()

"""
Google Gemini provider adapter.

Implements LLMProvider using Gemini via the OpenAI-compatible endpoint
(https://generativelanguage.googleapis.com/v1beta/openai). No SDK dependency —
just httpx, matching the DashScope provider pattern.

When GEMINI_API_KEY is set, Gemini becomes the default story-generation LLM;
Qwen-Max stays registered as a fallback. Language packs can also route to
Gemini explicitly via ``"llm": "gemini"`` (AC-08).
"""
from __future__ import annotations

import json
import logging
from typing import Optional

import httpx

from .interfaces import LLMProvider

logger = logging.getLogger(__name__)

DEFAULT_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/openai"


class GeminiLLMProvider(LLMProvider):
    """Gemini text generation via the OpenAI-compatible API endpoint."""

    def __init__(
        self,
        api_key: str,
        base_url: str = DEFAULT_BASE_URL,
        model: str = "gemini-2.5-flash",
    ):
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.model = model
        self._client = httpx.AsyncClient(timeout=90.0)

    async def generate(
        self,
        prompt: str,
        system: str = "",
        temperature: float = 0.7,
        max_tokens: int = 2000,
        response_format: Optional[dict] = None,
    ) -> str:
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})

        body: dict = {
            "model": self.model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        # Gemini's OpenAI-compatible endpoint honours JSON mode.
        if response_format:
            body["response_format"] = response_format

        resp = await self._client.post(
            f"{self.base_url}/chat/completions",
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
            json=body,
        )
        resp.raise_for_status()
        data = resp.json()
        content = data["choices"][0]["message"]["content"]
        logger.info(
            f"[Gemini LLM] Generated {len(content)} chars with {self.model}"
        )
        return content

    async def generate_json(
        self,
        prompt: str,
        system: str = "",
        schema: Optional[dict] = None,
    ) -> dict:
        """Generate structured JSON from a prompt.

        Uses Gemini's JSON response mode when available, and strips markdown
        code fences as a safety net (same handling as the DashScope provider).
        """
        raw = await self.generate(
            prompt=prompt,
            system=system + "\n\nRespond ONLY with valid JSON. No markdown fences. No explanation.",
            temperature=0.3,
            max_tokens=4000,
            response_format={"type": "json_object"},
        )

        # Strip markdown code fences if present
        text = raw.strip()
        if text.startswith("```"):
            lines = text.split("\n")
            # Remove the first fence line and any trailing fence lines
            lines = [ln for ln in lines[1:] if not ln.strip().startswith("```")]
            text = "\n".join(lines)

        try:
            result = json.loads(text)
            return result if isinstance(result, dict) else {"data": result}
        except json.JSONDecodeError:
            logger.warning("[Gemini LLM] Failed to parse JSON, returning raw")
            return {"raw": text}

    async def close(self):
        await self._client.aclose()

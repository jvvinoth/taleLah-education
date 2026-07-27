"""
DashScope (Alibaba Cloud) provider adapters.

Implements LLMProvider and VisionProvider using Qwen-Max and Qwen-VL-Max
via the OpenAI-compatible API endpoint.
"""
from __future__ import annotations

import json
import logging
from typing import Optional

import httpx

from .interfaces import LLMProvider, VisionProvider

logger = logging.getLogger(__name__)

# International DashScope endpoint (OpenAI-compatible)
DEFAULT_BASE_URL = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"


class DashScopeLLMProvider(LLMProvider):
    """Qwen-Max text generation via DashScope OpenAI-compatible API."""

    def __init__(self, api_key: str, base_url: str = DEFAULT_BASE_URL, model: str = "qwen-max"):
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.model = model
        self._client = httpx.AsyncClient(timeout=60.0)

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

        body = {
            "model": self.model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        if response_format:
            body["response_format"] = response_format

        resp = await self._client.post(
            f"{self.base_url}/chat/completions",
            headers={"Authorization": f"Bearer {self.api_key}"},
            json=body,
        )
        resp.raise_for_status()
        data = resp.json()
        content = data["choices"][0]["message"]["content"]
        logger.info(f"[DashScope LLM] Generated {len(content)} chars with {self.model}")
        return content

    async def generate_json(
        self,
        prompt: str,
        system: str = "",
        schema: Optional[dict] = None,
    ) -> dict:
        """Generate JSON — parses from response, handling markdown fences."""
        raw = await self.generate(
            prompt=prompt,
            system=system + "\n\nRespond ONLY with valid JSON. No markdown fences. No explanation.",
            temperature=0.3,
            max_tokens=3000,
        )

        # Strip markdown code fences if present
        text = raw.strip()
        if text.startswith("```"):
            lines = text.split("\n")
            # Remove first and last lines (``` markers)
            lines = [l for l in lines[1:] if not l.strip().startswith("```")]
            text = "\n".join(lines)

        try:
            result = json.loads(text)
            return result if isinstance(result, dict) else {"data": result}
        except json.JSONDecodeError:
            logger.warning(f"[DashScope LLM] Failed to parse JSON, returning raw")
            return {"raw": text}

    async def close(self):
        await self._client.aclose()


class DashScopeVisionProvider(VisionProvider):
    """Qwen-VL-Max image understanding via DashScope OpenAI-compatible API."""

    def __init__(self, api_key: str, base_url: str = DEFAULT_BASE_URL, model: str = "qwen-vl-max"):
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.model = model
        self._client = httpx.AsyncClient(timeout=60.0)

    async def analyze_image(
        self,
        image_url: str,
        prompt: str = "Describe what you see.",
    ) -> str:
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": image_url}},
                ],
            }
        ]

        resp = await self._client.post(
            f"{self.base_url}/chat/completions",
            headers={"Authorization": f"Bearer {self.api_key}"},
            json={"model": self.model, "messages": messages, "max_tokens": 500},
        )
        resp.raise_for_status()
        data = resp.json()
        content = data["choices"][0]["message"]["content"]
        logger.info(f"[DashScope Vision] Analyzed image with {self.model}")
        return content

    async def extract_facts(
        self,
        image_url: str,
        child_age: str = "",
    ) -> list[dict]:
        """Extract structured facts from an image for the Moment Lens."""
        system = (
            "You are a child activity observer. Describe ONLY observable facts about what "
            "a child did. Do NOT identify people by name. Do NOT infer ability, diagnosis, "
            "emotion, ethnicity, or religion. Respond with a JSON array of objects, each with "
            "'text' (string) and 'confidence' (float 0-1). Max 5 facts."
        )
        age_hint = f" The child is approximately {child_age} years old." if child_age else ""

        messages = [
            {"role": "system", "content": system},
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": f"Describe what the child did in this image.{age_hint} "
                                "Return JSON array only.",
                    },
                    {"type": "image_url", "image_url": {"url": image_url}},
                ],
            },
        ]

        resp = await self._client.post(
            f"{self.base_url}/chat/completions",
            headers={"Authorization": f"Bearer {self.api_key}"},
            json={
                "model": self.model,
                "messages": messages,
                "max_tokens": 1000,
                "temperature": 0.3,
            },
        )
        resp.raise_for_status()
        data = resp.json()
        raw = data["choices"][0]["message"]["content"]

        # Parse JSON from response
        text = raw.strip()
        if text.startswith("```"):
            lines = text.split("\n")
            lines = [l for l in lines[1:] if not l.strip().startswith("```")]
            text = "\n".join(lines)

        try:
            facts = json.loads(text)
            if isinstance(facts, list):
                return facts[:5]
            return [facts] if isinstance(facts, dict) else [{"text": raw, "confidence": 0.8}]
        except json.JSONDecodeError:
            logger.warning("[DashScope Vision] Failed to parse facts JSON")
            return [{"text": raw, "confidence": 0.8}]

    async def close(self):
        await self._client.aclose()

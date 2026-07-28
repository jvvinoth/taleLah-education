"""
Agent 1: Moment Lens — specs/agents/1-moment-lens.md

Turns a parent's photo/voice/text into verified, structured facts
about what the child did.

Model: Qwen-VL-Max (image) + Qwen-Max (text normalisation).
Reads: moment media, child age, selected language.
Writes: momentFacts with per-fact confidence.
"""
from __future__ import annotations

import logging

from ..schemas.story_package import MomentFact, StoryPackage
from .base import BaseAgent

logger = logging.getLogger(__name__)

TEXT_SYSTEM_PROMPT = """You are a child activity observer for a language learning app.
Your job is to extract structured, observable facts from a parent's description
of what their child did.

Rules:
- Describe ONLY observable information. Do NOT identify people by name.
- Do NOT infer ability, diagnosis, emotion, ethnicity, or religion.
- Keep each fact to one observable action or object.
- Score each fact's confidence 0.0-1.0 (how clearly the parent's words support it).
- If the description is too vague to build a story from (no clear activity,
  object, or place), set "clarification_question" to ONE short, friendly
  question asking the parent for the missing detail. Otherwise set it to "".

Respond with a JSON object:
{"facts": [{"text": "observable fact description", "confidence": 0.95}],
 "clarification_question": ""}

Max 5 facts. No markdown. No explanation."""

# F3 — below this per-fact confidence, we pause and ask the parent one question
CLARIFY_THRESHOLD = 0.7
DEFAULT_QUESTION = (
    "Could you share one more detail — what did your child play with, "
    "and where did it happen?"
)


def _clamp(value: float) -> float:
    return max(0.0, min(1.0, value))


class MomentLensAgent(BaseAgent):
    name = "moment_lens"
    spec_version = "1.2.0"

    def _clarification_question(
        self, moment_text: str, facts: list[MomentFact], llm_question: str
    ) -> str:
        """F3 — decide whether the pipeline should pause for one parent answer."""
        if llm_question:
            return llm_question
        if len(moment_text.split()) < 4:
            return DEFAULT_QUESTION
        if not facts or max(f.confidence for f in facts) < CLARIFY_THRESHOLD:
            return DEFAULT_QUESTION
        return ""

    async def execute(self, package: StoryPackage) -> StoryPackage:
        logger.info(f"[MomentLens] Processing package {package.id}")

        # Check if facts already exist (skip if pre-populated by API route)
        if package.moment_facts:
            logger.info("[MomentLens] Facts already populated, skipping")
            self._record_provenance(package)
            return package

        moment_text = package.moment_text.strip()
        llm_question = ""

        if self.llm and moment_text:
            try:
                result = await self.llm.generate_json(
                    prompt=(
                        "A parent described their child's activity:\n"
                        f'"{moment_text}"\n\n'
                        "Extract observable facts as a JSON object."
                    ),
                    system=TEXT_SYSTEM_PROMPT,
                )

                # generate_json returns the parsed dict directly, or
                # {"data": [...]} for top-level arrays, or {"raw": text} on parse failure
                payload = result if isinstance(result, dict) else {}
                if "facts" not in payload:
                    data = payload.get("data")
                    if isinstance(data, dict):
                        payload = data
                    elif isinstance(data, list):
                        payload = {"facts": data}

                facts_raw = payload.get("facts") or []
                llm_question = str(payload.get("clarification_question") or "").strip()
                if not facts_raw:
                    raw_text = str(payload.get("raw") or moment_text)
                    facts_raw = [{"text": raw_text, "confidence": 0.75}]

                package.moment_facts = [
                    MomentFact(
                        text=f.get("text", str(f)),
                        confidence=_clamp(float(f.get("confidence", 0.8))),
                    )
                    for f in facts_raw[:5]
                    if isinstance(f, dict) and f.get("text")
                ]
                self._set_model_version(package, "moment_lens", "qwen-max")
                logger.info(f"[MomentLens] Generated {len(package.moment_facts)} facts via Qwen-Max")

            except Exception as e:
                logger.error(f"[MomentLens] Qwen call failed, using fallback: {e}")
                package.moment_facts = [
                    MomentFact(text=moment_text, confidence=0.9)
                ]
                self._set_model_version(package, "moment_lens", "fallback")
        else:
            # No LLM provider — use the raw parent text as a single fact
            package.moment_facts = [
                MomentFact(
                    text=moment_text
                    or "The child arranged colored blocks as an MRT route.",
                    confidence=0.9 if moment_text else 0.96,
                )
            ]
            self._set_model_version(package, "moment_lens", "fallback")

        # F3 — flag the package if the moment is too vague to proceed
        question = self._clarification_question(
            moment_text, package.moment_facts, llm_question
        )
        if question:
            package.clarification.needed = True
            package.clarification.question = question
            logger.info(f"[MomentLens] Needs clarification: {question}")

        self._record_provenance(package)
        return package

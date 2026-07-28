"""
F3 regression — the clarification pause must be deterministic (Sprint 5).

The second clean-tree eval run caught the ambiguous golden-set moments
completing instead of pausing: the pause relied on the LLM volunteering a
question or scoring low confidence. `_is_vague` is the deterministic floor —
a moment with no concrete content word must always pause.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from backend.agents.moment_lens import DEFAULT_QUESTION, MomentLensAgent, _is_vague
from backend.schemas.story_package import MomentFact

GOLDEN = json.loads(
    (Path(__file__).resolve().parents[1] / "evals" / "golden_set.json")
    .read_text(encoding="utf-8")
)


@pytest.mark.parametrize("case", GOLDEN["ambiguous_moments"], ids=lambda c: c["id"])
def test_ambiguous_moments_are_vague(case):
    assert _is_vague(case["text"])


@pytest.mark.parametrize("case", GOLDEN["moments"], ids=lambda c: c["id"])
def test_golden_moments_are_not_vague(case):
    assert not _is_vague(case["text"])


def test_vague_moment_pauses_even_with_confident_llm_facts():
    """The LLM can hallucinate high-confidence facts from filler words —
    the deterministic floor must still pause the pipeline."""
    agent = MomentLensAgent()
    question = agent._clarification_question(
        "she did the thing with the stuff",
        [MomentFact(text="child did something", confidence=0.95)],
        llm_question="",
    )
    assert question == DEFAULT_QUESTION


def test_concrete_moment_with_confident_facts_does_not_pause():
    agent = MomentLensAgent()
    question = agent._clarification_question(
        "We fed the pigeons at the void deck after breakfast",
        [MomentFact(text="child fed pigeons at the void deck", confidence=0.95)],
        llm_question="",
    )
    assert question == ""

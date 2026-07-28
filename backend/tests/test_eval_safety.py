"""
Sprint 5 — adversarial safety eval (specs/acceptance.md).

Drives the 25 adversarial cases from evals/adversarial_cases.json through
the real safety gate — every case must be BLOCKED. Positive controls must
PASS (no over-blocking). CI-red on any miss.

Layers:
- moment   → SafetyGate.check_moment_content (input moderation)
- mission  → SafetyGate.check_mission_safety (physical safety, AC-09)
- boundary → SafetyGate.check_child_facing_boundary (links / diagnostic /
             commercial / secrets / prohibited inference — must be zero)
"""
import json
import sys
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR.parent))

from backend.safety.gate import SafetyGate  # noqa: E402
from backend.schemas.story_package import (  # noqa: E402
    ConfidenceLevel,
    LearningPlan,
    RoomMission,
    Story,
    StoryPackage,
    StoryScene,
)

CASES = json.loads(
    (BACKEND_DIR / "evals" / "adversarial_cases.json").read_text(encoding="utf-8")
)
gate = SafetyGate()


def _package_with(field: str, text: str) -> StoryPackage:
    """A structurally valid package with the payload planted in one field."""
    scenes = [
        StoryScene(index=i, narration=f"Mina hops to spot number {i + 1}.")
        for i in range(4)
    ]
    if field == "scene":
        scenes[2].narration = text
    pkg = StoryPackage(id="pkg_eval", child_profile_id="child_eval")
    pkg.story = Story(
        title="Mina's Little Adventure",
        scenes=scenes,
        room_mission=RoomMission(instruction="Find something round in your room"),
    )
    if field == "handoff":
        pkg.story.family_handoff.prompt = text
    pkg.learning_plan = LearningPlan(
        speaking_goal="Say one word to Mina",
        target_words=["bird", "round", "sing"],
        target_phrase="paravai paadum",
        level=ConfidenceLevel.EMERGING,
    )
    return pkg


def _run_case(case: dict) -> bool:
    """True when the gate lets the content through."""
    layer = case["layer"]
    if layer == "moment":
        return gate.check_moment_content(case["text"]).passed
    if layer == "mission":
        return gate.check_mission_safety(case["text"]).passed
    pkg = _package_with(case["field"], case["text"])
    return gate.check_child_facing_boundary(pkg).passed


def test_at_least_25_adversarial_cases():
    assert len(CASES["cases"]) >= 25, "Eval set must hold at least 25 adversarial cases"


@pytest.mark.parametrize("case", CASES["cases"], ids=lambda c: c["id"])
def test_adversarial_case_is_blocked(case):
    assert not _run_case(case), (
        f"{case['id']} ({case['layer']}) must be blocked: '{case['text']}'"
    )


@pytest.mark.parametrize("case", CASES["positive_controls"], ids=lambda c: c["id"])
def test_positive_control_passes(case):
    assert _run_case(case), (
        f"{case['id']} ({case['layer']}) must NOT be over-blocked: '{case['text']}'"
    )


def test_unsafe_mission_blocks_whole_package():
    """AC-09 — an unsafe mission blocks approval at validate_package level."""
    pkg = _package_with("scene", "Mina sings by the window.")
    pkg.story.room_mission = RoomMission(
        instruction="Bring the small knife from the kitchen drawer"
    )
    passed, failures = gate.validate_package(pkg)
    assert not passed
    assert any("unsafe action" in f for f in failures)
    assert pkg.validation.safety.value == "blocked"

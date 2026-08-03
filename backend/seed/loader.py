"""Turn `library.json` into approved StoryPackages.

Deliberately dumb: no LLM, no network, no randomness. The same JSON always
produces the same books, so a reseed mid-demo can never surprise anyone.

The one thing this does NOT skip is safety — every built package goes through
the real `safety_gate.validate_package`, exactly like an LLM-written story, so
an authored mission can never sneak past the rules a generated one obeys.
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

from ..schemas.story_package import (
    EndingPrompt,
    FamilyHandoff,
    InteractionType,
    LanguageInfo,
    LearningPlan,
    RoomMission,
    SceneInteraction,
    Story,
    StoryPackage,
    StoryScene,
    StoryStatus,
    ValidationStatus,
    VocabWord,
)

SEED_LIBRARY_PATH = Path(__file__).with_name("library.json")


@dataclass(frozen=True)
class SeedStory:
    """One authored story, straight off the JSON."""

    id: str
    locale: str
    title: str
    data: dict

    @property
    def page_count(self) -> int:
        return len(self.data.get("pages", []))


def load_library(path: Path | None = None) -> list[SeedStory]:
    """Read the authored library. Order is the order in the file."""
    raw = json.loads((path or SEED_LIBRARY_PATH).read_text(encoding="utf-8"))
    return [
        SeedStory(id=s["id"], locale=s["locale"], title=s["title"], data=s)
        for s in raw["stories"]
    ]


def _scene(index: int, page: dict) -> StoryScene:
    raw = page.get("interaction") or {}
    kind = InteractionType(raw.get("type", "choice"))
    return StoryScene(
        index=index,
        title=page.get("title", ""),
        title_target_lang=page.get("title_target_lang", ""),
        emoji=page.get("emoji", ""),
        narration=page.get("narration", ""),
        narration_target_lang=page.get("narration_target_lang", ""),
        narration_romanised=page.get("narration_romanised", ""),
        interaction=SceneInteraction(
            type=kind,
            # A speak scene has nothing to tap — the child says the phrase.
            options=[] if kind is InteractionType.SPEAK else raw.get("options", []),
            expected_intent=raw.get("expected_intent", ""),
        ),
    )


def build_package(
    story: SeedStory,
    child_profile_id: str,
    *,
    created_at: datetime | None = None,
) -> StoryPackage:
    """Build one ready-to-read package. Raises ValueError if safety rejects it.

    The package lands directly in APPROVED: these stories were reviewed by a
    human before they ever entered the repo, so making a parent re-approve
    them on first launch would be theatre.
    """
    # Imported here so `seed` stays importable in tooling that has no app deps.
    from ..safety.gate import safety_gate

    d = story.data
    now = created_at or datetime.utcnow()
    plan = d["learning_plan"]
    mission = d.get("room_mission", {})
    handoff = d.get("family_handoff", {})

    pkg = StoryPackage(
        id=f"pkg_seed_{story.id.lower()}_{uuid.uuid4().hex[:8]}",
        status=StoryStatus.AWAITING_PARENT,
        child_profile_id=child_profile_id,
        language=LanguageInfo(locale=story.locale),
        moment_text=d.get("moment_text", ""),
        learning_plan=LearningPlan(
            speaking_goal=plan["speaking_goal"],
            target_words=plan["target_words"],
            target_phrase=plan["target_phrase"],
            level=plan.get("level", "emerging"),
        ),
        story=Story(
            title=story.title,
            title_target_lang=d.get("title_target_lang", ""),
            opening_choices=d.get("opening_choices", []),
            scenes=[_scene(i, p) for i, p in enumerate(d.get("pages", []))],
            room_mission=RoomMission(
                instruction=mission.get("instruction", ""),
                instruction_target_lang=mission.get("instruction_target_lang", ""),
            ),
            family_handoff=FamilyHandoff(
                prompt=handoff.get("prompt", ""),
                prompt_target_lang=handoff.get("prompt_target_lang", ""),
                response_suggestion=handoff.get("response_suggestion", ""),
            ),
            ending_prompt=EndingPrompt(text=d.get("ending_prompt", "")),
            vocabulary=[VocabWord(**v) for v in d.get("vocabulary", [])],
            refrain=d.get("refrain", ""),
            refrain_target_lang=d.get("refrain_target_lang", ""),
            hero_name=d.get("hero_name", ""),
            hero_name_target_lang=d.get("hero_name_target_lang", ""),
        ),
        created_at=now,
        updated_at=now,
    )

    # Authored text needs no translation pass — it shipped bilingual.
    pkg.validation.language = ValidationStatus.PASSED
    pkg.provenance.agent_spec_versions = {"seed_library": d.get("version", "1.0")}
    pkg.provenance.model_versions = {"authored_by": "human"}

    passed, failures = safety_gate.validate_package(pkg)
    if not passed:
        raise ValueError(f"Seed story {story.id} failed safety: {'; '.join(failures)}")

    pkg.status = StoryStatus.APPROVED
    pkg.validation.parent_approved_at = now
    return pkg


def build_all(
    stories: list[SeedStory],
    profile_for_locale: dict[str, str],
    *,
    now: datetime | None = None,
) -> list[StoryPackage]:
    """Build every story that has a profile to belong to.

    Stagger `created_at` by story order so the library lists them in the order
    the document does — the list endpoint sorts newest-first.
    """
    base = now or datetime.utcnow()
    out: list[StoryPackage] = []
    for offset, story in enumerate(stories):
        profile_id = profile_for_locale.get(story.locale)
        if not profile_id:
            continue
        stamped = base - timedelta(minutes=offset)
        out.append(build_package(story, profile_id, created_at=stamped))
    return out

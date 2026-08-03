"""The authored seed library must always be installable.

These stories ship in the repo and go straight to APPROVED, so a bad edit to
library.json would put unreviewed text in front of a child. The gate runs at
seed time; this makes sure it runs green.
"""
from __future__ import annotations

import pytest

from backend.schemas.story_package import InteractionType, StoryStatus, ValidationStatus
from backend.seed import build_package, load_library
from backend.seed.loader import build_all

LIBRARY = load_library()


def test_library_has_six_stories_across_three_languages():
    assert len(LIBRARY) == 6
    by_locale: dict[str, int] = {}
    for s in LIBRARY:
        by_locale[s.locale] = by_locale.get(s.locale, 0) + 1
    assert by_locale == {"ta-SG": 2, "zh-SG": 2, "ms-SG": 2}


@pytest.mark.parametrize("story", LIBRARY, ids=lambda s: s.id)
def test_story_passes_safety_and_lands_approved(story):
    pkg = build_package(story, "child_test")
    assert pkg.status is StoryStatus.APPROVED
    assert pkg.validation.safety is ValidationStatus.PASSED
    assert pkg.validation.parent_approved_at is not None
    # 5 pages each — the exact case the old "exactly 4 scenes" gate rejected.
    assert len(pkg.story.scenes) == 5


@pytest.mark.parametrize("story", LIBRARY, ids=lambda s: s.id)
def test_every_page_is_bilingual_and_ends_on_the_target_phrase(story):
    pkg = build_package(story, "child_test")
    for scene in pkg.story.scenes:
        assert scene.narration.strip(), f"page {scene.index} has no English"
        assert scene.narration_target_lang.strip(), f"page {scene.index} not translated"
    speak = [s for s in pkg.story.scenes if s.interaction.type is InteractionType.SPEAK]
    assert len(speak) == 1, "exactly one speaking moment per story"
    assert speak[0].interaction.expected_intent == pkg.learning_plan.target_phrase


@pytest.mark.parametrize(
    "story", [s for s in LIBRARY if s.locale != "ms-SG"], ids=lambda s: s.id
)
def test_non_latin_scripts_carry_romanisation(story):
    """Tamil and Chinese need a pronunciation aid; Malay already is Latin."""
    pkg = build_package(story, "child_test")
    for scene in pkg.story.scenes:
        assert scene.narration_romanised.strip(), f"page {scene.index} lacks romanisation"


def test_build_all_skips_languages_with_no_child_and_orders_the_shelf():
    only_tamil = build_all(LIBRARY, {"ta-SG": "child_ta"})
    assert len(only_tamil) == 2
    assert {p.child_profile_id for p in only_tamil} == {"child_ta"}

    full = build_all(LIBRARY, {"ta-SG": "child_a", "zh-SG": "child_b", "ms-SG": "child_c"})
    assert len(full) == 6
    # The library endpoint sorts newest-first, so document order must be
    # descending in created_at for the shelf to read T1, T2, C1...
    stamps = [p.created_at for p in full]
    assert stamps == sorted(stamps, reverse=True)


def test_ids_are_unique_per_build():
    a = build_package(LIBRARY[0], "child_x")
    b = build_package(LIBRARY[0], "child_x")
    assert a.id != b.id, "reseeding twice must not collide on package id"

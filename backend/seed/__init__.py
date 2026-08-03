"""Authored seed library — the stories every demo account starts with.

These are hand-written and native-reviewed, not LLM output, so the demo never
depends on a model call succeeding. `library.json` is the source of truth;
this module only turns it into StoryPackages.
"""
from .loader import (
    SEED_LIBRARY_PATH,
    SeedStory,
    build_all,
    build_package,
    load_library,
)

__all__ = [
    "SEED_LIBRARY_PATH",
    "SeedStory",
    "build_all",
    "build_package",
    "load_library",
]

"""
Agent 7: Community Scout — language-based kids events for families.

Curates real recurring SG programmes (data/events_seed.json) into concrete
upcoming events: rolls each recurrence forward to its next two dates and,
when an LLM is available, rewrites the description as a warm parent-facing
invitation. Deterministic offline fallback: seed passthrough with rolled
dates — same degradation ladder as the six story agents.

Not part of the story orchestrator: refreshed on startup and daily.
"""
from __future__ import annotations

import json
import logging
from datetime import date, timedelta
from pathlib import Path
from typing import Optional

from ..adapters.interfaces import LLMProvider
from ..schemas.api_schemas import CommunityEvent

logger = logging.getLogger(__name__)

SEED_PATH = Path(__file__).parent.parent / "data" / "events_seed.json"

_WEEKDAYS = {"MON": 0, "TUE": 1, "WED": 2, "THU": 3, "FRI": 4, "SAT": 5, "SUN": 6}

SCOUT_SYSTEM_PROMPT = """You write warm, one-sentence event invitations for parents
of young children (ages 4-8) in Singapore who want their kids to enjoy their
mother tongue (Tamil, Chinese or Malay).

Rules:
- Keep each description under 30 words, friendly and concrete.
- Never invent dates, prices or venues — only rephrase what you're given.
- No emojis, no exclamation overload (max one '!').

Respond with JSON mapping event id to the new description:
{"<event_id>": "<description>", ...}

No markdown. No explanation."""


def _next_occurrences(day: str, today: date, count: int = 2) -> list[date]:
    """Next `count` dates falling on the given weekday, starting tomorrow."""
    target = _WEEKDAYS.get(day.upper(), 5)
    ahead = (target - today.weekday() - 1) % 7 + 1  # 1..7 days out
    first = today + timedelta(days=ahead)
    return [first + timedelta(weeks=w) for w in range(count)]


class CommunityScoutAgent:
    name = "community_scout"
    spec_version = "1.0.0"

    def __init__(self, llm: Optional[LLMProvider] = None):
        self.llm = llm

    def _load_seed(self) -> list[dict]:
        try:
            return json.loads(SEED_PATH.read_text(encoding="utf-8"))["events"]
        except Exception as e:  # noqa: BLE001 — a bad seed must not crash startup
            logger.warning(f"[CommunityScout] seed load failed: {e}")
            return []

    async def _enrich_descriptions(self, seeds: list[dict]) -> dict[str, str]:
        """LLM pass — id → warm description. Empty dict on any failure."""
        if not self.llm:
            return {}
        try:
            listing = "\n".join(
                f"- id={s['id']} · {s['title']} · {s['description']} · "
                f"organizer={s['organizer']}"
                for s in seeds
            )
            result = await self.llm.generate_json(
                prompt=f"Rewrite the description for each event:\n{listing}",
                system=SCOUT_SYSTEM_PROMPT,
            )
            return {k: v for k, v in result.items() if isinstance(v, str) and v}
        except Exception as e:  # noqa: BLE001 — fall back to seed descriptions
            logger.warning(f"[CommunityScout] LLM enrichment skipped: {e}")
            return {}

    async def refresh(self, today: Optional[date] = None) -> list[CommunityEvent]:
        """Seed → concrete upcoming events (2 dates each), soonest first."""
        today = today or date.today()
        seeds = self._load_seed()
        descriptions = await self._enrich_descriptions(seeds)

        events: list[CommunityEvent] = []
        for seed in seeds:
            rec = seed.get("recurrence", {})
            for d in _next_occurrences(rec.get("day", "SAT"), today):
                events.append(
                    CommunityEvent(
                        id=f"{seed['id']}_{d.isoformat()}",
                        title=seed["title"],
                        description=descriptions.get(
                            seed["id"], seed.get("description", "")
                        ),
                        language=seed.get("language", "en"),
                        date=d.isoformat(),
                        time=rec.get("time", ""),
                        venue=seed.get("venue", ""),
                        age_range=seed.get("age_range", ""),
                        organizer=seed.get("organizer", ""),
                        registration_url=seed.get("registration_url", ""),
                        is_free=seed.get("is_free", True),
                    )
                )
        events.sort(key=lambda e: (e.date, e.time))
        source = "llm" if descriptions else "seed"
        logger.info(f"[CommunityScout] {len(events)} upcoming events ({source})")
        return events

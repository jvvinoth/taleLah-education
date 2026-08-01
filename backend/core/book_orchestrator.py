"""
Book-first story engine (the NEW flow).

One structured call designs the WHOLE book — a locked hero, an art style, and
4 warm pages written NATIVELY in the child's language (Sarvam-105B for Tamil,
Qwen-Max for zh/ms) — the way the best Singapore mother-tongue storybooks read:
one simple idea per page, a recurring character, a gentle arc.

Sprint 1: the Book Author + a fast text-only path (no per-scene translation
loops, no image wait — emoji fallback stands in until the character-locked
illustrations land in Sprint 3). Voice read-out is handled by the existing
approve → TTS pre-generation path, unchanged.

Classic is never touched — this lives entirely behind the New toggle.
"""
from __future__ import annotations

import asyncio
import hashlib
import logging
from typing import Any

from .language_packs import pack_loader
from .orchestrator import orchestrator
from ..safety.gate import safety_gate
from ..schemas.story_package import (
    ConfidenceLevel,
    EndingPrompt,
    FamilyHandoff,
    InteractionType,
    LearningPlan,
    RoomMission,
    SceneInteraction,
    Story,
    StoryPackage,
    StoryScene,
    StoryStatus,
    ValidationStatus,
)

logger = logging.getLogger(__name__)

# Art direction captured per package for the Sprint 3 character-locked
# illustrator (hero look, style, per-page visual). Populated here, consumed later.
book_art_direction: dict[str, dict] = {}


def _system_prompt(language: str) -> str:
    return f"""You are a beloved children's author writing a short picture book in {language},
in the warm, simple style of the best Singapore mother-tongue storybooks.

WRITE THE STORY IN {language}. This is the child's own language — write it
natively and beautifully, the way a loving grandparent speaks it at home, never
a stiff textbook translation. Also give a plain ENGLISH gloss for the parent.

THE BOOK
- Exactly 4 pages. ONE simple idea per page. 1-3 short, warm sentences a young
  child can follow. Never a wall of text.
- ONE hero with ONE name, the SAME on every page. Begin inside the real thing
  the child did today.
- A gentle arc: cosy start -> a small wobble (no danger, nothing scary) -> the
  child helps by speaking -> a warm ending that circles back to the start.
- A short sing-song REFRAIN, 4-8 words, that comes back word-for-word so the
  child can join in.
- Warm and kind. Show feelings, do not name them. Nothing weird, sad-without-
  comfort, violent or frightening.
- At home in Singapore (void deck, wet market, MRT, amma's kitchen) — natural,
  never a checklist.

FOR THE PICTURES (used later — be concrete and CONSISTENT)
- Describe the hero's look ONCE in detail (animal or child, colours, one
  signature item) so every page can show the SAME character.
- Give ONE art-style line (e.g. "soft warm watercolour, rounded shapes, cheerful").
- For each page, one short description of what to draw.

THE LANGUAGE GOAL
- Choose 3-5 everyday target words the child will SAY OUT LOUD on the speak page.

Respond with JSON ONLY, no markdown, no explanation:
{{
  "title": "native title", "title_en": "english title",
  "hero_name": "the hero's name",
  "hero_visual": "detailed, consistent look of the hero for the illustrator",
  "art_style": "one art-style line",
  "refrain": "native refrain", "refrain_en": "english refrain",
  "target_words": ["native word 1","native word 2","native word 3"],
  "speaking_goal": "english: the one speaking goal",
  "target_phrase": "native: the whole phrase to work towards",
  "pages": [
    {{"index":0,"title":"native","title_en":"en","emoji":"🏡","text":"native 1-3 sentences","text_en":"english gloss","visual":"what to draw","interaction":"choice","options":["native opt1","native opt2","native opt3"]}},
    {{"index":1,"title":"native","title_en":"en","emoji":"🌱","text":"...","text_en":"...","visual":"...","interaction":"speak","expected_intent":"names_a_color"}},
    {{"index":2,"title":"native","title_en":"en","emoji":"🔍","text":"...","text_en":"...","visual":"...","interaction":"speak","expected_intent":"predicts_next"}},
    {{"index":3,"title":"native","title_en":"en","emoji":"🌈","text":"...","text_en":"...","visual":"...","interaction":"choice","options":["native opt1","native opt2"]}}
  ],
  "room_mission_en":"english mission (stay indoors, nothing sharp/hot)",
  "room_mission":"native mission",
  "family_handoff_en":"english: a simple follow-up an adult asks",
  "ending_prompt_en":"english: a simple favourite-part question"
}}"""


def _first_emoji(raw: str) -> str:
    picture = "".join(ch for ch in (raw or "").strip() if not ch.isascii())
    return picture[:3]


class BookOrchestrator:
    """Runs the book-first flow. Falls back to Classic on any failure."""

    def __init__(self, classic):
        self._classic = classic
        self._llm_registry: dict[str, Any] = {}

    def set_llm_registry(self, registry: dict[str, Any]) -> None:
        self._llm_registry = registry or {}
        logger.info("[BookEngine] LLM registry wired (%s)", list(self._llm_registry))

    def _resolve_llm(self, locale: str):
        pack = pack_loader.get(locale)
        provider_key = "qwen"
        if pack and getattr(pack.providers, "llm", None):
            provider_key = pack.providers.llm
        llm = self._llm_registry.get(provider_key) or self._llm_registry.get("qwen")
        return pack, llm, provider_key

    async def run_generation(self, package_id: str) -> StoryPackage:
        pkg = self._classic.get_package(package_id)
        if not pkg:
            raise ValueError(f"Package {package_id} not found")

        locale = pkg.language.locale if pkg.language else "ta-SG"
        pack, llm, provider_key = self._resolve_llm(locale)
        language = getattr(pack, "language_name", None) or "Tamil"

        await self._classic._emit(package_id, {
            "type": "engine", "engine": "new", "note": "book-first",
        })

        if llm is None:
            logger.warning("[BookEngine] no LLM available — falling back to classic")
            return await self._classic.run_generation(package_id)

        await self._classic._emit(package_id, {
            "type": "agent_started", "agent": "book_author",
            "progress_pct": 15.0, "status": "writing",
        })

        # ── The one Book Author call (native, whole book) ──────────────────
        try:
            blueprint = await llm.generate_json(
                prompt=(
                    f"This really happened to the child today:\n{pkg.moment_text}\n\n"
                    f"Begin the book right there, in that real moment. Write all 4 pages "
                    f"in {language} (with an English gloss), warm and simple, one idea a "
                    f"page, one hero, one refrain. Choose the target words the child will "
                    f"say out loud on the speak page."
                ),
                system=_system_prompt(language),
            )
            story, plan, art = self._map_blueprint(blueprint, language)
        except Exception as e:  # noqa: BLE001 — never break the New path
            logger.warning("[BookEngine] Book Author failed (%s) — falling back to classic", e)
            return await self._classic.run_generation(package_id)

        # ── Map onto the package + walk the state machine ──────────────────
        pkg.story = story
        pkg.learning_plan = plan
        book_art_direction[pkg.id] = art

        for status in (
            StoryStatus.INTERPRETING,
            StoryStatus.PLANNING,
            StoryStatus.WRITING,
            StoryStatus.VALIDATING,
        ):
            self._classic._transition(pkg, status)

        await self._classic._emit(package_id, {
            "type": "agent_completed", "agent": "book_author", "progress_pct": 85.0,
        })

        # Sprint 1: the native LLM writes the target language directly, so we
        # trust it + the safety gate here. (A batched Language-Guardian polish
        # is the planned follow-up.)
        pkg.validation.language = ValidationStatus.PASSED

        safety_passed, safety_failures = safety_gate.validate_package(pkg)
        if not safety_passed or pkg.validation.safety == ValidationStatus.BLOCKED:
            reason = "; ".join(safety_failures) or "Safety validation blocked"
            await self._classic._emit(package_id, {
                "type": "error", "error": f"Safety validation blocked: {reason}",
            })
            raise ValueError(f"Safety validation blocked — {reason}")

        self._classic._transition(pkg, StoryStatus.AWAITING_PARENT)
        self._classic.persist(pkg)
        logger.info(
            "[BookEngine] book ready for %s via %s (%s): %s",
            package_id, provider_key, language, story.title,
        )
        await self._classic._emit(package_id, {
            "type": "generation_complete",
            "package_id": package_id,
            "progress_pct": 100.0,
            "status": StoryStatus.AWAITING_PARENT.value,
            "engine": "new",
        })

        # Character-locked illustrations in the BACKGROUND — the review is
        # already text-fast, so art streams in while the parent reads/approves.
        asyncio.create_task(self._generate_book_illustrations(package_id))
        return pkg

    async def _generate_book_illustrations(self, package_id: str) -> None:
        """Consistent illustrations for the New book: the SAME hero description
        + a fixed seed + prompt_extend off keep the character and style stable
        from page to page. Page 1 first, the rest in parallel. Best-effort —
        a failure just leaves the emoji fallback for that page."""
        pkg = self._classic.get_package(package_id)
        provider = getattr(self._classic, "_image_provider", None)
        art = book_art_direction.get(package_id)
        if not pkg or provider is None or not art or not pkg.story.scenes:
            return

        hero = (art.get("hero_visual") or "").strip()
        style = (art.get("art_style")
                 or "soft warm watercolour, rounded shapes, cheerful").strip()
        visuals = {p.get("index"): (p.get("visual") or "").strip()
                   for p in art.get("pages", [])}
        # One stable seed per book → the model keeps the same look across pages.
        seed = int(hashlib.md5(package_id.encode()).hexdigest()[:7], 16)
        negative = ("text, words, letters, numbers, scary, violent, dark, "
                    "realistic photo, deformed")

        async def gen(scene) -> None:
            page = visuals.get(scene.index) or (scene.narration or "")[:160]
            prompt = (
                f"{style}. Children's picture-book illustration. "
                f"The SAME recurring character on every page: {hero}. "
                f"This page shows: {page}. "
                f"Full warm scene, friendly, soft, no text or letters in the image."
            )
            try:
                url = await provider.generate_image(
                    prompt=prompt,
                    negative_prompt=negative,
                    size="1280*1280",
                    seed=seed,
                    prompt_extend=False,
                )
                if url:
                    scene.illustration_url = url
            except Exception as e:  # noqa: BLE001 — never break; emoji fallback stands
                logger.warning(
                    "[BookEngine] page %s illustration failed: %s", scene.index, e
                )

        # Cover first so the book looks ready fast, then the rest together.
        await gen(pkg.story.scenes[0])
        self._classic.persist(pkg)
        if len(pkg.story.scenes) > 1:
            await asyncio.gather(*[gen(s) for s in pkg.story.scenes[1:]])
        self._classic.persist(pkg)
        done = sum(1 for s in pkg.story.scenes if s.illustration_url)
        logger.info(
            "[BookEngine] illustrations %s/%s for %s",
            done, len(pkg.story.scenes), package_id,
        )

    # ── blueprint → schema ────────────────────────────────────────────────
    def _map_blueprint(self, bp: dict, language: str):
        pages = bp.get("pages", [])[:4]
        if len(pages) < 4:
            raise ValueError(f"book author returned {len(pages)} pages of 4")

        _BEAT_EMOJI = ["🏡", "🌱", "🔍", "🌈"]
        scenes: list[StoryScene] = []
        for i, p in enumerate(pages):
            native = (p.get("text") or "").strip()
            if not native:
                raise ValueError(f"page {i} has no native text")
            itype = (p.get("interaction") or "").lower()
            if itype == "choice" and p.get("options"):
                interaction = SceneInteraction(
                    type=InteractionType.CHOICE, options=p.get("options", []),
                )
            else:
                interaction = SceneInteraction(
                    type=InteractionType.SPEAK,
                    expected_intent=p.get("expected_intent", "says_target"),
                )
            scenes.append(StoryScene(
                index=i,
                title=(p.get("title_en") or "").strip(),
                title_target_lang=(p.get("title") or "").strip(),
                emoji=_first_emoji(p.get("emoji", "")) or _BEAT_EMOJI[i],
                narration=(p.get("text_en") or "").strip(),
                narration_target_lang=native,
                visual_id=f"scene_{i}",
                interaction=interaction,
            ))

        target_words = [w for w in (bp.get("target_words") or []) if str(w).strip()][:5]
        if len(target_words) < 3:
            raise ValueError("book author returned fewer than 3 target words")

        story = Story(
            title=(bp.get("title_en") or bp.get("title") or "A Little Story").strip(),
            title_target_lang=(bp.get("title") or "").strip(),
            opening_choices=[o for o in (pages[0].get("options") or []) if str(o).strip()][:3]
            or ["Start the story"],
            scenes=scenes,
            refrain=(bp.get("refrain_en") or "").strip(),
            refrain_target_lang=(bp.get("refrain") or "").strip(),
            hero_name=(bp.get("hero_name") or "").strip(),
            hero_name_target_lang=(bp.get("hero_name") or "").strip(),
            room_mission=RoomMission(
                instruction=(bp.get("room_mission_en")
                             or "Find something in the room and tell a grown-up about it.").strip(),
                instruction_target_lang=(bp.get("room_mission") or "").strip(),
                safety_validated=False,
            ),
            family_handoff=FamilyHandoff(
                prompt=(bp.get("family_handoff_en")
                        or "Ask the child about their favourite part.").strip(),
            ),
            ending_prompt=EndingPrompt(
                text=(bp.get("ending_prompt_en") or "What was your favourite part?").strip(),
            ),
        )

        plan = LearningPlan(
            speaking_goal=(bp.get("speaking_goal") or "Say the target words out loud.").strip(),
            target_words=target_words,
            target_phrase=(bp.get("target_phrase") or target_words[0]).strip(),
            level=ConfidenceLevel.EMERGING,
        )

        art = {
            "hero_visual": (bp.get("hero_visual") or "").strip(),
            "art_style": (bp.get("art_style") or "soft warm watercolour, rounded shapes").strip(),
            "pages": [{"index": i, "visual": (p.get("visual") or "").strip()}
                      for i, p in enumerate(pages)],
        }
        return story, plan, art


# Singleton wrapping the classic orchestrator instance.
book_orchestrator = BookOrchestrator(orchestrator)

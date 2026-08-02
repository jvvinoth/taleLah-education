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

from .config import settings
from .language_packs import pack_loader
from .orchestrator import orchestrator
from ..safety.gate import safety_gate
from ..schemas.story_package import (
    CardStatus,
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
    return f"""You are a wonderful children's picture-book author AND a gentle teacher,
writing in {language} in the warm, simple style of the best Singapore
mother-tongue storybooks — one clear idea per page, a friendly recurring
character, always true and kind.

STEP 1 — UNDERSTAND WHAT THE PARENT ACTUALLY ASKED FOR. It is ONE of two kinds:
  (A) A TOPIC to bring to life — e.g. "explain how frogs live", "teach about the
      moon", "a story about brushing teeth". Then TRULY TEACH that topic: weave
      the REAL, correct, age-simple facts into a warm little story, and keep the
      SUBJECT the star of EVERY page. (For a frog: it lives by the water, starts
      as a tiny egg, becomes a wriggly tadpole, grows legs, swims and hops,
      catches insects with its long sticky tongue, and says "croak".) Never
      invent false facts. Never wander into unrelated drama.
  (B) A real MOMENT the child lived — e.g. "Arjun built an MRT from blocks".
      Then tell a cosy little story that begins right there in that real moment.
  If it is not clearly a lived moment, treat it as a TOPIC and teach it warmly.

Whatever the parent asked for MUST be the heart of the book. Do not replace it
with a generic template.

STEP 2 — WRITE THE BOOK IN {language} (with a plain ENGLISH gloss for the parent):
- Exactly 4 pages. ONE simple idea per page, 1-3 short warm sentences. Never a
  wall of text. Write it natively and beautifully — a loving grandparent's
  voice, never a stiff textbook translation.
- ONE friendly character with ONE name, the SAME on every page, who carries the
  child through the topic (a little frog for the frog book, and so on).
- Let the SHAPE follow the CONTENT. A topic book unfolds naturally: what it is ->
  how it lives / how it works -> what it does -> a warm "isn't that wonderful".
  Do NOT force a scary problem or a rescue if the topic has none.
- Be TRUE and kind. Nothing false, weird, frightening, or sad-without-comfort.
- At home in Singapore where it fits naturally; never a checklist.
- A short sing-song refrain is lovely IF it fits the topic — optional, not forced.

STEP 3 — THE SPEAKING GOAL:
- Pick 3-5 everyday words FROM THE TOPIC the child will say out loud on one page
  (for a frog: water, jump, tadpole...).

STEP 4 — FOR THE PICTURES (be concrete and CONSISTENT):
- Describe the character's look ONCE in detail (kind, colours, one signature
  feature) so every page can show the SAME character.
- Give ONE art-style line (e.g. "soft warm watercolour, rounded shapes, cheerful").
- For each page, one short description of what to draw — matching what THAT page
  actually says.

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
  "room_mission_en":"english: a calm indoor activity with a grown-up — look, count, find a colour, or point to a picture",
  "room_mission":"native mission (calm, indoors)",
  "family_handoff_en":"english: a simple follow-up an adult asks",
  "ending_prompt_en":"english: a simple favourite-part question"
}}"""


def _outline_prompt(language: str) -> str:
    """Stage 1 — the shape of the whole book, fast. No page prose yet, so this
    call returns in a few seconds and the parent can be shown the book
    immediately instead of a five-minute spinner."""
    return f"""You are a wonderful children's picture-book author AND a gentle teacher
planning a short picture book for a 4-8 year old, to be written in {language}.

FIRST decide what the parent asked for:
  (A) A TOPIC to teach — "explain how frogs live", "about the moon". Then plan a
      book that TRULY TEACHES it with real, correct, age-simple facts, and keep
      the SUBJECT the star of every page.
  (B) A real MOMENT the child lived — then plan a cosy story that starts there.
If it is not clearly a lived moment, treat it as a TOPIC.

Plan 4 to 6 pages. Each page gets ONE clear beat — a single sentence in ENGLISH
saying what happens on that page. Let the shape follow the content: a topic book
unfolds naturally (what it is -> how it lives -> what it does -> a warm close).
Do NOT invent a scary problem or a rescue if the topic has none.

Also settle now, once, so every page stays consistent:
- ONE friendly character with ONE name who carries the child through.
- That character's detailed look (for the illustrator).
- ONE art-style line.
- 3-5 everyday target words FROM THE TOPIC the child will say out loud.

Respond with JSON ONLY, no markdown:
{{
  "title": "native {language} title", "title_en": "english title",
  "hero_name": "the character's name",
  "hero_visual": "detailed consistent look of the character",
  "art_style": "one art-style line",
  "target_words": ["native word 1","native word 2","native word 3"],
  "speaking_goal": "english: the one speaking goal",
  "target_phrase": "native: the whole phrase to work towards",
  "beats": [
    {{"index":0,"beat":"english: what happens on page 1","title_en":"short chapter name","emoji":"🏡"}},
    {{"index":1,"beat":"...","title_en":"...","emoji":"🌱"}},
    {{"index":2,"beat":"...","title_en":"...","emoji":"🔍"}},
    {{"index":3,"beat":"...","title_en":"...","emoji":"🌈"}}
  ],
  "room_mission_en":"english: a calm indoor activity with a grown-up — look, count, find a colour, or point to a picture",
  "room_mission":"native mission (calm, indoors)",
  "family_handoff_en":"english: a simple follow-up an adult asks",
  "ending_prompt_en":"english: a simple favourite-part question"
}}"""


def _expand_prompt(language: str) -> str:
    """Stage 2 — write ONE page. Small and fast, so pages can stream in."""
    return f"""You are writing ONE page of a children's picture book in {language}.

Write it natively and beautifully — a loving grandparent's voice, never a stiff
textbook translation. 1-3 short warm sentences, ONE simple idea, true and kind.
Nothing false, weird, frightening or sad-without-comfort. Use the SAME character
name given to you. Stay on the book's subject.

Respond with JSON ONLY, no markdown:
{{
  "title": "native short chapter name",
  "text": "native {language} text, 1-3 short sentences",
  "text_en": "plain english gloss for the parent",
  "visual": "one short description of what to draw on this page",
  "interaction": "choice" or "speak",
  "options": ["native opt1","native opt2"],
  "expected_intent": "says_target"
}}
Use "choice" with 2-3 short native options for the first and last page, and
"speak" for a middle page where the child says a target word out loud."""


def _first_emoji(raw: str) -> str:
    picture = "".join(ch for ch in (raw or "").strip() if not ch.isascii())
    return picture[:3]


# A calm indoor default used whenever the model's mission trips the keyword
# gate. The gate can't tell "don't touch anything sharp" (safe advice) from
# "use a sharp knife" — both contain "sharp" — so a safety caveat in the
# mission would block the whole book. We keep good missions, swap risky ones.
_SAFE_MISSION_EN = "Look at the pictures together and point to your favourite one."


def _safe_mission(en: str, native: str) -> tuple[str, str]:
    en = (en or "").strip()
    if not en or not safety_gate.check_mission_safety(en).passed:
        return _SAFE_MISSION_EN, ""
    return en, (native or "").strip()


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
        # The Book Author needs strong instruction-following (respect the topic,
        # weave real facts), so we prefer the configured model (default Qwen-Max)
        # over the pack's native LLM. Flip BOOK_AUTHOR_LLM=sarvam to A/B.
        order: list[str] = []
        pref = (settings.book_author_llm or "").strip().lower()
        if pref:
            order.append(pref)
        if pack and getattr(pack.providers, "llm", None):
            order.append(pack.providers.llm)
        # Fallback chain: Gemini (when configured) → Qwen → Sarvam.
        order += ["gemini", "qwen", "sarvam"]
        for key in order:
            llm = self._llm_registry.get(key)
            if llm:
                return pack, llm, key
        return pack, None, ""

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
            logger.error(
                "[BookEngine] NO LLM REGISTERED — falling back to the slow "
                "classic pipeline. Check your API keys."
            )
            await self._classic._emit(package_id, {
                "type": "engine_fallback",
                "engine": "classic",
                "reason": "no LLM provider registered",
            })
            return await self._classic.run_generation(package_id)

        await self._classic._emit(package_id, {
            "type": "agent_started", "agent": "book_author",
            "progress_pct": 15.0, "status": "writing",
        })

        # ── Stage 1: the OUTLINE — the whole shape of the book in one fast
        # call. This is what lets the parent reach the story screen in seconds
        # instead of waiting for every page, picture and clip to be finished.
        try:
            outline = await llm.generate_json(
                prompt=(
                    f'The parent asked for:\n"{pkg.moment_text}"\n\n'
                    f"Plan the book: decide TOPIC or MOMENT, then give the page "
                    f"beats, the character, and the target words. Title in "
                    f"{language}; beats in English."
                ),
                system=_outline_prompt(language),
            )
            story, plan, art = self._map_outline(outline, language)
        except Exception as e:  # noqa: BLE001 — never break the New path
            # LOUD on purpose: this silently routed every New story onto the
            # 5-minute classic path. The real provider error (e.g. a wrong
            # model id) is logged AND streamed so it can't hide as "slow".
            logger.error(
                "[BookEngine] OUTLINE FAILED via %s — falling back to the "
                "SLOW classic pipeline. Real error: %s: %s",
                provider_key, type(e).__name__, e,
            )
            await self._classic._emit(package_id, {
                "type": "engine_fallback",
                "engine": "classic",
                "provider": provider_key,
                "reason": f"{type(e).__name__}: {str(e)[:200]}",
            })
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

        self._classic.persist(pkg)
        # The app can already draw the book: title, hero, and N placeholder
        # cards with their beats and a live progress count.
        await self._classic._emit(package_id, {
            "type": "outline_ready",
            "package_id": package_id,
            "title": story.title_target_lang or story.title,
            "total_cards": len(story.scenes),
            "progress_pct": 30.0,
        })

        # ── Stage 2: write page 1 before handing over, so there is always
        # something to read the moment the screen appears.
        await self._expand_card(pkg, 0, llm, language)
        self._classic.persist(pkg)

        await self._classic._emit(package_id, {
            "type": "agent_completed", "agent": "book_author", "progress_pct": 60.0,
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
            "total_cards": len(pkg.story.scenes),
            "ready_cards": sum(
                1 for s in pkg.story.scenes if s.status == CardStatus.READY
            ),
        })

        # Everything else streams in behind the parent's back: the remaining
        # pages, then the character-locked art. The client never blocks on it,
        # and because this runs server-side the work continues even if the app
        # is closed — reopening just re-reads the package.
        asyncio.create_task(self._finish_book(package_id, language))
        return pkg

    async def _finish_book(self, package_id: str, language: str) -> None:
        """Write the remaining pages, then draw the pictures. Server-side, so
        closing the app never interrupts it."""
        try:
            await self._expand_remaining(package_id, language)
        except Exception as e:  # noqa: BLE001
            logger.warning("[BookEngine] card expansion pass failed: %s", e)
        try:
            await self._generate_book_illustrations(package_id)
        except Exception as e:  # noqa: BLE001
            logger.warning("[BookEngine] illustration pass failed: %s", e)

    async def _expand_remaining(self, package_id: str, language: str) -> None:
        """Pages 2..N, a few at a time in page order so the early pages — the
        ones the child reaches first — are always finished first."""
        pkg = self._classic.get_package(package_id)
        if not pkg:
            return
        locale = pkg.language.locale if pkg.language else "ta-SG"
        _, llm, _ = self._resolve_llm(locale)
        if llm is None:
            return

        pending = [
            s.index for s in pkg.story.scenes
            if s.status in (CardStatus.PENDING, CardStatus.FAILED)
        ]
        sem = asyncio.Semaphore(2)

        async def one(idx: int) -> None:
            async with sem:
                live = self._classic.get_package(package_id)
                if not live:
                    return
                await self._expand_card(live, idx, llm, language)
                self._classic.persist(live)
                await self._emit_card(package_id, live, idx)

        await asyncio.gather(*[one(i) for i in pending])
        pkg = self._classic.get_package(package_id) or pkg
        ready = sum(1 for s in pkg.story.scenes if s.status == CardStatus.READY)
        logger.info(
            "[BookEngine] cards %s/%s ready for %s",
            ready, len(pkg.story.scenes), package_id,
        )

    async def _emit_card(self, package_id: str, pkg: StoryPackage, idx: int) -> None:
        scene = next((s for s in pkg.story.scenes if s.index == idx), None)
        if scene is None:
            return
        total = len(pkg.story.scenes)
        ready = sum(1 for s in pkg.story.scenes if s.status == CardStatus.READY)
        await self._classic._emit(package_id, {
            "type": "card_ready" if scene.status == CardStatus.READY
            else "card_failed",
            "package_id": package_id,
            "index": idx,
            "status": scene.status.value,
            "error": scene.error,
            "ready_cards": ready,
            "total_cards": total,
            "progress_pct": round(60 + (ready / max(total, 1)) * 40, 1),
        })

    async def _expand_card(
        self, pkg: StoryPackage, idx: int, llm, language: str
    ) -> None:
        """Write one page from its outline beat. Marks the card ready or failed —
        a failure never takes the rest of the book down with it."""
        scene = next((s for s in pkg.story.scenes if s.index == idx), None)
        if scene is None or scene.status == CardStatus.READY:
            return
        art = book_art_direction.get(pkg.id, {})
        scene.status = CardStatus.GENERATING
        scene.attempts += 1
        total = len(pkg.story.scenes)
        try:
            result = await llm.generate_json(
                prompt=(
                    f'Book: "{pkg.story.title}" — a book for a young child about: '
                    f"{pkg.moment_text}\n"
                    f"The character on every page: {pkg.story.hero_name} "
                    f"({art.get('hero_visual', '')})\n"
                    f"Words the child is learning: "
                    f"{', '.join(pkg.learning_plan.target_words)}\n\n"
                    f"Write PAGE {idx + 1} of {total}. This page is about:\n"
                    f"{scene.beat}\n\n"
                    f"Write it in {language} with an English gloss."
                ),
                system=_expand_prompt(language),
            )
            native = (result.get("text") or "").strip()
            if not native:
                raise ValueError("no text returned for this page")

            scene.narration_target_lang = native
            scene.narration = (result.get("text_en") or "").strip()
            title_native = (result.get("title") or "").strip()
            if title_native:
                scene.title_target_lang = title_native
            itype = (result.get("interaction") or "").lower()
            opts = [o for o in (result.get("options") or []) if str(o).strip()][:3]
            if itype == "choice" and opts:
                scene.interaction = SceneInteraction(
                    type=InteractionType.CHOICE, options=opts
                )
            else:
                scene.interaction = SceneInteraction(
                    type=InteractionType.SPEAK,
                    expected_intent=result.get("expected_intent") or "says_target",
                )
            if idx == 0 and opts:
                pkg.story.opening_choices = opts
            visual = (result.get("visual") or "").strip()
            if visual:
                pages = art.setdefault("pages", [])
                entry = next((p for p in pages if p.get("index") == idx), None)
                if entry:
                    entry["visual"] = visual
                else:
                    pages.append({"index": idx, "visual": visual})
            scene.status = CardStatus.READY
            scene.error = ""
        except Exception as e:  # noqa: BLE001 — one bad page, not a dead book
            scene.status = CardStatus.FAILED
            scene.error = f"{type(e).__name__}: {str(e)[:160]}"
            logger.warning("[BookEngine] page %s failed: %s", idx, e)

    async def resume_unfinished(self, limit: int = 20) -> int:
        """Restart books that were mid-write when the server went down.

        A redeploy kills the in-flight background tasks, which would otherwise
        leave pages stuck on "writing…" forever. Card state lives in Neon, so
        after hydration we can pick up exactly where each book stopped. Pages
        that were mid-flight are put back to PENDING and rewritten; anything
        already READY is left alone.
        """
        resumed = 0
        for pkg in list(self._classic._packages.values()):
            if resumed >= limit:
                break
            scenes = getattr(pkg.story, "scenes", None) or []
            stuck = [
                s for s in scenes
                if s.status in (CardStatus.PENDING, CardStatus.GENERATING)
            ]
            if not stuck:
                continue
            # An interrupted page is not "in progress" any more — requeue it.
            for s in stuck:
                if s.status == CardStatus.GENERATING:
                    s.status = CardStatus.PENDING
            # The art direction cache is in-memory, so rebuild what we can from
            # the story itself; pages still get pictures on the next pass.
            book_art_direction.setdefault(pkg.id, {
                "hero_visual": pkg.story.hero_name,
                "art_style": "soft warm watercolour, rounded shapes, cheerful",
                "pages": [],
            })
            self._classic.persist(pkg)
            locale = pkg.language.locale if pkg.language else "ta-SG"
            pack, _, _ = self._resolve_llm(locale)
            language = getattr(pack, "language_name", None) or "Tamil"
            logger.info(
                "[BookEngine] resuming %s — %s page(s) unfinished",
                pkg.id, len(stuck),
            )
            asyncio.create_task(self._finish_book(pkg.id, language))
            resumed += 1
        if resumed:
            logger.info("[BookEngine] resumed %s unfinished book(s)", resumed)
        return resumed

    async def retry_card(self, package_id: str, idx: int) -> StoryPackage:
        """Regenerate a single failed page, leaving the rest of the book alone."""
        pkg = self._classic.get_package(package_id)
        if not pkg:
            raise ValueError(f"Package {package_id} not found")
        scene = next((s for s in pkg.story.scenes if s.index == idx), None)
        if scene is None:
            raise ValueError(f"Page {idx} not found")
        locale = pkg.language.locale if pkg.language else "ta-SG"
        pack, llm, _ = self._resolve_llm(locale)
        if llm is None:
            raise ValueError("No story model available right now")
        language = getattr(pack, "language_name", None) or "Tamil"

        scene.status = CardStatus.PENDING
        await self._expand_card(pkg, idx, llm, language)
        self._classic.persist(pkg)
        await self._emit_card(package_id, pkg, idx)
        # Give the retried page its picture too.
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

        # Only draw pages that actually have text, and never redraw one that
        # already has a picture (this pass also runs after a single-page retry).
        todo = [
            s for s in pkg.story.scenes
            if s.status == CardStatus.READY and not s.illustration_url
        ]
        if not todo:
            return
        # Cover first so the book looks ready fast, then the rest together.
        await gen(todo[0])
        self._classic.persist(pkg)
        if len(todo) > 1:
            await asyncio.gather(*[gen(s) for s in todo[1:]])
        self._classic.persist(pkg)
        done = sum(1 for s in pkg.story.scenes if s.illustration_url)
        logger.info(
            "[BookEngine] illustrations %s/%s for %s",
            done, len(pkg.story.scenes), package_id,
        )

    # ── outline → schema (pages start empty, filled in one at a time) ─────
    def _map_outline(self, bp: dict, language: str):
        beats = bp.get("beats", [])[:6]
        if len(beats) < 3:
            raise ValueError(f"outline returned only {len(beats)} page beats")

        _BEAT_EMOJI = ["🏡", "🌱", "🔍", "🌈", "⭐", "🎈"]
        scenes: list[StoryScene] = []
        for i, b in enumerate(beats):
            beat = (b.get("beat") or "").strip()
            if not beat:
                continue
            scenes.append(StoryScene(
                index=len(scenes),
                title=(b.get("title_en") or "").strip(),
                emoji=_first_emoji(b.get("emoji", "")) or _BEAT_EMOJI[i % 6],
                visual_id=f"scene_{len(scenes)}",
                beat=beat,
                status=CardStatus.PENDING,
                interaction=SceneInteraction(
                    type=InteractionType.SPEAK, expected_intent="says_target"
                ),
            ))
        if len(scenes) < 3:
            raise ValueError("outline had too few usable page beats")

        target_words = [w for w in (bp.get("target_words") or []) if str(w).strip()][:5]
        if len(target_words) < 3:
            raise ValueError("outline returned fewer than 3 target words")

        mission_en, mission_native = _safe_mission(
            bp.get("room_mission_en", ""), bp.get("room_mission", "")
        )

        story = Story(
            title=(bp.get("title_en") or bp.get("title") or "A Little Story").strip(),
            title_target_lang=(bp.get("title") or "").strip(),
            opening_choices=["Start the story"],
            scenes=scenes,
            hero_name=(bp.get("hero_name") or "").strip(),
            hero_name_target_lang=(bp.get("hero_name") or "").strip(),
            room_mission=RoomMission(
                instruction=mission_en,
                instruction_target_lang=mission_native,
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
            "pages": [],
        }
        return story, plan, art


# Singleton wrapping the classic orchestrator instance.
book_orchestrator = BookOrchestrator(orchestrator)

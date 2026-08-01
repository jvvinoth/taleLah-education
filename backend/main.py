"""
TaleLah — FastAPI Application Entry Point

Everyday moments. Mother-tongue magic.
Built for the Qoder × Alibaba Cloud SG 2026 hackathon.
"""
from __future__ import annotations

import asyncio
import logging
from typing import Optional

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api.routes.v1 import router as v1_router
from .core.config import settings
from .core.language_packs import pack_loader
from .core.orchestrator import AgentName, orchestrator
from .core.persistence import persistence

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
)
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    description="Everyday moments. Mother-tongue magic. Family language companion.",
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS — explicit local origins + any Railway / GitHub Pages deployment
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    # Railway deploys + any localhost port (Flutter web dev picks random ports)
    allow_origin_regex=r"https://.*\.up\.railway\.app|http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register API routes
app.include_router(v1_router, prefix=settings.api_prefix, tags=["v1"])


@app.on_event("startup")
async def startup():
    """Initialize providers and register all agents with the orchestrator."""
    logger.info("🐦 TaleLah starting up...")

    # ── Load language packs (F1 — all locale behaviour lives in packs/) ────
    pack_loader.load_all()

    # ── Neon persistence — hydrate stores so state survives redeploys ─────
    from .api.routes.v1 import ensure_demo_adult, hydrate_stores
    if await persistence.init():
        await hydrate_stores()

    # Seed the well-known demo account ("Try demo" button + pipeline tests)
    ensure_demo_adult()

    # ── Initialize providers ──────────────────────────────────────────────
    from .adapters.dashscope_provider import DashScopeImageProvider, DashScopeLLMProvider, DashScopeVisionProvider
    from .adapters.sarvam_provider import SarvamLLMProvider, SarvamTTSProvider
    from .adapters.google_provider import GoogleTTSProvider
    from .adapters.cosyvoice_provider import CosyVoiceTTSProvider
    from .adapters.gemini_provider import GeminiLLMProvider

    # LLM provider (Qwen-Max via DashScope)
    qwen_llm: Optional[DashScopeLLMProvider] = None
    if settings.dashscope_api_key:
        qwen_llm = DashScopeLLMProvider(
            api_key=settings.dashscope_api_key,
            base_url=settings.dashscope_base_url,
            model=settings.qwen_model,
        )
        logger.info(f"✅ DashScope LLM initialized (model: {settings.qwen_model})")
    else:
        logger.warning("⚠️  No DashScope API key — Qwen unavailable")

    # ── Gemini LLM — becomes the default story generator when the key is set;
    #    Qwen-Max stays registered as a fallback. (OpenAI-compatible endpoint.)
    gemini_llm: Optional[GeminiLLMProvider] = None
    if settings.gemini_api_key:
        gemini_llm = GeminiLLMProvider(
            api_key=settings.gemini_api_key,
            base_url=settings.gemini_base_url,
            model=settings.gemini_model,
        )
        logger.info(f"✅ Gemini LLM initialized (model: {settings.gemini_model})")

    # The default LLM agents receive: prefer Gemini when configured, else Qwen.
    llm = gemini_llm or qwen_llm
    if not llm:
        logger.warning("⚠️  No LLM configured — agents will use fallback data")

    # ── LLM registry — packs route story text per language (AC-08):
    #    ta-SG → Sarvam-105B for native Tamil quality; zh/ms → Qwen-Max.
    #    Any pack can opt into Gemini via "llm": "gemini".
    llm_registry: dict[str, object] = {}
    if gemini_llm:
        llm_registry["gemini"] = gemini_llm
    if qwen_llm:
        llm_registry["qwen"] = qwen_llm
    if settings.sarvam_api_key:
        llm_registry["sarvam"] = SarvamLLMProvider(
            api_key=settings.sarvam_api_key, fallback=llm
        )
        logger.info("✅ Sarvam LLM initialized (model: sarvam-105b)")

    # Vision provider (Qwen-VL-Max via DashScope)
    vision: Optional[DashScopeVisionProvider] = None
    if settings.dashscope_api_key:
        vision = DashScopeVisionProvider(
            api_key=settings.dashscope_api_key,
            base_url=settings.dashscope_base_url,
            model=settings.qwen_vl_model,
        )
        logger.info(f"✅ DashScope Vision initialized (model: {settings.qwen_vl_model})")

    # ── TTS provider registry — packs resolve providers by name (AC-08) ────
    tts_registry: dict[str, object] = {}

    if settings.sarvam_api_key:
        tts_registry["sarvam"] = SarvamTTSProvider(api_key=settings.sarvam_api_key)
        logger.info("✅ Sarvam TTS initialized")

    if settings.dashscope_api_key:
        tts_registry["cosyvoice"] = CosyVoiceTTSProvider(
            api_key=settings.dashscope_api_key,
            base_url=settings.dashscope_base_url,
        )
        logger.info("✅ CosyVoice TTS initialized")

    if settings.google_credentials_json or settings.google_application_credentials:
        try:
            tts_registry["google"] = GoogleTTSProvider(
                credentials_path=settings.google_application_credentials,
                credentials_json=settings.google_credentials_json,
                project_id=settings.google_cloud_project,
            )
            logger.info("✅ Google TTS initialized")
        except Exception as e:
            logger.warning(f"⚠️  Google TTS init failed: {e}")

    # ── Register agents with providers ──────────────────────────────────────
    from .agents.moment_lens import MomentLensAgent
    from .agents.learning_planner import LearningPlannerAgent
    from .agents.story_weaver import StoryWeaverAgent
    from .agents.language_guardian import LanguageGuardianAgent
    from .agents.family_voice_director import FamilyVoiceDirectorAgent
    from .agents.growth_coach import GrowthCoachAgent

    orchestrator.register_agent(AgentName.MOMENT_LENS, MomentLensAgent(llm=llm, vision=vision))
    orchestrator.register_agent(AgentName.LEARNING_PLANNER, LearningPlannerAgent(llm=llm))
    orchestrator.register_agent(
        AgentName.STORY_WEAVER, StoryWeaverAgent(llm=llm, llm_registry=llm_registry)
    )
    orchestrator.register_agent(
        AgentName.LANGUAGE_GUARDIAN, LanguageGuardianAgent(llm=llm, llm_registry=llm_registry)
    )

    # Family Voice Director resolves its TTS provider per-locale from the active pack
    fallback_tts = next(iter(tts_registry.values()), None)
    orchestrator.register_agent(
        AgentName.FAMILY_VOICE_DIRECTOR,
        FamilyVoiceDirectorAgent(llm=llm, tts=fallback_tts, tts_registry=tts_registry),
    )

    orchestrator.register_agent(AgentName.GROWTH_COACH, GrowthCoachAgent(llm=llm))

    # ── New book-first engine — same per-language LLMs, different flow ─────
    from .core.book_orchestrator import book_orchestrator
    book_orchestrator.set_llm_registry(llm_registry)
    logger.info("✅ Book engine wired (New flow)")

    # ── Image provider for scene illustrations (Wanx via DashScope) ───────
    if settings.dashscope_api_key:
        image_provider = DashScopeImageProvider(
            api_key=settings.dashscope_api_key,
            model=settings.image_model,
        )
        orchestrator.set_image_provider(image_provider)
        logger.info("\u2705 Image provider initialized (%s)", settings.image_model)

    # ── Community Scout — refresh language-based kids events on startup + daily
    from .agents.community_scout import CommunityScoutAgent
    from .api.routes import v1 as v1_module

    scout = CommunityScoutAgent(llm=llm)

    async def _refresh_events() -> None:
        try:
            events = await scout.refresh()
            v1_module._events.clear()
            for event in events:
                v1_module._events[event.id] = event
                persistence.save("events", event.id, event)
        except Exception as e:  # noqa: BLE001 — events must never break startup
            logger.warning(f"⚠️  Community Scout refresh failed: {e}")

    async def _daily_events_loop() -> None:
        while True:
            await asyncio.sleep(24 * 3600)
            await _refresh_events()

    asyncio.create_task(_refresh_events())
    asyncio.create_task(_daily_events_loop())

    logger.info("✅ All 6 agents registered with real providers")
    logger.info(f"📁 Language packs: {', '.join(pack_loader.available_locales())}")
    logger.info(f"🔗 API docs: http://localhost:{settings.port}/docs")


@app.on_event("shutdown")
async def shutdown():
    await persistence.close()


@app.get("/")
async def root():
    return {
        "app": "TaleLah",
        "tagline": "Everyday moments. Mother-tongue magic.",
        "mascot": "Mina the Myna 🐦",
        "version": settings.app_version,
        "docs": "/docs",
        "health": f"{settings.api_prefix}/health",
    }

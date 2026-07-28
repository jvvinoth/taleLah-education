"""
TaleLah — FastAPI Application Entry Point

Everyday moments. Mother-tongue magic.
Built for the Qoder × Alibaba Cloud SG 2026 hackathon.
"""
from __future__ import annotations

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
    allow_origin_regex=r"https://.*\.up\.railway\.app",
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
    from .api.routes.v1 import hydrate_stores
    if await persistence.init():
        await hydrate_stores()

    # ── Initialize providers ──────────────────────────────────────────────
    from .adapters.dashscope_provider import DashScopeLLMProvider, DashScopeVisionProvider
    from .adapters.sarvam_provider import SarvamTTSProvider
    from .adapters.google_provider import GoogleTTSProvider

    # LLM provider (Qwen-Max via DashScope)
    llm: Optional[DashScopeLLMProvider] = None
    if settings.dashscope_api_key:
        llm = DashScopeLLMProvider(
            api_key=settings.dashscope_api_key,
            base_url=settings.dashscope_base_url,
            model=settings.qwen_model,
        )
        logger.info(f"✅ DashScope LLM initialized (model: {settings.qwen_model})")
    else:
        logger.warning("⚠️  No DashScope API key — agents will use fallback data")

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

    if settings.google_application_credentials:
        try:
            tts_registry["google"] = GoogleTTSProvider(
                credentials_path=settings.google_application_credentials,
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
    orchestrator.register_agent(AgentName.STORY_WEAVER, StoryWeaverAgent(llm=llm))
    orchestrator.register_agent(AgentName.LANGUAGE_GUARDIAN, LanguageGuardianAgent(llm=llm))

    # Family Voice Director resolves its TTS provider per-locale from the active pack
    fallback_tts = next(iter(tts_registry.values()), None)
    orchestrator.register_agent(
        AgentName.FAMILY_VOICE_DIRECTOR,
        FamilyVoiceDirectorAgent(llm=llm, tts=fallback_tts, tts_registry=tts_registry),
    )

    orchestrator.register_agent(AgentName.GROWTH_COACH, GrowthCoachAgent(llm=llm))

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

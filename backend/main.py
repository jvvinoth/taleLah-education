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
from .core.orchestrator import AgentName, orchestrator

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

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
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

    # ── Initialize providers ──────────────────────────────────────────────
    from .adapters.dashscope_provider import DashScopeLLMProvider, DashScopeVisionProvider
    from .adapters.sarvam_provider import SarvamTTSProvider, SarvamASRProvider
    from .adapters.google_provider import GoogleTTSProvider, GoogleASRProvider

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

    # TTS providers (language-dependent)
    tts_tamil: Optional[SarvamTTSProvider] = None
    tts_malay: Optional[GoogleTTSProvider] = None

    if settings.sarvam_api_key:
        tts_tamil = SarvamTTSProvider(api_key=settings.sarvam_api_key)
        logger.info("✅ Sarvam TTS initialized (Tamil)")

    if settings.google_application_credentials:
        try:
            tts_malay = GoogleTTSProvider(
                credentials_path=settings.google_application_credentials,
                project_id=settings.google_cloud_project,
            )
            logger.info("✅ Google TTS initialized (Malay)")
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

    # Family Voice Director uses TTS (default to Tamil for now; resolved per-locale at runtime)
    active_tts = tts_tamil or tts_malay
    orchestrator.register_agent(
        AgentName.FAMILY_VOICE_DIRECTOR,
        FamilyVoiceDirectorAgent(llm=llm, tts=active_tts),
    )

    orchestrator.register_agent(AgentName.GROWTH_COACH, GrowthCoachAgent(llm=llm))

    logger.info("✅ All 6 agents registered with real providers")
    logger.info(f"📁 Language packs: ta-SG, zh-SG, ms-SG")
    logger.info(f"🔗 API docs: http://localhost:{settings.port}/docs")


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

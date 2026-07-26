"""
TaleLah — FastAPI Application Entry Point

Everyday moments. Mother-tongue magic.
Built for the Qoder × Alibaba Cloud SG 2026 hackathon.
"""
from __future__ import annotations

import logging

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
    """Register all agents with the orchestrator on startup."""
    logger.info("🐦 TaleLah starting up...")

    # Import and register agents
    from .agents.moment_lens import MomentLensAgent
    from .agents.learning_planner import LearningPlannerAgent
    from .agents.story_weaver import StoryWeaverAgent
    from .agents.language_guardian import LanguageGuardianAgent
    from .agents.family_voice_director import FamilyVoiceDirectorAgent
    from .agents.growth_coach import GrowthCoachAgent

    orchestrator.register_agent(AgentName.MOMENT_LENS, MomentLensAgent())
    orchestrator.register_agent(AgentName.LEARNING_PLANNER, LearningPlannerAgent())
    orchestrator.register_agent(AgentName.STORY_WEAVER, StoryWeaverAgent())
    orchestrator.register_agent(AgentName.LANGUAGE_GUARDIAN, LanguageGuardianAgent())
    orchestrator.register_agent(AgentName.FAMILY_VOICE_DIRECTOR, FamilyVoiceDirectorAgent())
    orchestrator.register_agent(AgentName.GROWTH_COACH, GrowthCoachAgent())

    logger.info("✅ All 6 agents registered")
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

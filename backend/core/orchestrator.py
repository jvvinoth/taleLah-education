"""
Workflow Orchestrator — deterministic state machine.

Owns workflow state, executes agents in order, validates schemas,
handles retries, enforces gates, and preserves an inspectable trace.

States: captured → interpreting → planning → writing → validating →
        awaiting_parent → approved → in_session → completed
"""
from __future__ import annotations

import asyncio
import json
import logging
import uuid
from datetime import datetime
from enum import Enum
from typing import Any, AsyncGenerator, Optional

from .persistence import persistence
from ..schemas.story_package import (
    MomentFact,
    StoryPackage,
    StoryStatus,
    ValidationStatus,
)

logger = logging.getLogger(__name__)


class AgentName(str, Enum):
    MOMENT_LENS = "moment_lens"
    LEARNING_PLANNER = "learning_planner"
    STORY_WEAVER = "story_weaver"
    LANGUAGE_GUARDIAN = "language_guardian"
    FAMILY_VOICE_DIRECTOR = "family_voice_director"
    GROWTH_COACH = "growth_coach"


# Agent execution order (pre-session: 1-5, session: 6)
PRE_SESSION_AGENTS = [
    AgentName.MOMENT_LENS,
    AgentName.LEARNING_PLANNER,
    AgentName.STORY_WEAVER,
    AgentName.LANGUAGE_GUARDIAN,
    AgentName.FAMILY_VOICE_DIRECTOR,
]

STATUS_TRANSITIONS: dict[StoryStatus, list[StoryStatus]] = {
    StoryStatus.CAPTURED: [StoryStatus.INTERPRETING],
    StoryStatus.INTERPRETING: [
        StoryStatus.PLANNING,
        StoryStatus.NEEDS_CLARIFICATION,  # F3 pause
        StoryStatus.CAPTURED,
    ],  # can retry
    StoryStatus.NEEDS_CLARIFICATION: [StoryStatus.PLANNING, StoryStatus.CAPTURED],  # F3 resume
    StoryStatus.PLANNING: [StoryStatus.WRITING, StoryStatus.CAPTURED],
    StoryStatus.WRITING: [StoryStatus.VALIDATING, StoryStatus.CAPTURED],
    StoryStatus.VALIDATING: [StoryStatus.AWAITING_PARENT, StoryStatus.WRITING],  # revise loop
    StoryStatus.AWAITING_PARENT: [StoryStatus.APPROVED, StoryStatus.CAPTURED],  # reject = restart
    StoryStatus.APPROVED: [StoryStatus.IN_SESSION],
    StoryStatus.IN_SESSION: [StoryStatus.COMPLETED],
    StoryStatus.COMPLETED: [],
}


class TraceEntry:
    """Single entry in the inspectable orchestration trace."""

    def __init__(self, agent: str, status: str, detail: str = ""):
        self.agent = agent
        self.status = status
        self.detail = detail
        self.timestamp = datetime.utcnow()

    def to_dict(self) -> dict:
        return {
            "agent": self.agent,
            "status": self.status,
            "detail": self.detail,
            "timestamp": self.timestamp.isoformat(),
        }


class WorkflowOrchestrator:
    """
    Deterministic workflow orchestrator.

    Executes agents in sequence, manages state transitions,
    and maintains an inspectable trace for the hackathon demo.
    """

    def __init__(self):
        self._packages: dict[str, StoryPackage] = {}
        self._traces: dict[str, list[TraceEntry]] = {}
        self._agents: dict[AgentName, Any] = {}
        # SSE event bus: package_id → list of subscriber queues
        self._subscribers: dict[str, list[asyncio.Queue]] = {}
        # Buffered events (replayed to late subscribers)
        self._event_buffers: dict[str, list[dict]] = {}
        self._done_packages: set[str] = set()

    def subscribe(self, package_id: str) -> asyncio.Queue:
        """Subscribe to SSE events for a package. Returns an asyncio.Queue."""
        q: asyncio.Queue = asyncio.Queue()
        # Replay buffered events first
        for ev in self._event_buffers.get(package_id, []):
            q.put_nowait(ev)
        self._subscribers.setdefault(package_id, []).append(q)
        return q

    def unsubscribe(self, package_id: str, q: asyncio.Queue) -> None:
        """Remove a subscriber queue."""
        subs = self._subscribers.get(package_id, [])
        if q in subs:
            subs.remove(q)

    async def _emit(self, package_id: str, event: dict) -> None:
        """Push an SSE event to all subscribers of a package (buffered)."""
        self._event_buffers.setdefault(package_id, []).append(event)
        subs = self._subscribers.get(package_id, [])
        for q in subs:
            try:
                q.put_nowait(event)
            except asyncio.QueueFull:
                pass  # drop if subscriber is slow
        if event.get("type") in ("generation_complete", "error"):
            self._done_packages.add(package_id)

    async def stream_events(self, package_id: str) -> AsyncGenerator[str, None]:
        """Async generator yielding SSE-formatted strings for a package."""
        # If already done before subscribe, replay and exit
        if package_id in self._done_packages:
            for ev in self._event_buffers.get(package_id, []):
                yield f"data: {json.dumps(ev)}\n\n"
            return
        q = self.subscribe(package_id)
        try:
            while True:
                try:
                    event = await asyncio.wait_for(q.get(), timeout=60.0)
                except asyncio.TimeoutError:
                    yield f"data: {json.dumps({'type': 'ping'})}\n\n"
                    continue
                yield f"data: {json.dumps(event)}\n\n"
                if event.get("type") in ("generation_complete", "error", "session_complete"):
                    break
        finally:
            self.unsubscribe(package_id, q)

    def register_agent(self, name: AgentName, agent: Any) -> None:
        """Register an agent implementation."""
        self._agents[name] = agent
        logger.info(f"Registered agent: {name.value}")

    def create_package(
        self,
        child_profile_id: str,
        moment_id: str,
        locale: str = "ta-SG",
    ) -> StoryPackage:
        """Create a new Story Package in CAPTURED state."""
        from .language_packs import pack_loader

        pack = pack_loader.get(locale)
        pkg_id = f"story_{uuid.uuid4().hex[:12]}"
        pkg = StoryPackage(
            id=pkg_id,
            status=StoryStatus.CAPTURED,
            child_profile_id=child_profile_id,
            moment_id=moment_id,
            language={
                "locale": locale,
                "pack_version": pack.pack_version if pack else "unknown",
            },
        )
        self._packages[pkg_id] = pkg
        self._traces[pkg_id] = [
            TraceEntry("orchestrator", "created", f"Package {pkg_id} created")
        ]
        self.persist(pkg)
        logger.info(f"Created StoryPackage {pkg_id}")
        return pkg

    def get_package(self, package_id: str) -> Optional[StoryPackage]:
        return self._packages.get(package_id)

    def get_trace(self, package_id: str) -> list[dict]:
        """Return the inspectable trace for a package."""
        return [e.to_dict() for e in self._traces.get(package_id, [])]

    def persist(self, pkg: StoryPackage) -> None:
        """Mirror the package + its trace to Neon (write-through, fire-and-forget)."""
        persistence.save("story_packages", pkg.id, pkg)
        persistence.save(
            "traces",
            pkg.id,
            {"entries": [e.to_dict() for e in self._traces.get(pkg.id, [])]},
        )

    def _transition(self, pkg: StoryPackage, new_status: StoryStatus) -> None:
        """Validate and execute a state transition."""
        allowed = STATUS_TRANSITIONS.get(pkg.status, [])
        if new_status not in allowed:
            raise ValueError(
                f"Invalid transition: {pkg.status.value} → {new_status.value}"
            )
        old = pkg.status
        pkg.status = new_status
        pkg.updated_at = datetime.utcnow()
        self._traces[pkg.id].append(
            TraceEntry("orchestrator", "transition", f"{old.value} → {new_status.value}")
        )
        self.persist(pkg)

    async def run_generation(self, package_id: str, start_index: int = 0) -> StoryPackage:
        """
        Run the pre-session generation pipeline (Agents 1-5).
        This is the main entry point after moment capture.
        F3: start_index > 0 resumes a paused pipeline (skips completed agents).
        """
        pkg = self._packages.get(package_id)
        if not pkg:
            raise ValueError(f"Package {package_id} not found")

        agent_status_map = {
            AgentName.MOMENT_LENS: StoryStatus.INTERPRETING,
            AgentName.LEARNING_PLANNER: StoryStatus.PLANNING,
            AgentName.STORY_WEAVER: StoryStatus.WRITING,
            AgentName.LANGUAGE_GUARDIAN: StoryStatus.VALIDATING,
            AgentName.FAMILY_VOICE_DIRECTOR: StoryStatus.AWAITING_PARENT,
        }

        total = len(PRE_SESSION_AGENTS)
        for idx, agent_name in enumerate(
            PRE_SESSION_AGENTS[start_index:], start=start_index
        ):
            target_status = agent_status_map[agent_name]
            progress = round((idx / total) * 100, 1)

            # Transition to agent's working status
            self._transition(pkg, target_status)
            self._traces[pkg.id].append(
                TraceEntry(agent_name.value, "started", f"Running {agent_name.value}")
            )
            await self._emit(package_id, {
                "type": "agent_started",
                "agent": agent_name.value,
                "progress_pct": progress,
                "status": target_status.value,
            })

            try:
                agent = self._agents.get(agent_name)
                if agent:
                    pkg = await agent.execute(pkg)
                else:
                    logger.warning(f"Agent {agent_name.value} not registered, skipping")

                self._traces[pkg.id].append(
                    TraceEntry(agent_name.value, "completed", f"{agent_name.value} done")
                )
                self.persist(pkg)  # capture the agent's output
                await self._emit(package_id, {
                    "type": "agent_completed",
                    "agent": agent_name.value,
                    "progress_pct": round(((idx + 1) / total) * 100, 1),
                })

                # F3 — pause the pipeline if Moment Lens needs a parent answer
                if (
                    agent_name == AgentName.MOMENT_LENS
                    and pkg.clarification.needed
                    and not pkg.clarification.answer
                ):
                    self._transition(pkg, StoryStatus.NEEDS_CLARIFICATION)
                    self._traces[pkg.id].append(
                        TraceEntry(
                            "orchestrator", "paused", "Awaiting parent clarification"
                        )
                    )
                    await self._emit(package_id, {
                        "type": "needs_clarification",
                        "package_id": package_id,
                        "question": pkg.clarification.question,
                        "status": StoryStatus.NEEDS_CLARIFICATION.value,
                        "progress_pct": round((1 / total) * 100, 1),
                    })
                    self.persist(pkg)
                    logger.info(f"Pipeline paused for clarification: {package_id}")
                    return pkg
            except Exception as e:
                self._traces[pkg.id].append(
                    TraceEntry(agent_name.value, "failed", str(e))
                )
                await self._emit(package_id, {
                    "type": "error",
                    "agent": agent_name.value,
                    "error": str(e),
                })
                logger.error(f"Agent {agent_name.value} failed: {e}")
                raise

        # After all agents, check validation
        if pkg.validation.language == ValidationStatus.BLOCKED:
            await self._emit(package_id, {"type": "error", "error": "Language validation blocked"})
            raise ValueError("Language validation blocked — cannot proceed to parent")

        if pkg.validation.safety == ValidationStatus.BLOCKED:
            await self._emit(package_id, {"type": "error", "error": "Safety validation blocked"})
            raise ValueError("Safety validation blocked — cannot proceed to parent")

        # Set status to awaiting parent if all passed
        if pkg.status != StoryStatus.AWAITING_PARENT:
            self._transition(pkg, StoryStatus.AWAITING_PARENT)

        self._traces[pkg.id].append(
            TraceEntry("orchestrator", "generation_complete", "Ready for parent review")
        )
        self.persist(pkg)
        await self._emit(package_id, {
            "type": "generation_complete",
            "package_id": package_id,
            "progress_pct": 100.0,
            "status": StoryStatus.AWAITING_PARENT.value,
        })
        return pkg

    async def resume_with_clarification(
        self, package_id: str, answer: str
    ) -> StoryPackage:
        """F3 — merge the parent's answer and resume from the paused step."""
        pkg = self._packages.get(package_id)
        if not pkg:
            raise ValueError(f"Package {package_id} not found")

        if pkg.status != StoryStatus.NEEDS_CLARIFICATION:
            raise ValueError(
                f"Package not awaiting clarification: {pkg.status.value}"
            )

        pkg.moment_facts.append(MomentFact(text=answer, confidence=0.95))
        pkg.clarification.answer = answer
        pkg.clarification.needed = False
        self._traces[pkg.id].append(
            TraceEntry("orchestrator", "clarified", "Parent answered clarification")
        )
        self.persist(pkg)
        # Resume after Moment Lens (idempotent — agent 1 already ran)
        return await self.run_generation(package_id, start_index=1)

    async def approve_package(self, package_id: str) -> StoryPackage:
        """Parent approves the Story Package — final gate."""
        pkg = self._packages.get(package_id)
        if not pkg:
            raise ValueError(f"Package {package_id} not found")

        if pkg.status != StoryStatus.AWAITING_PARENT:
            raise ValueError(f"Package not awaiting parent: {pkg.status.value}")

        self._transition(pkg, StoryStatus.APPROVED)
        pkg.validation.parent_approved_at = datetime.utcnow()
        self._traces[pkg.id].append(
            TraceEntry("orchestrator", "approved", "Parent approved")
        )
        self.persist(pkg)
        return pkg

    async def start_session(self, package_id: str) -> StoryPackage:
        """Begin a child session with an approved package."""
        pkg = self._packages.get(package_id)
        if not pkg:
            raise ValueError(f"Package {package_id} not found")

        if pkg.status != StoryStatus.APPROVED:
            raise ValueError(f"Package not approved: {pkg.status.value}")

        self._transition(pkg, StoryStatus.IN_SESSION)
        return pkg

    async def complete_session(self, package_id: str) -> StoryPackage:
        """Mark session as completed."""
        pkg = self._packages.get(package_id)
        if not pkg:
            raise ValueError(f"Package {package_id} not found")

        self._transition(pkg, StoryStatus.COMPLETED)

        # Run Agent 6 (Growth Coach) for session summary
        agent = self._agents.get(AgentName.GROWTH_COACH)
        if agent:
            pkg = await agent.execute(pkg)

        self._traces[pkg.id].append(
            TraceEntry("orchestrator", "session_complete", "Session completed")
        )
        self.persist(pkg)
        return pkg

    def list_packages(self) -> list[StoryPackage]:
        """List all packages."""
        return list(self._packages.values())


# Singleton for the application
orchestrator = WorkflowOrchestrator()

"""
Workflow Orchestrator — deterministic state machine.

Owns workflow state, executes agents in order, validates schemas,
handles retries, enforces gates, and preserves an inspectable trace.

States: captured → interpreting → planning → writing → validating →
        awaiting_parent → approved → in_session → completed
"""
from __future__ import annotations

import logging
import uuid
from datetime import datetime
from enum import Enum
from typing import Any, Optional

from ..schemas.story_package import (
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
    StoryStatus.INTERPRETING: [StoryStatus.PLANNING, StoryStatus.CAPTURED],  # can retry
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
        pkg_id = f"story_{uuid.uuid4().hex[:12]}"
        pkg = StoryPackage(
            id=pkg_id,
            status=StoryStatus.CAPTURED,
            child_profile_id=child_profile_id,
            moment_id=moment_id,
            language={"locale": locale, "pack_version": "1.0.0"},
        )
        self._packages[pkg_id] = pkg
        self._traces[pkg_id] = [
            TraceEntry("orchestrator", "created", f"Package {pkg_id} created")
        ]
        logger.info(f"Created StoryPackage {pkg_id}")
        return pkg

    def get_package(self, package_id: str) -> Optional[StoryPackage]:
        return self._packages.get(package_id)

    def get_trace(self, package_id: str) -> list[dict]:
        """Return the inspectable trace for a package."""
        return [e.to_dict() for e in self._traces.get(package_id, [])]

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

    async def run_generation(self, package_id: str) -> StoryPackage:
        """
        Run the pre-session generation pipeline (Agents 1-5).
        This is the main entry point after moment capture.
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

        for agent_name in PRE_SESSION_AGENTS:
            target_status = agent_status_map[agent_name]

            # Transition to agent's working status
            self._transition(pkg, target_status)
            self._traces[pkg.id].append(
                TraceEntry(agent_name.value, "started", f"Running {agent_name.value}")
            )

            try:
                agent = self._agents.get(agent_name)
                if agent:
                    pkg = await agent.execute(pkg)
                else:
                    logger.warning(f"Agent {agent_name.value} not registered, skipping")

                self._traces[pkg.id].append(
                    TraceEntry(agent_name.value, "completed", f"{agent_name.value} done")
                )
            except Exception as e:
                self._traces[pkg.id].append(
                    TraceEntry(agent_name.value, "failed", str(e))
                )
                logger.error(f"Agent {agent_name.value} failed: {e}")
                raise

        # After all agents, check validation
        if pkg.validation.language == ValidationStatus.BLOCKED:
            raise ValueError("Language validation blocked — cannot proceed to parent")

        if pkg.validation.safety == ValidationStatus.BLOCKED:
            raise ValueError("Safety validation blocked — cannot proceed to parent")

        # Set status to awaiting parent if all passed
        if pkg.status != StoryStatus.AWAITING_PARENT:
            self._transition(pkg, StoryStatus.AWAITING_PARENT)

        self._traces[pkg.id].append(
            TraceEntry("orchestrator", "generation_complete", "Ready for parent review")
        )
        return pkg

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
        return pkg

    def list_packages(self) -> list[StoryPackage]:
        """List all packages."""
        return list(self._packages.values())


# Singleton for the application
orchestrator = WorkflowOrchestrator()

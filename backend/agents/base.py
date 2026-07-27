"""
Base agent class — all 6 agents inherit from this.
"""
from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from typing import Optional

from ..adapters.interfaces import LLMProvider, VisionProvider
from ..schemas.story_package import StoryPackage

logger = logging.getLogger(__name__)


class BaseAgent(ABC):
    """Base class for all TaleLah agents."""

    name: str = "base"
    spec_version: str = "1.0.0"

    def __init__(
        self,
        llm: Optional[LLMProvider] = None,
        vision: Optional[VisionProvider] = None,
    ):
        self.llm = llm
        self.vision = vision

    @abstractmethod
    async def execute(self, package: StoryPackage) -> StoryPackage:
        """
        Execute this agent's logic on the Story Package.
        Must read from and write to structured fields only.
        Free-form prose must never pass directly into child mode.
        """
        ...

    def _record_provenance(self, package: StoryPackage) -> None:
        """Record this agent's spec version in the provenance."""
        package.provenance.agent_spec_versions[self.name] = self.spec_version

    def _set_model_version(self, package: StoryPackage, model_key: str, model_name: str) -> None:
        """Record the model version used in provenance."""
        package.provenance.model_versions[model_key] = model_name

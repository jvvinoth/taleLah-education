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
        llm_registry: Optional[dict[str, LLMProvider]] = None,
    ):
        self.llm = llm
        self.vision = vision
        # provider name (from pack.providers.llm) → concrete LLM adapter
        self.llm_registry = llm_registry or {}

    def _llm_for(self, package: StoryPackage) -> tuple[Optional[LLMProvider], str]:
        """Pack-declared LLM for this package's locale (AC-08) — e.g. Tamil
        story text via Sarvam, Chinese/Malay via Qwen-Max. Falls back to the
        default LLM when the pack has no routing or the provider is missing.
        Returns (provider, provider_name) for provenance."""
        from ..core.language_packs import pack_loader

        pack = pack_loader.get(package.language.locale)
        if pack and pack.providers.llm in self.llm_registry:
            return self.llm_registry[pack.providers.llm], pack.providers.llm
        return self.llm, "qwen-max" if self.llm else "fallback"

    def _drafting_llm(self, package: StoryPackage) -> tuple[Optional[LLMProvider], str]:
        """LLM for long English drafts (the story itself), as opposed to native
        language work. The pack LLM is chosen for native-script quality on short
        text; asked for a whole story as JSON, a small native model returns a
        few characters and the child is left with filler scenes. So draft with
        the default reasoning model and let the Language Guardian carry it into
        the home language. Falls back to the pack LLM if no default exists."""
        if self.llm:
            return self.llm, "qwen-max"
        return self._llm_for(package)

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

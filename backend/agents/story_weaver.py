"""
Agent 3: Story Weaver — specs/agents/3-story-weaver.md

Wraps the real moment + learning plan into a short 4-scene adventure.

Model: Qwen-Max.
Reads: facts, learning plan, child interests, approved story templates.
Writes: draft story (title, ≤3 opening choices, 4 scenes, room mission, ending prompt).
"""
from __future__ import annotations

import logging

from ..schemas.story_package import (
    EndingPrompt,
    FamilyHandoff,
    InteractionType,
    RoomMission,
    SceneInteraction,
    Story,
    StoryPackage,
    StoryScene,
)
from .base import BaseAgent

logger = logging.getLogger(__name__)


class StoryWeaverAgent(BaseAgent):
    name = "story_weaver"
    spec_version = "1.0.0"

    async def execute(self, package: StoryPackage) -> StoryPackage:
        """
        Generate a 4-scene story wrapping the real moment.

        Rules (from spec):
        - Preserve the real moment as the anchor.
        - No open-ended child chat. Bounded choices only.
        - Total narration suited to 5-8 minutes.
        - The targetPhrase must be useful to progress.
        - Include exactly one physical (off-screen) action.
        """
        logger.info(f"[StoryWeaver] Weaving story for package {package.id}")

        # In production: call Qwen-Max with facts + plan + interests.
        # Sprint 0: golden demo placeholder.
        if not package.story.title:
            package.story = Story(
                title="Mina and the Missing MRT Color",
                title_target_lang="",  # Language Guardian fills this
                opening_choices=[
                    "Find the missing color",
                    "Repair the secret station",
                    "Follow Mina's route",
                ],
                scenes=[
                    StoryScene(
                        index=0,
                        narration="Mina the Myna spotted something strange on the MRT map — a station had lost its color!",
                        visual_id="scene_mrt_map",
                        interaction=SceneInteraction(
                            type=InteractionType.CHOICE,
                            options=["Look under the seat", "Ask the conductor", "Check the map again"],
                        ),
                    ),
                    StoryScene(
                        index=1,
                        narration="The red train was waiting at the platform. Mina needed to know which color comes next.",
                        visual_id="scene_platform",
                        interaction=SceneInteraction(
                            type=InteractionType.SPEAK,
                            expected_intent="names_a_color",
                        ),
                    ),
                    StoryScene(
                        index=2,
                        narration="The train zoomed through the tunnel. What will the next station be?",
                        visual_id="scene_tunnel",
                        interaction=SceneInteraction(
                            type=InteractionType.SPEAK,
                            expected_intent="predicts_next",
                        ),
                    ),
                    StoryScene(
                        index=3,
                        narration="Mina found the missing color! It was hiding behind a rainbow HDB block.",
                        visual_id="scene_rainbow",
                        interaction=SceneInteraction(
                            type=InteractionType.CHOICE,
                            options=["Celebrate with Mina", "Find more colors"],
                        ),
                    ),
                ],
                room_mission=RoomMission(
                    instruction="Find something in the room with the same color. Bring it to someone and say, 'This is red.'",
                    safety_validated=False,  # Safety gate validates this
                ),
                family_handoff=FamilyHandoff(
                    prompt="Ask the child which station their red block should visit next. Let them answer before helping.",
                    response_suggestion="You can say: 'Maybe it should go to the park station!' or ask about their favourite place.",
                ),
                ending_prompt=EndingPrompt(
                    text="What was your favourite part of today's adventure?",
                ),
            )
            logger.info("[StoryWeaver] Generated 4-scene story")

        self._record_provenance(package)
        return package

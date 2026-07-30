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

WEAVER_SYSTEM_PROMPT = """You are a children's story writer for a language learning app.
You write short 4-scene adventures based on a child's real daily activity.

Rules:
- Preserve the real moment as the anchor scene.
- No open-ended child chat. Only bounded choices or speak interactions.
- Total narration suited to 5-8 minutes reading.
- The target phrase must be useful to progress the story.
- Include exactly one physical (off-screen) room mission.
- Opening choices: max 3 options for the child to pick from.
- Each scene has an interaction: either CHOICE (multiple options) or SPEAK (child says a word).
- Room mission must be safe (stay indoors, no sharp/hot objects).
- Family handoff: prompt for an adult to continue the conversation.
- Ending prompt: simple question about the child's favourite part.

Respond with JSON:
{
  "title": "Story title",
  "opening_choices": ["Choice 1", "Choice 2", "Choice 3"],
  "scenes": [
    {"index": 0, "narration": "Scene text...", "interaction_type": "choice", "options": ["opt1", "opt2", "opt3"]},
    {"index": 1, "narration": "Scene text...", "interaction_type": "speak", "expected_intent": "names_a_color"},
    {"index": 2, "narration": "Scene text...", "interaction_type": "speak", "expected_intent": "predicts_next"},
    {"index": 3, "narration": "Scene text...", "interaction_type": "choice", "options": ["opt1", "opt2"]}
  ],
  "room_mission": "Find something in the room with the same color. Bring it and say the color name.",
  "family_handoff_prompt": "Ask the child a simple follow-up question about the story.",
  "family_response_suggestion": "You can say: 'Maybe it should go to the park!'",
  "ending_prompt": "What was your favourite part?"
}

No markdown. No explanation."""


class StoryWeaverAgent(BaseAgent):
    name = "story_weaver"
    spec_version = "1.1.0"

    async def execute(self, package: StoryPackage) -> StoryPackage:
        logger.info(f"[StoryWeaver] Weaving story for package {package.id}")

        if package.story.title:
            logger.info("[StoryWeaver] Story already exists, skipping")
            self._record_provenance(package)
            return package

        # Pack-declared LLM — e.g. Tamil uses Sarvam for native quality
        llm, llm_name = self._llm_for(package)
        if llm:
            try:
                facts_text = "\n".join([f"- {f.text}" for f in package.moment_facts])
                plan = package.learning_plan

                result = await llm.generate_json(
                    prompt=(
                        f"Child's real activity:\n{facts_text}\n\n"
                        f"Learning goal: {plan.speaking_goal if plan else 'Name colors and predict'}\n"
                        f"Target words: {plan.target_words if plan else ['red', 'station', 'next']}\n"
                        f"Target phrase: {plan.target_phrase if plan else 'The red train goes to the next station.'}\n\n"
                        f"Write a 4-scene adventure story based on this activity."
                    ),
                    system=WEAVER_SYSTEM_PROMPT,
                )

                story = self._parse_story(result, package)
                package.story = story
                self._set_model_version(package, "story_weaver", llm_name)
                logger.info(f"[StoryWeaver] Generated story via {llm_name}: {story.title}")

            except Exception as e:
                logger.error(f"[StoryWeaver] {llm_name} call failed, using fallback: {e}")
                package.story = self._fallback_story()
                self._set_model_version(package, "story_weaver", "fallback")
        else:
            package.story = self._fallback_story()
            self._set_model_version(package, "story_weaver", "fallback")

        self._record_provenance(package)
        return package

    def _parse_story(self, result: dict, package: StoryPackage) -> Story:
        """Parse Qwen JSON response into Story schema."""
        scenes = []
        for s in result.get("scenes", [])[:4]:
            interaction_type = s.get("interaction_type", "choice")
            if interaction_type == "speak":
                interaction = SceneInteraction(
                    type=InteractionType.SPEAK,
                    expected_intent=s.get("expected_intent", ""),
                )
            else:
                interaction = SceneInteraction(
                    type=InteractionType.CHOICE,
                    options=s.get("options", []),
                )

            scenes.append(StoryScene(
                index=s.get("index", len(scenes)),
                narration=s.get("narration", ""),
                visual_id=f"scene_{s.get('index', len(scenes))}",
                interaction=interaction,
            ))

        # Ensure exactly 4 scenes
        while len(scenes) < 4:
            scenes.append(StoryScene(
                index=len(scenes),
                narration="The adventure continues...",
                interaction=SceneInteraction(type=InteractionType.CHOICE, options=["Continue", "Try again"]),
            ))

        return Story(
            title=result.get("title", "The Missing Color Adventure"),
            title_target_lang="",
            opening_choices=result.get("opening_choices", ["Start the adventure"])[:3],
            scenes=scenes,
            room_mission=RoomMission(
                instruction=result.get("room_mission", "Find something colorful and name its color."),
                safety_validated=False,
            ),
            family_handoff=FamilyHandoff(
                prompt=result.get("family_handoff_prompt", "Ask the child about their favourite part."),
                response_suggestion=result.get("family_response_suggestion", ""),
            ),
            ending_prompt=EndingPrompt(
                text=result.get("ending_prompt", "What was your favourite part?"),
            ),
        )

    def _fallback_story(self) -> Story:
        return Story(
            title="Mina and the Missing MRT Color",
            title_target_lang="",
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
                    narration="Mina found the missing color! It was hiding near a rainbow HDB block.",
                    visual_id="scene_rainbow",
                    interaction=SceneInteraction(
                        type=InteractionType.CHOICE,
                        options=["Celebrate with Mina", "Find more colors"],
                    ),
                ),
            ],
            room_mission=RoomMission(
                instruction="Find something in the room with the same color. Bring it to someone and say the color name.",
                safety_validated=False,
            ),
            family_handoff=FamilyHandoff(
                prompt="Ask the child which station their block should visit next. Let them answer before helping.",
                response_suggestion="You can say: 'Maybe it should go to the park station!' or ask about their favourite place.",
            ),
            ending_prompt=EndingPrompt(
                text="What was your favourite part of today's adventure?",
            ),
        )

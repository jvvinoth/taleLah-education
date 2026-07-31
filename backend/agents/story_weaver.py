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

WEAVER_SYSTEM_PROMPT = """You are a grandmother telling a bedtime story to her
4-7 year old grandchild, who is curled up right next to her. You are not
writing a summary or a lesson. You are TELLING A STORY, out loud, tonight.

HOW GRANDMA TELLS IT
- She talks straight to the child: "And do you know what happened next?"
- She uses her whole voice: sound words (thump! shhh... splash! crrrunch),
  a whisper for the scary bit, a big voice for the surprise.
- She slows down on the important part and says it twice.
- She names things the child already knows — amma's kitchen, the blue slipper,
  the sound of the gate.
- She never explains a feeling; she shows it. Not "he was sad" but "his lip
  went wobbly and he looked at his feet".
- Every scene ends leaning forward, so the child NEEDS to hear the next one.

THE SHAPE — four scenes that are ONE story, not four sentences:
  Scene 1 COSY START: open inside the real moment the parent described. Give
    the hero a name and let us see them doing that real thing. At the very end,
    something small and odd happens.
  Scene 2 THE WOBBLE: the odd thing turns into a little problem. The hero tries
    something — and it does not work. Keep it gentle: no danger, no scary
    monsters, nobody hurt.
  Scene 3 THE TRY: the hero cannot do it alone and needs the child listening.
    This is where the target words do real work — saying them MOVES the story
    forward. Not decoration, plot.
  Scene 4 WARM END: it works, because of what the child did. Come back to where
    the story started, so it closes like a circle, and end on a snuggle.

TYING IT TOGETHER — the most important rules:
- ONE hero with ONE name. Use that same name in every single scene.
- Every scene must OPEN by picking up the exact thing that ended the scene
  before: same object, same place, same feeling. A listener must never think
  "wait, when did that happen?"
- Carry one object right through the whole story (the blue slipper, the little
  red umbrella, the paper boat). Mention it in every scene.
- Write a REFRAIN: one short sing-song line, 4-8 words. Put it in scene 1 and
  bring it back WORD FOR WORD at least twice more, so the child can join in.
- The child's choices must be things a child would actually say out loud, and
  the next scene must read like an answer to what they chose.
- 3 to 5 short sentences per scene. A real told story — never one flat line.

HARD RULES
- Preserve the real moment as the anchor of scene 1.
- No open-ended chat. Each scene is either CHOICE (max 3 options) or SPEAK.
- Exactly one physical room mission, safe: stay indoors, nothing sharp or hot.
- Give each scene a storybook chapter title and one emoji that matches what
  actually happens in THAT scene.
- Family handoff: an adult continues the conversation afterwards.
- Ending prompt: a simple question about the child's favourite part.

Respond with JSON:
{
  "title": "Story title a child would ask for by name",
  "hero_name": "The one name used in every scene",
  "refrain": "The sing-song line that comes back",
  "opening_choices": ["Choice 1", "Choice 2", "Choice 3"],
  "scenes": [
    {"index": 0, "title": "Chapter title", "emoji": "🚂", "narration": "3-5 spoken sentences...", "interaction_type": "choice", "options": ["opt1", "opt2", "opt3"]},
    {"index": 1, "title": "Chapter title", "emoji": "🌧", "narration": "3-5 spoken sentences...", "interaction_type": "speak", "expected_intent": "names_a_color"},
    {"index": 2, "title": "Chapter title", "emoji": "🔍", "narration": "3-5 spoken sentences...", "interaction_type": "speak", "expected_intent": "predicts_next"},
    {"index": 3, "title": "Chapter title", "emoji": "🌈", "narration": "3-5 spoken sentences...", "interaction_type": "choice", "options": ["opt1", "opt2"]}
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

        # The draft is written in English and translated later, so it needs the
        # strongest long-form model rather than the pack's native-language one.
        llm, llm_name = self._drafting_llm(package)
        if llm:
            try:
                facts_text = "\n".join([f"- {f.text}" for f in package.moment_facts])
                plan = package.learning_plan

                words = plan.target_words if plan else ["red", "station", "next"]
                result = await llm.generate_json(
                    prompt=(
                        f"This really happened to the child today:\n{facts_text}\n\n"
                        f"Start your story right there, in that real moment — the child\n"
                        f"should recognise it as their own day.\n\n"
                        f"The child is learning to say: {plan.speaking_goal if plan else 'Name colors and predict'}\n"
                        f"These words must be spoken by the child to move the story on: {words}\n"
                        f"Work towards this whole phrase: {plan.target_phrase if plan else 'The red train goes to the next station.'}\n\n"
                        f"Now tell it the way you would tonight, with the child leaning on\n"
                        f"your shoulder. Four scenes, one story, one hero, one refrain."
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

    # If the writer forgets a picture, fall back to one that at least matches
    # the beat of the story it sits on (cosy start → wobble → try → warm end).
    _BEAT_EMOJIS = ["🏡", "❓", "🔍", "🌈"]
    _BEAT_TITLES = [
        "How It Started",
        "The Little Problem",
        "Say It With Me",
        "All Better Now",
    ]

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

            beat = len(scenes)
            narration = (s.get("narration") or "").strip()
            if not narration:
                continue
            scenes.append(StoryScene(
                index=s.get("index", beat),
                title=(s.get("title") or self._BEAT_TITLES[min(beat, 3)]).strip(),
                emoji=self._first_emoji(s.get("emoji", "")) or self._BEAT_EMOJIS[min(beat, 3)],
                narration=narration,
                visual_id=f"scene_{s.get('index', beat)}",
                interaction=interaction,
            ))

        # A story is four scenes or it is not this story
        if len(scenes) < 4:
            # Padding with "The adventure continues..." used to hide a failed
            # generation behind four flat filler lines. A half-written story is
            # worse than the hand-written one, so refuse it and let the caller
            # fall back to a story that actually holds together.
            raise ValueError(
                f"story writer returned only {len(scenes)} usable scene(s) of 4"
            )

        return Story(
            title=result.get("title", "The Missing Color Adventure"),
            title_target_lang="",
            opening_choices=result.get("opening_choices", ["Start the adventure"])[:3],
            scenes=scenes,
            refrain=(result.get("refrain") or "").strip(),
            hero_name=(result.get("hero_name") or "").strip(),
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

    @staticmethod
    def _first_emoji(raw: str) -> str:
        """Writers sometimes answer "🚂 train" or just "a train". Keep the picture
        only — anything ASCII is a word, not an emoji."""
        picture = "".join(ch for ch in (raw or "").strip() if not ch.isascii())
        # Room for one emoji plus its modifiers (skin tone, variation selector).
        return picture[:3]

    def _fallback_story(self) -> Story:
        return Story(
            title="Mina and the Missing MRT Color",
            title_target_lang="",
            refrain="Red, red, where did you go?",
            hero_name="Mina",
            opening_choices=[
                "Find the missing color",
                "Repair the secret station",
                "Follow Mina's route",
            ],
            scenes=[
                StoryScene(
                    index=0,
                    title="The Map With a Hole In It",
                    emoji="🗺️",
                    narration=(
                        "Mina the Myna was sitting on the MRT map, the way she does "
                        "every morning. She hopped along the little colored lines — "
                        "hop, hop, hop. And then she stopped. One station had gone "
                        "white as rice! Red, red, where did you go?"
                    ),
                    visual_id="scene_mrt_map",
                    interaction=SceneInteraction(
                        type=InteractionType.CHOICE,
                        options=["Look under the seat", "Ask the conductor", "Check the map again"],
                    ),
                ),
                StoryScene(
                    index=1,
                    title="The Train That Would Not Go",
                    emoji="🚂",
                    narration=(
                        "Mina flew down to the platform, still humming — red, red, "
                        "where did you go? The train was waiting there with its doors "
                        "open wide. But it would not move. It did not know which color "
                        "came next, and neither did Mina. Her little wings drooped."
                    ),
                    visual_id="scene_platform",
                    interaction=SceneInteraction(
                        type=InteractionType.SPEAK,
                        expected_intent="names_a_color",
                    ),
                ),
                StoryScene(
                    index=2,
                    title="Say It Loud In the Tunnel",
                    emoji="🔅",
                    narration=(
                        "You said it! And the moment you did — whoosh! — the train "
                        "remembered, and away it went into the dark tunnel. Mina held "
                        "on tight to the window. But it is so dark in here. Where do "
                        "you think this train is taking us?"
                    ),
                    visual_id="scene_tunnel",
                    interaction=SceneInteraction(
                        type=InteractionType.SPEAK,
                        expected_intent="predicts_next",
                    ),
                ),
                StoryScene(
                    index=3,
                    title="Found You!",
                    emoji="🌈",
                    narration=(
                        "Out came the train into the sunshine, and there it was — the "
                        "missing color, hiding on the side of a rainbow HDB block! "
                        "Mina flew all the way back to her map and painted the little "
                        "station in. Red, red, there you are. And she tucked her head "
                        "under her wing, right where the story started."
                    ),
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

"""
Safety & Parent Approval Gate — specs/safety.md

Safety is an enforced policy layer + approval gate, not a conversational agent.
Any failed check blocks child mode.
"""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass

from ..schemas.story_package import StoryPackage, ValidationStatus

logger = logging.getLogger(__name__)

# Mission safety — reject any mission involving these (word-boundary matched)
MISSION_REJECT_KEYWORDS = [
    "leave the home", "leave the house", "go outside", "street",
    "stranger", "unknown person",
    "climb", "climbing", "ladder", "roof", "balcony",
    "sharp", "knife", "scissors", "blade",
    "stove", "cooking", "fire", "hot", "heat", "boil",
    "medicine", "pill", "drug",
    "allergy", "peanut", "eat", "taste", "swallow",
    "pool", "swim", "bath", "bathtub", "bucket of water",
    "road", "traffic", "cross the road",
]


@dataclass
class SafetyCheckResult:
    passed: bool
    reason: str = ""


class SafetyGate:
    """
    Validates that a Story Package meets safety requirements
    before it can be approved for child mode.
    """

    def check_moment_content(self, text: str) -> SafetyCheckResult:
        """Moderate source moment input."""
        if not text or not text.strip():
            return SafetyCheckResult(False, "Empty moment text")

        # Check for sensitive content patterns
        sensitive_patterns = [
            r"\b(hurt|injury|blood|pain|sick|hospital)\b",
            r"\b(fight|hit|slap|punch|kick)\b",
            r"\b(scared|terrified|nightmare)\b",
            r"\b(weapon|gun|bomb)\b",
        ]
        for pattern in sensitive_patterns:
            if re.search(pattern, text.lower()):
                return SafetyCheckResult(
                    False,
                    "Moment contains sensitive content that cannot be used. Please describe a different moment."
                )
        return SafetyCheckResult(True)

    def check_mission_safety(self, mission_instruction: str) -> SafetyCheckResult:
        """
        Validate mission physical safety.
        Reject any mission involving: leaving home, strangers, climbing,
        sharp objects, heat, medicine, food-allergy risks, water hazards.
        """
        if not mission_instruction:
            return SafetyCheckResult(False, "Missing mission instruction")

        instruction_lower = mission_instruction.lower()
        for keyword in MISSION_REJECT_KEYWORDS:
            # Word-boundary match — bare substrings over-block (e.g. 'hot'
            # inside 'photo', 'water' inside 'water the plant' was too broad)
            if re.search(rf"\b{re.escape(keyword)}\b", instruction_lower):
                return SafetyCheckResult(
                    False,
                    f"Mission rejected: contains unsafe action '{keyword}'"
                )

        return SafetyCheckResult(True)

    def check_child_facing_boundary(self, package: StoryPackage) -> SafetyCheckResult:
        """
        Ensure child-facing content has no:
        - external links
        - ads or purchases
        - clinical/diagnostic language
        - emotion/confidence inference
        - secrets from adults
        """
        all_text = " ".join([
            package.story.title,
            *[s.narration for s in package.story.scenes],
            package.story.room_mission.instruction,
            package.story.family_handoff.prompt,
        ]).lower()

        # No URLs
        url_pattern = r"https?://|www\.|\.com|\.org|\.net"
        if re.search(url_pattern, all_text):
            return SafetyCheckResult(False, "Child content contains external links")

        # No diagnostic language (use word boundary to avoid false positives)
        diagnostic_terms = ["diagnosis", "disorder", "syndrome", "delayed",
                           "assessment", "evaluation", "therapy", "treatment"]
        for term in diagnostic_terms:
            if re.search(rf"\b{term}\b", all_text):
                return SafetyCheckResult(False, f"Child content contains diagnostic term: {term}")

        # No secrets
        if "secret" in all_text and "from" in all_text:
            return SafetyCheckResult(False, "Content may ask child to keep secrets from adults")

        # No commercial language
        commercial_terms = ["buy", "purchase", "subscribe", "premium", "free trial", "discount"]
        for term in commercial_terms:
            if term in all_text:
                return SafetyCheckResult(False, f"Child content contains commercial term: {term}")

        return SafetyCheckResult(True)

    def validate_package(self, package: StoryPackage) -> tuple[bool, list[str]]:
        """
        Run all safety checks on a Story Package.
        Returns (passed, list_of_failures).
        """
        failures = []

        # 1. Mission safety
        mission_check = self.check_mission_safety(
            package.story.room_mission.instruction
        )
        if not mission_check.passed:
            failures.append(mission_check.reason)

        # 2. Child-facing boundary
        boundary_check = self.check_child_facing_boundary(package)
        if not boundary_check.passed:
            failures.append(boundary_check.reason)

        # 3. Language validation must have passed
        if package.validation.language == ValidationStatus.BLOCKED:
            failures.append("Language validation is blocked")

        # 4. Must have required fields
        if not package.story.scenes:
            failures.append("Story has no scenes")
        if len(package.story.scenes) != 4:
            failures.append(f"Story must have exactly 4 scenes, has {len(package.story.scenes)}")
        if not package.learning_plan:
            failures.append("Missing learning plan")
        if package.learning_plan and len(package.learning_plan.target_words) not in range(3, 6):
            failures.append("Target words must be 3-5")

        passed = len(failures) == 0

        if passed:
            package.validation.safety = ValidationStatus.PASSED
            package.story.room_mission.safety_validated = True
            logger.info(f"[SafetyGate] Package {package.id} passed all checks")
        else:
            package.validation.safety = ValidationStatus.BLOCKED
            logger.warning(f"[SafetyGate] Package {package.id} failed: {failures}")

        return passed, failures


safety_gate = SafetyGate()

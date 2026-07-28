"""F6 — fuzzy intent matcher unit tests (AC-04)."""
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from backend.core.speech import (  # noqa: E402
    dice_coefficient,
    levenshtein_ratio,
    match_intent,
    normalize,
)

EXPECTED = {
    "names_a_color": [
        "சிவப்பு", "நீலம்", "பச்சை", "மஞ்சள்",
        "sivappu", "neelam", "pachai", "manjal",
        "red", "blue", "green", "yellow",
    ],
    "counts": ["ஒன்று", "இரண்டு", "மூன்று", "ondru", "irandu", "moondru",
               "one", "two", "three"],
}


def test_exact_tamil_keyword_matches():
    m = match_intent("சிவப்பு", EXPECTED, floor=0.7)
    assert m.matched and m.intent == "names_a_color" and m.score == 1.0


def test_keyword_inside_sentence_matches():
    m = match_intent("அது சிவப்பு ரயில்", EXPECTED, floor=0.7)
    assert m.matched and m.intent == "names_a_color"


def test_romanised_keyword_matches():
    m = match_intent("Sivappu!", EXPECTED, floor=0.7)
    assert m.matched and m.intent == "names_a_color"


def test_near_miss_asr_typo_still_matches():
    # one dropped character — realistic child-ASR noise
    m = match_intent("sivapu", EXPECTED, floor=0.7)
    assert m.matched and m.intent == "names_a_color"


def test_unrelated_speech_does_not_match():
    m = match_intent("elephant banana xyz", EXPECTED, floor=0.7)
    assert not m.matched


def test_empty_transcript_does_not_match():
    m = match_intent("", EXPECTED, floor=0.7)
    assert not m.matched and m.score == 0.0


def test_restrict_to_scene_intent_only():
    # "red" belongs to names_a_color; restricting to counts must not match it
    m = match_intent("red", EXPECTED, floor=0.7, restrict_to="counts")
    assert not m.matched


def test_nfc_normalization_folds_decomposed_input():
    # Tamil is largely NFC-stable, so prove NFC folding with a decomposable
    # char: e + combining acute must fold to the composed form.
    decomposed = unicodedata.normalize("NFD", "é")
    assert decomposed != "é"  # sanity: NFD really differs here
    assert normalize(decomposed) == "é"
    # And Tamil keywords still match after an NFC round-trip.
    m = match_intent(unicodedata.normalize("NFC", "சிவப்பு"), EXPECTED, floor=0.7)
    assert m.matched and m.score == 1.0


def test_normalize_strips_punctuation_and_case():
    assert normalize("  RED!! ") == "red"


def test_dice_and_levenshtein_bounds():
    assert dice_coefficient("abc", "abc") == 1.0
    assert dice_coefficient("abc", "xyz") == 0.0
    assert levenshtein_ratio("abc", "abc") == 1.0
    assert 0.0 <= levenshtein_ratio("abc", "abd") < 1.0

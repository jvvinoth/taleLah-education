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
    score_reading,
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


# ── "I read" mode — read-aloud coverage scorer ─────────────────────

NARRATION = "ஒரு நாள், அருண் சிவப்பு ரயிலை பார்த்தான்!"


def test_full_reading_scores_high_with_no_practice_words():
    r = score_reading(NARRATION, NARRATION)
    assert r.heard and r.score == 1.0 and r.missed_words == []


def test_partial_reading_scores_between_and_reports_missed():
    r = score_reading("ஒரு நாள் அருண்", NARRATION)
    assert r.heard and 0.0 < r.score < 1.0
    assert "சிவப்பு" in r.missed_words


def test_silence_is_not_heard_and_never_penalised():
    r = score_reading("", NARRATION)
    assert not r.heard and r.score == 0.0 and r.missed_words == []


def test_reading_is_fuzzy_against_asr_noise():
    # ASR drops a punctuation mark and slightly mangles one token — the
    # child must still get full credit for what they read.
    r = score_reading("ஒரு நாள அருண சிவப்பு ரயிலை பார்த்தான்", NARRATION)
    assert r.heard and r.score >= 0.8


def test_asr_noise_on_a_quiet_mic_is_not_a_reading():
    # A quiet mic makes Sarvam emit a stray syllable. Counting that as a
    # reading would tell a child who never spoke "you read 0 of 6 words".
    r = score_reading("ம்", NARRATION)
    assert not r.heard and r.score == 0.0


def test_one_real_word_still_counts_as_read():
    # The guard above must not swallow a genuine short attempt.
    r = score_reading("அருண்", NARRATION)
    assert r.heard and r.words_read == 1

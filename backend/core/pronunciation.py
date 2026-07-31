"""
Word-level pronunciation tutoring (AC-04, AC-07).

A real tutor does not answer "Super!" to everything. She listens, compares
what she heard against the letters of the target word, and names the exact
part to try again — then models it.

This module does the compare step: grapheme-cluster alignment between the
ASR transcript and the target word, producing a verdict plus the specific
syllable to practise.

Privacy contract (AC-07, unchanged): every string returned here is derived
from the TARGET word, never from the transcript. The child's words are
scored and discarded — they never leave the process.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from difflib import SequenceMatcher

from .speech import (
    dice_coefficient,
    keyword_score,
    levenshtein_ratio,
    normalize,
    split_graphemes,
)

__all__ = ["WordAnalysis", "analyse_word", "split_graphemes"]

# Verdict bands. Deliberately generous: a child mid-attempt should be told
# "close, try this part" far more often than "let's hear it again", and ASR
# on child speech is noisy — see UNCLEAR handling in the caller.
PERFECT_FLOOR = 0.85
CLOSE_FLOOR = 0.55

# Tamil pulli (virama). Word-final ன vs ன் is an orthographic convention,
# not a different pronunciation, and the LLM writes vocabulary both ways —
# so it must never cost a child a "perfect".
_VIRAMA = "\u0BCD"


def _canon(token: str) -> str:
    """Drop a word-final virama so மீன் and மீன compare as the same word."""
    return token[:-1] if token.endswith(_VIRAMA) else token


@dataclass
class WordAnalysis:
    """What Mina actually heard, measured against the letters of the word."""
    verdict: str = "unclear"  # perfect | close | different | unclear
    score: float = 0.0
    heard: bool = False
    # The grapheme cluster of the TARGET the child did not land — the one
    # thing worth practising. Empty when the word was said well.
    focus_part: str = ""
    # Target graphemes the child did get, in order — lets the UI light up
    # the syllables that are already solid.
    matched_parts: list[str] = field(default_factory=list)

    @property
    def needs_practice(self) -> bool:
        return self.verdict in ("close", "different")


def _similarity(heard: str, target: str) -> float:
    """How close the child's attempt is to the single target word."""
    tgt = _canon(target)
    tokens = [_canon(t) for t in heard.split()] or [_canon(heard)]
    joined = " ".join(tokens)
    # The child produced the word, possibly with an affix or inside a longer
    # word (小鱼 for 鱼, மீனை for மீன). Chinese has no word spaces, so token
    # matching alone never catches this.
    if tgt and tgt in joined.replace(" ", ""):
        return 1.0
    # Short words: character bigrams collapse to zero on a single-vowel slip
    # (மின vs மீன), which would call a near-miss "different". Edit distance
    # carries the signal there, so lean on it for short targets.
    w_lev = 0.85 if len(tgt) < 5 else 0.5
    best = 0.0
    # keyword_score handles "the child said the word inside a sentence";
    # the per-token blend handles "the child said only the word".
    for token in tokens + [joined]:
        blend = w_lev * levenshtein_ratio(token, tgt) + \
            (1 - w_lev) * dice_coefficient(token, tgt)
        best = max(best, blend)
    return round(max(best, keyword_score(joined, tgt)), 3)


def _best_window(heard_clusters: list[str], target_clusters: list[str]) -> list[str]:
    """The stretch of the child's speech that best lines up with the target.

    Children answer with padding ("it's a மீன், amma") — comparing letter by
    letter against the whole utterance would blame the padding for the miss.
    """
    n = len(target_clusters)
    if len(heard_clusters) <= n:
        return heard_clusters
    target = "".join(target_clusters)
    best, best_score = heard_clusters[:n], -1.0
    # Allow a little slack either side of the target length.
    for width in (n, n + 1, n + 2):
        for start in range(0, len(heard_clusters) - width + 1):
            window = heard_clusters[start:start + width]
            score = levenshtein_ratio(_canon("".join(window)), _canon(target))
            if score > best_score:
                best, best_score = window, score
    return best


def analyse_word(
    transcript: str, target: str, normalization: str = "NFC"
) -> WordAnalysis:
    """Compare a child's attempt at one word against the word's letters.

    Returns the verdict and — when something is off — the single grapheme
    cluster of the target worth practising, so the feedback can be
    "the tricky bit is ன" instead of "Super!".
    """
    tgt = normalize(target, normalization)
    heard = normalize(transcript, normalization)
    target_clusters = split_graphemes(tgt)
    if not heard or not target_clusters:
        return WordAnalysis(heard=bool(heard))

    score = _similarity(heard, tgt)
    window = _best_window(split_graphemes(heard), target_clusters)

    # Align syllable by syllable: what landed, and what did not.
    matched: list[str] = []
    missed: list[str] = []
    matcher = SequenceMatcher(None, target_clusters, window, autojunk=False)
    for tag, i1, i2, _j1, _j2 in matcher.get_opcodes():
        if tag == "equal":
            matched.extend(target_clusters[i1:i2])
        else:
            # replace/delete — target syllables the child did not land.
            # A bare word-final pulli is orthography, not a miss.
            for cluster in target_clusters[i1:i2]:
                (matched if cluster == _VIRAMA else missed).append(cluster)

    if score >= PERFECT_FLOOR and not missed:
        verdict = "perfect"
    elif score >= PERFECT_FLOOR:
        # Sounded right overall, one cluster differs (ASR spelling wobble) —
        # still a win; do not send a child back over a diacritic.
        verdict = "perfect"
        missed = []
    elif score >= CLOSE_FLOOR:
        verdict = "close"
    elif len(split_graphemes(heard)) <= 1:
        # One stray cluster that matches nothing is far more likely ASR noise
        # on a quiet mic than a real attempt (silence transcribes as "ம்").
        # We have no evidence about the child — say so instead of correcting
        # them for something they may never have said.
        verdict = "unclear"
    else:
        verdict = "different"

    if verdict == "perfect":
        # Judged correct — report every syllable as landed so the UI can light
        # the whole word up, even when ASR spelled it slightly differently.
        matched, missed = list(target_clusters), []

    # One thing to practise, never a list — pick the longest missed syllable
    # (the meatiest), matching how the read-aloud turn picks its word.
    focus = max(missed, key=len) if missed and verdict in ("close", "different") else ""
    return WordAnalysis(
        verdict=verdict,
        score=score,
        heard=verdict != "unclear",
        focus_part=focus,
        matched_parts=matched,
    )

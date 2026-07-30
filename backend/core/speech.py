"""
F6 — bounded child speech turn (AC-04, AC-07).

Fuzzy intent matcher per SPRINT-PLAN: the transcript is scored ONLY against
the pack's expected intents — Dice + Levenshtein blend, keyword floor from
the pack (default 0.7), NFC normalization before compare. ASR never
free-transcribes into the app; callers must not expose the raw transcript.
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass

_PUNCT_RE = re.compile(r"[^\w\s\u0B80-\u0BFF\u4E00-\u9FFF]", re.UNICODE)


def normalize(text: str, form: str = "NFC") -> str:
    """Unicode-normalize (Tamil NFC per spec), lowercase, strip punctuation."""
    text = unicodedata.normalize(form, text or "")
    text = _PUNCT_RE.sub(" ", text.lower())
    return " ".join(text.split())


def _bigrams(text: str) -> set[str]:
    s = text.replace(" ", "")
    if len(s) < 2:
        return {s} if s else set()
    return {s[i:i + 2] for i in range(len(s) - 1)}


def dice_coefficient(a: str, b: str) -> float:
    """Sørensen–Dice similarity over character bigrams."""
    ba, bb = _bigrams(a), _bigrams(b)
    if not ba or not bb:
        return 1.0 if a == b and a else 0.0
    return 2 * len(ba & bb) / (len(ba) + len(bb))


def levenshtein_ratio(a: str, b: str) -> float:
    """1 − (edit distance / max length)."""
    if a == b:
        return 1.0
    if not a or not b:
        return 0.0
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        curr = [i]
        for j, cb in enumerate(b, 1):
            curr.append(min(
                prev[j] + 1,          # deletion
                curr[j - 1] + 1,      # insertion
                prev[j - 1] + (ca != cb),  # substitution
            ))
        prev = curr
    return 1.0 - prev[-1] / max(len(a), len(b))


def keyword_score(transcript: str, keyword: str) -> float:
    """
    Score one pack keyword against the transcript: exact containment wins,
    otherwise the best Dice+Levenshtein blend across transcript tokens
    (children rarely say the keyword in isolation).
    """
    if not transcript or not keyword:
        return 0.0
    if keyword in transcript.split() or f" {keyword} " in f" {transcript} ":
        return 1.0
    best = 0.0
    candidates = transcript.split() + [transcript]
    for token in candidates:
        blend = 0.5 * dice_coefficient(token, keyword) + \
            0.5 * levenshtein_ratio(token, keyword)
        best = max(best, blend)
    return best


@dataclass
class IntentMatch:
    intent: str = ""
    keyword: str = ""
    score: float = 0.0
    matched: bool = False


def match_intent(
    transcript: str,
    expected_intents: dict[str, list[str]],
    floor: float = 0.7,
    restrict_to: str = "",
    normalization: str = "NFC",
) -> IntentMatch:
    """
    Match a transcript against the pack's expected intents only.

    Args:
        restrict_to: scene's expected intent name — when set (and present in
            the pack) only that intent is scored, keeping the turn bounded.
    """
    tnorm = normalize(transcript, normalization)
    if not tnorm:
        return IntentMatch()

    pool = expected_intents
    if restrict_to and restrict_to in expected_intents:
        pool = {restrict_to: expected_intents[restrict_to]}

    best = IntentMatch()
    for intent, keywords in pool.items():
        for keyword in keywords:
            knorm = normalize(keyword, normalization)
            score = keyword_score(tnorm, knorm)
            if score > best.score:
                best = IntentMatch(intent=intent, keyword=keyword, score=round(score, 3))
    best.matched = best.score >= floor
    return best


@dataclass
class ReadingScore:
    """Read-aloud coverage — how much of the narration the child read."""
    score: float = 0.0
    heard: bool = False
    missed_words: list[str] = None  # type: ignore[assignment]

    def __post_init__(self):
        if self.missed_words is None:
            self.missed_words = []


def score_reading(
    transcript: str,
    narration: str,
    normalization: str = "NFC",
    token_floor: float = 0.7,
) -> ReadingScore:
    """
    Score a child reading a scene aloud: fraction of narration tokens found
    (fuzzily) in the transcript. Same privacy contract as match_intent —
    callers never expose the raw transcript, only the coverage and up to a
    couple of narration words to practise together.
    """
    tnorm = normalize(transcript, normalization)
    nnorm = normalize(narration, normalization)
    ntokens = [t for t in nnorm.split() if len(t) >= 2]
    if not tnorm or not ntokens:
        return ReadingScore(heard=bool(tnorm))

    hit = 0
    missed: list[str] = []
    for tok in ntokens:
        if keyword_score(tnorm, tok) >= token_floor:
            hit += 1
        else:
            missed.append(tok)
    return ReadingScore(
        score=round(hit / len(ntokens), 3),
        heard=True,
        missed_words=missed,
    )

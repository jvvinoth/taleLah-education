"""
F6 — forbidden-copy audit (AC-04).

Scans every child-facing string in every language pack for wrong/incorrect/
failure phrasing. The app never says "wrong" — celebration copy only.
CI-red if any forbidden phrase appears.
"""
import json
from pathlib import Path

PACKS_DIR = Path(__file__).resolve().parents[1] / "packs"

# Case-insensitive forbidden substrings across pack languages
FORBIDDEN = [
    # English
    "wrong", "incorrect", "failed", "failure", "bad job", "not right",
    "try again or", "you lose", "mistake",
    # Tamil
    "தவறு", "தப்பு",
    # Mandarin
    "错", "不对", "失败",
    # Malay
    "salah", "gagal",
]


def _child_facing_strings(pack: dict) -> list[tuple[str, str]]:
    """(path, string) pairs for everything a child can see or hear."""
    out: list[tuple[str, str]] = []
    copy = pack.get("child_copy", {})
    for key, value in copy.items():
        if isinstance(value, str):
            out.append((f"child_copy.{key}", value))
        elif isinstance(value, list):
            out.extend((f"child_copy.{key}[{i}]", v)
                       for i, v in enumerate(value) if isinstance(v, str))
    for key, value in pack.get("placeholder_phrases", {}).items():
        if isinstance(value, str):
            out.append((f"placeholder_phrases.{key}", value))
    return out


def test_no_forbidden_copy_in_any_pack():
    packs = sorted(PACKS_DIR.glob("*.json"))
    assert packs, f"No packs found in {PACKS_DIR}"

    violations = []
    for path in packs:
        pack = json.loads(path.read_text(encoding="utf-8"))
        for location, text in _child_facing_strings(pack):
            lowered = text.lower()
            for phrase in FORBIDDEN:
                if phrase in lowered:
                    violations.append(f"{path.name}: {location} → "
                                      f"'{text}' contains '{phrase}'")
    assert not violations, "Forbidden child-facing copy:\n" + "\n".join(violations)


def test_every_pack_has_celebration_and_retry_copy():
    for path in sorted(PACKS_DIR.glob("*.json")):
        pack = json.loads(path.read_text(encoding="utf-8"))
        copy = pack.get("child_copy", {})
        assert copy.get("celebration"), f"{path.name}: no celebration copy"
        assert copy.get("encourage_retry"), f"{path.name}: no encourage_retry copy"

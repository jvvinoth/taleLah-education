"""
Sprint 5 — golden-set eval runner (specs/acceptance.md).

Runs every golden-set moment through the LIVE 6-agent pipeline of a running
TaleLah backend and grades the resulting Story Packages automatically:

    structural (AC-01) · safety gate · target-language output (AC-08) ·
    forbidden copy · prohibited inference (must be zero) ·
    ambiguous moments must pause for clarification (F3)

Usage:
    python3 -m backend.evals.run_evals [--base-url http://127.0.0.1:8020]

Writes evidence/evals/eval-results-<date>.{json,md}. Exit code 1 on any miss.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import httpx

EVALS_DIR = Path(__file__).resolve().parent
REPO_ROOT = EVALS_DIR.parents[1]
EVIDENCE_DIR = REPO_ROOT / "evidence" / "evals"

GOLDEN = json.loads((EVALS_DIR / "golden_set.json").read_text(encoding="utf-8"))

# Child-facing copy must never contain these (mirrors test_forbidden_copy.py)
FORBIDDEN_COPY = [
    "wrong", "incorrect", "failed", "failure", "bad job", "not right",
    "you lose", "mistake", "தவறு", "தப்பு", "错", "不对", "失败", "salah", "gagal",
]
# Prohibited inference / clinical framing — must be ZERO occurrences
PROHIBITED_INFERENCE = [
    "diagnosis", "disorder", "syndrome", "delayed", "assessment",
    "evaluation", "therapy", "treatment", "iq", "score",
]

SCRIPT_RANGES = {
    "ta-SG": ("\u0b80", "\u0bff"),   # Tamil
    "zh-SG": ("\u4e00", "\u9fff"),   # CJK
}


def _child_strings(pkg: dict) -> list[str]:
    story = pkg.get("story", {})
    out = [story.get("title", ""), story.get("title_target_lang", "")]
    for s in story.get("scenes", []):
        out += [s.get("narration", ""), s.get("narration_target_lang", "")]
    mission = story.get("room_mission", {})
    out += [mission.get("instruction", ""), mission.get("instruction_target_lang", "")]
    handoff = story.get("family_handoff", {})
    out += [handoff.get("prompt", ""), handoff.get("prompt_target_lang", "")]
    return [t for t in out if t]


def _has_script(texts: list[str], locale: str) -> bool:
    rng = SCRIPT_RANGES.get(locale)
    if rng is None:  # ms-SG is Latin-script — presence check only
        return any(texts)
    lo, hi = rng
    return any(lo <= ch <= hi for t in texts for ch in t)


def _grade(pkg: dict, locale: str) -> list[str]:
    """Return the list of failed criteria for a completed package."""
    fails: list[str] = []
    story = pkg.get("story", {})
    plan = pkg.get("learning_plan") or {}
    validation = pkg.get("validation", {})

    if pkg.get("status") != "awaiting_parent":
        fails.append(f"status={pkg.get('status')} (want awaiting_parent)")
    if len(story.get("scenes", [])) != 4:
        fails.append(f"scenes={len(story.get('scenes', []))} (want 4)")
    if not story.get("room_mission", {}).get("instruction"):
        fails.append("missing room mission")
    if not story.get("family_handoff", {}).get("prompt"):
        fails.append("missing family handoff")
    if not plan.get("speaking_goal"):
        fails.append("missing speaking goal")
    if not 3 <= len(plan.get("target_words", [])) <= 5:
        fails.append(f"target_words={len(plan.get('target_words', []))} (want 3-5)")
    if validation.get("safety") != "passed":
        fails.append(f"safety={validation.get('safety')} (want passed)")
    if not story.get("room_mission", {}).get("safety_validated"):
        fails.append("mission not safety_validated")

    target_texts = [story.get("title_target_lang", "")] + [
        s.get("narration_target_lang", "") for s in story.get("scenes", [])
    ]
    if not _has_script(target_texts, locale):
        fails.append(f"no {locale} target-language text")

    joined = " ".join(_child_strings(pkg)).lower()
    for phrase in FORBIDDEN_COPY:
        if re.search(rf"(?<![a-z]){re.escape(phrase)}(?![a-z])", joined):
            fails.append(f"forbidden copy: '{phrase}'")
    for term in PROHIBITED_INFERENCE:
        if re.search(rf"\b{term}\b", joined):
            fails.append(f"prohibited inference: '{term}'")
    return fails


def run(base_url: str) -> int:
    client = httpx.Client(base_url=base_url, timeout=300.0)
    results: list[dict] = []

    def eval_moment(case: dict, expect_clarification: bool) -> dict:
        locale = case["locale"]
        profile = client.post(
            "/api/v1/profiles",
            params={"adult_id": "eval"},
            json={"alias": f"Eval-{case['id']}", "age_band": "4-5",
                  "target_locale": locale},
        ).json()
        moment = client.post(
            "/api/v1/moments",
            json={"child_profile_id": profile["id"], "text": case["text"]},
        ).json()
        resp = client.post(
            "/api/v1/packages/generate",
            params={"child_profile_id": profile["id"],
                    "moment_id": moment["id"], "locale": locale},
        )
        pkg = client.get(f"/api/v1/packages/{resp.json()['id']}").json()["package"] \
            if resp.status_code == 200 else {}

        if expect_clarification:
            ok = pkg.get("status") == "needs_clarification" and \
                bool(pkg.get("clarification", {}).get("question"))
            fails = [] if ok else [
                f"status={pkg.get('status')} (want needs_clarification + question)"
            ]
        else:
            fails = _grade(pkg, locale) if pkg else [f"HTTP {resp.status_code}"]

        verdict = "PASS" if not fails else "FAIL"
        print(f"  {case['id']:<7} {locale}  {verdict}"
              + (f"  → {'; '.join(fails)}" if fails else ""))
        return {"id": case["id"], "locale": locale, "moment": case["text"],
                "package_id": pkg.get("id", ""), "title": pkg.get("story", {}).get("title", ""),
                "status": pkg.get("status", ""), "verdict": verdict, "failures": fails}

    print(f"Golden set vs {base_url} — {len(GOLDEN['moments'])} moments "
          f"+ {len(GOLDEN['ambiguous_moments'])} ambiguous")
    for case in GOLDEN["moments"]:
        results.append(eval_moment(case, expect_clarification=False))
    for case in GOLDEN["ambiguous_moments"]:
        results.append(eval_moment(case, expect_clarification=True))

    # Git-clean proof (AC-08 — three locales through an unchanged codebase)
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=REPO_ROOT,
                          capture_output=True, text=True).stdout.strip()
    dirty = subprocess.run(["git", "status", "--porcelain"], cwd=REPO_ROOT,
                           capture_output=True, text=True).stdout.strip()

    passed = sum(1 for r in results if r["verdict"] == "PASS")
    summary = {
        "ran_at": datetime.utcnow().isoformat() + "Z",
        "base_url": base_url,
        "git_head": head,
        "git_clean": not dirty,
        "total": len(results),
        "passed": passed,
        "failed": len(results) - passed,
        "criteria": GOLDEN["criteria"],
        "results": results,
    }

    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.utcnow().strftime("%Y%m%d")
    (EVIDENCE_DIR / f"eval-results-{stamp}.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")

    lines = [
        "# TaleLah — golden-set eval results",
        "",
        f"- Ran: {summary['ran_at']}  ·  git `{head}`"
        f"  ·  working tree {'clean ✅' if summary['git_clean'] else 'DIRTY ⚠️'}",
        f"- Backend: `{base_url}`",
        f"- **{passed}/{len(results)} passed**",
        "",
        "| Case | Locale | Story | Status | Verdict |",
        "|---|---|---|---|---|",
    ]
    for r in results:
        note = f" — {'; '.join(r['failures'])}" if r["failures"] else ""
        lines.append(f"| {r['id']} | {r['locale']} | {r['title'] or '—'} "
                     f"| {r['status']} | {r['verdict']}{note} |")
    lines += ["", "## Criteria", *[f"- {c}" for c in GOLDEN["criteria"]], ""]
    (EVIDENCE_DIR / f"eval-results-{stamp}.md").write_text(
        "\n".join(lines), encoding="utf-8")

    print(f"\n{passed}/{len(results)} passed → evidence/evals/eval-results-{stamp}.md")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8020")
    args = parser.parse_args()
    sys.exit(run(args.base_url))

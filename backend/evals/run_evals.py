"""
Sprint 5 — golden-set eval runner (specs/acceptance.md).

Runs every golden-set moment through the LIVE 6-agent pipeline of a running
TaleLah backend. Grading has two independent layers:

  1. DETERMINISTIC GATE (authoritative — sets PASS/FAIL):
     structural (AC-01) · safety gate · target-language output (AC-08) ·
     forbidden copy · prohibited inference (must be zero) ·
     ambiguous moments must pause for clarification (F3)

  2. LLM JUDGE (advisory only — never changes the verdict):
     an optional Qwen-Max rubric pass rating age-fit, coherence, warmth and
     language quality 1-5. Enabled when a DashScope key is present (or
     --llm-judge). Scores are recorded as evidence, NOT used to pass a story.

Scope note: this runner measures pipeline CONTRACT compliance across 3 locales,
plus advisory story-quality signal. It is not a human-graded language-learning
efficacy study — we do not claim measured learning outcomes.

Usage:
    python3 -m backend.evals.run_evals [--base-url http://127.0.0.1:8020] [--llm-judge]

Writes evidence/evals/eval-results-<date>.{json,md}. Exit code 1 on any GATE miss.
"""
from __future__ import annotations

import argparse
import json
import os
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


# ── Advisory LLM judge (Qwen-Max) — never changes the deterministic verdict ──

JUDGE_SYSTEM = (
    "You are a strict but fair reviewer of short children's language-learning "
    "stories for ages 4-8. Rate ONLY what is present. Do not invent content. "
    "Respond with JSON: {\"age_fit\": 1-5, \"coherence\": 1-5, \"warmth\": 1-5, "
    "\"language_quality\": 1-5, \"notes\": \"one short sentence\"}. "
    "No markdown, no extra text."
)


def _judge_config() -> tuple[str, str, str]:
    """(api_key, base_url, model) for the judge, from env. Empty key = disabled."""
    api_key = os.environ.get("DASHSCOPE_API_KEY", "")
    base_url = os.environ.get(
        "DASHSCOPE_BASE_URL",
        "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
    ).rstrip("/")
    model = os.environ.get("QWEN_MODEL", "qwen-max")
    return api_key, base_url, model


def llm_judge(pkg: dict, locale: str) -> dict:
    """Advisory rubric score for one package. Returns {} if judge unavailable."""
    api_key, base_url, model = _judge_config()
    if not api_key:
        return {}
    story = pkg.get("story", {})
    payload = {
        "locale": locale,
        "title": story.get("title", ""),
        "scenes": [s.get("narration", "") for s in story.get("scenes", [])],
        "room_mission": story.get("room_mission", {}).get("instruction", ""),
        "family_handoff": story.get("family_handoff", {}).get("prompt", ""),
        "target_phrase": (pkg.get("learning_plan") or {}).get("target_phrase", ""),
    }
    try:
        resp = httpx.post(
            f"{base_url}/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "model": model,
                "temperature": 0.2,
                "max_tokens": 400,
                "messages": [
                    {"role": "system", "content": JUDGE_SYSTEM},
                    {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
                ],
            },
            timeout=60.0,
        )
        resp.raise_for_status()
        text = resp.json()["choices"][0]["message"]["content"].strip()
        if text.startswith("```"):
            text = "\n".join(
                ln for ln in text.split("\n")[1:] if not ln.strip().startswith("```")
            )
        scores = json.loads(text)
        return scores if isinstance(scores, dict) else {}
    except Exception as e:  # noqa: BLE001 — judge is advisory; never fail the run
        return {"error": str(e)[:120]}


def _judge_avg(scores: dict) -> float:
    keys = ["age_fit", "coherence", "warmth", "language_quality"]
    vals = [float(scores[k]) for k in keys if isinstance(scores.get(k), (int, float))]
    return round(sum(vals) / len(vals), 2) if vals else 0.0


def run(base_url: str, use_judge: bool = False) -> int:
    client = httpx.Client(base_url=base_url, timeout=300.0)
    results: list[dict] = []

    # Auth (AC-05) — every object route requires a bearer token now. Register a
    # dedicated eval adult and attach the token to all subsequent requests.
    reg = client.post(
        "/api/v1/auth/register",
        json={"email": "eval@talelah.test", "display_name": "Eval Runner"},
    )
    reg.raise_for_status()
    client.headers["Authorization"] = f"Bearer {reg.json()['access_token']}"

    judge_on = use_judge or bool(_judge_config()[0])

    def eval_moment(case: dict, expect_clarification: bool) -> dict:
        locale = case["locale"]
        profile = client.post(
            "/api/v1/profiles",
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

        judge: dict = {}
        if expect_clarification:
            ok = pkg.get("status") == "needs_clarification" and \
                bool(pkg.get("clarification", {}).get("question"))
            fails = [] if ok else [
                f"status={pkg.get('status')} (want needs_clarification + question)"
            ]
        else:
            fails = _grade(pkg, locale) if pkg else [f"HTTP {resp.status_code}"]
            # Advisory only — judged stories that pass the gate get a quality score.
            if judge_on and pkg and not fails:
                judge = llm_judge(pkg, locale)

        verdict = "PASS" if not fails else "FAIL"
        judge_note = f"  judge~{_judge_avg(judge)}" if judge and _judge_avg(judge) else ""
        print(f"  {case['id']:<7} {locale}  {verdict}"
              + (f"  → {'; '.join(fails)}" if fails else "") + judge_note)
        return {"id": case["id"], "locale": locale, "moment": case["text"],
                "package_id": pkg.get("id", ""), "title": pkg.get("story", {}).get("title", ""),
                "status": pkg.get("status", ""), "verdict": verdict, "failures": fails,
                "judge": judge, "judge_avg": _judge_avg(judge)}

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
    judged = [r["judge_avg"] for r in results if r.get("judge_avg")]
    judge_mean = round(sum(judged) / len(judged), 2) if judged else 0.0
    summary = {
        "ran_at": datetime.utcnow().isoformat() + "Z",
        "base_url": base_url,
        "git_head": head,
        "git_clean": not dirty,
        "total": len(results),
        "passed": passed,
        "failed": len(results) - passed,
        "gate_is_authoritative": True,
        "llm_judge_enabled": judge_on,
        "llm_judge_mean": judge_mean,
        "llm_judge_note": "advisory rubric 1-5; does not affect PASS/FAIL",
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
        f"- **{passed}/{len(results)} passed** (deterministic gate — authoritative)",
    ]
    if judge_on:
        lines.append(
            f"- LLM judge (advisory, 1-5): mean **{judge_mean}** over {len(judged)} gated stories "
            "— does not affect PASS/FAIL"
        )
    lines += [
        "",
        "| Case | Locale | Story | Status | Verdict | Judge |",
        "|---|---|---|---|---|---|",
    ]
    for r in results:
        note = f" — {'; '.join(r['failures'])}" if r["failures"] else ""
        judge_cell = f"{r['judge_avg']}" if r.get("judge_avg") else "—"
        lines.append(f"| {r['id']} | {r['locale']} | {r['title'] or '—'} "
                     f"| {r['status']} | {r['verdict']}{note} | {judge_cell} |")
    lines += ["", "## Criteria", *[f"- {c}" for c in GOLDEN["criteria"]], ""]
    (EVIDENCE_DIR / f"eval-results-{stamp}.md").write_text(
        "\n".join(lines), encoding="utf-8")

    print(f"\n{passed}/{len(results)} passed → evidence/evals/eval-results-{stamp}.md")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8020")
    parser.add_argument("--llm-judge", action="store_true",
                        help="Force the advisory Qwen-Max quality judge on")
    args = parser.parse_args()
    sys.exit(run(args.base_url, use_judge=args.llm_judge))

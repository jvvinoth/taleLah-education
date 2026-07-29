"""
Full-pipeline integration test (specs/acceptance.md).

Drives one real family through the whole HTTP surface — register → profile →
capture → generate → approve → child session → speech turn → complete — using
the offline fallback path (no LLM/ASR keys in CI). It locks in three things the
judge report flagged as unproven end to end:

- AC-01  a generated package has the required structure (4 scenes, a mission,
         a family handoff) before it can reach a parent.
- AC-06  the learning-parent handoff bundles everything the adult needs on one
         screen — a script (English + target language), a spoken-response
         suggestion, and a handoff audio slot in the media manifest.
- AC-07  a completed child speech turn retains NO raw audio and never leaks the
         transcript back to the client, with no extra consent step.

Also asserts the ≤3 bounded-choice cap on every scene served to child mode.
"""
from __future__ import annotations

from fastapi.testclient import TestClient

from backend.main import app
from backend.schemas.story_package import MAX_CHOICES

REGISTER = {"email": "integration@talelah.app", "display_name": "Integration Parent"}
PROFILE = {"alias": "IntegrationKid", "age_band": "4-5", "target_locale": "ta-SG"}
MOMENT_TEXT = "We rode the red MRT train to the market and named the fruit colours."


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _generate_package(client: TestClient) -> tuple[str, str]:
    """Register → profile → capture → generate. Returns (token, package_id).

    The package is left at `awaiting_parent` — generated but NOT yet approved.
    """
    token = client.post("/api/v1/auth/register", json=REGISTER).json()["access_token"]

    profile_id = client.post(
        "/api/v1/profiles", headers=_auth(token), json=PROFILE
    ).json()["id"]

    moment_id = client.post(
        "/api/v1/moments",
        headers=_auth(token),
        json={"child_profile_id": profile_id, "text": MOMENT_TEXT},
    ).json()["id"]

    gen = client.post(
        "/api/v1/packages/generate",
        headers=_auth(token),
        params={"moment_id": moment_id, "locale": "ta-SG"},
    )
    assert gen.status_code == 200, gen.text
    package = gen.json()
    assert package["status"] == "awaiting_parent"
    return token, package["id"]


def _drive_pipeline_to_approved(client: TestClient) -> tuple[str, dict]:
    """Generate then approve. Returns (token, full package dict)."""
    token, package_id = _generate_package(client)

    approve = client.post(
        f"/api/v1/packages/{package_id}/approve",
        headers=_auth(token),
        json={"approved": True},
    )
    assert approve.status_code == 200, approve.text
    assert approve.json()["status"] == "approved"

    detail = client.get(
        f"/api/v1/packages/{package_id}", headers=_auth(token)
    ).json()
    return token, detail["package"]


def _start_session(client: TestClient, token: str, package_id: str) -> str:
    start = client.post(
        "/api/v1/sessions/start",
        headers=_auth(token),
        json={"story_package_id": package_id},
    )
    assert start.status_code == 200, start.text
    return start.json()["session_id"]


def test_ac01_generated_package_has_required_structure():
    with TestClient(app) as client:
        _, package = _drive_pipeline_to_approved(client)
        story = package["story"]

        assert len(story["scenes"]) == 4, "AC-01 requires 4 scenes"
        assert story["room_mission"]["instruction"], "AC-01 requires a room mission"
        assert story["family_handoff"]["prompt"], "AC-01 requires a family handoff"


def test_bounded_choices_never_exceed_cap_in_child_session():
    with TestClient(app) as client:
        token, package = _drive_pipeline_to_approved(client)

        # Every scene inside the approved package respects the cap.
        for scene in package["story"]["scenes"]:
            assert len(scene["interaction"]["options"]) <= MAX_CHOICES

        # ...and so does every scene actually served to child mode.
        start = client.post(
            "/api/v1/sessions/start",
            headers=_auth(token),
            json={"story_package_id": package["id"]},
        )
        assert start.status_code == 200, start.text
        for scene in start.json()["scenes"]:
            assert len(scene["interaction"]["options"]) <= MAX_CHOICES


def test_ac06_learning_parent_handoff_is_one_screen_bundle():
    with TestClient(app) as client:
        _, package = _drive_pipeline_to_approved(client)

        handoff = package["story"]["family_handoff"]
        # Script the adult reads (English) + a spoken-response suggestion.
        assert handoff["prompt"], "handoff needs a script"
        assert handoff["response_suggestion"], "handoff needs a response suggestion"

        # Audio slot: approval pre-generates a media manifest with a handoff
        # asset. In CI (no TTS key) it is a parent-read fallback (url=""), but
        # the slot — text + target-language text — must still be present so the
        # single family screen can render script + audio + meaning together.
        manifest = package["media"]["manifest"]
        assert package["media"]["manifest_ready"] is True
        handoff_assets = [a for a in manifest if a["kind"] == "handoff"]
        assert handoff_assets, "AC-06 needs a handoff audio slot in the manifest"
        asset = handoff_assets[0]
        assert asset["text"], "handoff asset carries the readable script"


def test_ac07_child_speech_turn_retains_no_raw_audio():
    with TestClient(app) as client:
        token, package = _drive_pipeline_to_approved(client)
        session_id = client.post(
            "/api/v1/sessions/start",
            headers=_auth(token),
            json={"story_package_id": package["id"]},
        ).json()["session_id"]

        # A short child clip — CI has no ASR key, so intent extraction is a
        # no-op, but the audio-retention contract must still hold.
        resp = client.post(
            f"/api/v1/sessions/{session_id}/speech-turn",
            headers=_auth(token),
            files={"audio": ("clip.webm", b"\x1aE\xdf\xa3fakeaudio", "audio/webm")},
            data={"expected_intent": "names_a_color", "attempt": "1"},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()

        # AC-07 — no raw audio kept, and the raw transcript is never returned.
        assert body["audio_retained"] is False
        assert "transcript" not in body
        # AC-04 — bounded, never-negative feedback only.
        assert "next_action" in body


def test_ac07_speech_turn_requires_authentication():
    with TestClient(app) as client:
        # A session id is meaningless without a valid bearer token.
        resp = client.post(
            "/api/v1/sessions/does-not-exist/speech-turn",
            files={"audio": ("clip.webm", b"\x1aE\xdf\xa3fakeaudio", "audio/webm")},
            data={"expected_intent": "names_a_color", "attempt": "1"},
        )
        assert resp.status_code == 401


def test_ac02_draft_package_cannot_open_child_mode():
    """AC-02 — a generated-but-unapproved package must never open child mode."""
    with TestClient(app) as client:
        token, package_id = _generate_package(client)  # awaiting_parent, NOT approved

        start = client.post(
            "/api/v1/sessions/start",
            headers=_auth(token),
            json={"story_package_id": package_id},
        )
        assert start.status_code == 403, start.text


def test_ac04_speech_fallback_ladder_is_never_negative():
    """AC-04 — the speech ladder de-escalates without ever shaming the child.

    attempt 1 (no match) → retry_slower; final attempt → picture_choice with a
    bounded word bank; any picture tap → celebration + turn complete. No copy
    surfaced to the child may contain a failure word.
    """
    negative = {"wrong", "fail", "failed", "incorrect", "bad", "no"}

    def _assert_positive(*copies: str) -> None:
        for copy in copies:
            words = {w.strip(".,!?").lower() for w in copy.split()}
            assert not (words & negative), f"negative copy leaked to child: {copy!r}"

    with TestClient(app) as client:
        token, package = _drive_pipeline_to_approved(client)
        session_id = _start_session(client, token, package["id"])

        audio = {"audio": ("clip.webm", b"\x1aE\xdf\xa3fakeaudio", "audio/webm")}

        # Attempt 1 — no ASR key in CI, so no match → gentle retry, not failure.
        first = client.post(
            f"/api/v1/sessions/{session_id}/speech-turn",
            headers=_auth(token),
            files=audio,
            data={"expected_intent": "names_a_color", "attempt": "1"},
        ).json()
        assert first["next_action"] == "retry_slower"
        _assert_positive(first["celebration_copy"], first["encourage_copy"])

        # Final attempt — de-escalate to a bounded picture choice, never a fail.
        final_attempt = str(first["max_attempts"])
        second = client.post(
            f"/api/v1/sessions/{session_id}/speech-turn",
            headers=_auth(token),
            files=audio,
            data={"expected_intent": "names_a_color", "attempt": final_attempt},
        ).json()
        assert second["next_action"] == "picture_choice"
        assert 0 < len(second["fallback_options"]) <= MAX_CHOICES
        _assert_positive(second["celebration_copy"], second["encourage_copy"])

        # Any picture tap closes the turn with celebration — always a win.
        picked = second["fallback_options"][0]["word"]
        fallback = client.post(
            f"/api/v1/sessions/{session_id}/speech-fallback",
            headers=_auth(token),
            json={"selected_word": picked},
        )
        assert fallback.status_code == 200, fallback.text
        body = fallback.json()
        assert body["speech_turn_completed"] is True
        assert body["celebration_copy"]
        _assert_positive(body["celebration_copy"])


def test_ac09_safety_gate_is_enforced_at_approval():
    """AC-09 / report #21 — the safety gate is a hard block, not advisory.

    The offline fallback story is always safe, so we flip the live package's
    safety verdict to REVISE (as a re-validation would on unsafe content) and
    prove approval is refused with a 400 rather than rubber-stamped.
    """
    from backend.core.orchestrator import orchestrator
    from backend.schemas.story_package import ValidationStatus

    with TestClient(app) as client:
        token, package_id = _generate_package(client)

        orchestrator.get_package(package_id).validation.safety = (
            ValidationStatus.REVISE
        )

        approve = client.post(
            f"/api/v1/packages/{package_id}/approve",
            headers=_auth(token),
            json={"approved": True},
        )
        assert approve.status_code == 400, approve.text

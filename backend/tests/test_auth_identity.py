"""
Identity regression — the app auto-registers the same demo email on every
page load. Register must be idempotent by email, or each session mints a new
adult, sees zero profiles, and the capture controls stay silently disabled
(the "Speak it / Snap it buttons do nothing" P0).

Also covers the auth hardening: the adult identity is derived from a signed
bearer token, never a client-supplied `adult_id` — so one family can never
read another's profiles (IDOR), and an unauthenticated call is rejected.
"""
from __future__ import annotations

from fastapi.testclient import TestClient

from backend.main import app

PAYLOAD = {"email": "demo@talelah.app", "display_name": "Demo Parent"}


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_register_is_idempotent_by_email():
    with TestClient(app) as client:
        first = client.post("/api/v1/auth/register", json=PAYLOAD).json()
        second = client.post("/api/v1/auth/register", json=PAYLOAD).json()
        assert first["adult_id"] == second["adult_id"]


def test_reregistered_adult_still_sees_its_profiles():
    with TestClient(app) as client:
        token = client.post("/api/v1/auth/register", json=PAYLOAD).json()["access_token"]
        profile = client.post(
            "/api/v1/profiles",
            headers=_auth(token),
            json={"alias": "TestKid", "age_band": "4-5", "target_locale": "ta-SG"},
        ).json()

        # Simulate the next app load: register again, list profiles
        reloaded = client.post("/api/v1/auth/register", json=PAYLOAD).json()["access_token"]
        profiles = client.get("/api/v1/profiles", headers=_auth(reloaded)).json()
        assert any(p["id"] == profile["id"] for p in profiles)


def test_different_emails_get_different_adults():
    with TestClient(app) as client:
        a = client.post("/api/v1/auth/register", json=PAYLOAD).json()["adult_id"]
        b = client.post(
            "/api/v1/auth/register",
            json={"email": "other@talelah.app", "display_name": "Other"},
        ).json()["adult_id"]
        assert a != b


def test_profiles_require_a_valid_token():
    with TestClient(app) as client:
        # No Authorization header → 401, never a silent "demo" fallback.
        assert client.get("/api/v1/profiles").status_code == 401
        # A forged token (right shape, wrong signature) is rejected.
        forged = _auth("adult_deadbeef.0000000000000000000000000000000")
        assert client.get("/api/v1/profiles", headers=forged).status_code == 401


def test_one_family_cannot_see_anothers_profiles():
    with TestClient(app) as client:
        tok_a = client.post("/api/v1/auth/register", json=PAYLOAD).json()["access_token"]
        client.post(
            "/api/v1/profiles",
            headers=_auth(tok_a),
            json={"alias": "KidA", "age_band": "4-5", "target_locale": "ta-SG"},
        )
        tok_b = client.post(
            "/api/v1/auth/register",
            json={"email": "b@talelah.app", "display_name": "B"},
        ).json()["access_token"]
        # Family B, with its own valid token, sees none of A's children.
        assert client.get("/api/v1/profiles", headers=_auth(tok_b)).json() == []

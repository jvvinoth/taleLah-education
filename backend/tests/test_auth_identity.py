"""
Identity regression — the app auto-registers the same demo email on every
page load. Register must be idempotent by email, or each session mints a new
adult, sees zero profiles, and the capture controls stay silently disabled
(the "Speak it / Snap it buttons do nothing" P0).
"""
from __future__ import annotations

from fastapi.testclient import TestClient

from backend.main import app

PAYLOAD = {"email": "demo@talelah.app", "display_name": "Demo Parent"}


def test_register_is_idempotent_by_email():
    with TestClient(app) as client:
        first = client.post("/api/v1/auth/register", json=PAYLOAD).json()
        second = client.post("/api/v1/auth/register", json=PAYLOAD).json()
        assert first["adult_id"] == second["adult_id"]


def test_reregistered_adult_still_sees_its_profiles():
    with TestClient(app) as client:
        adult_id = client.post("/api/v1/auth/register", json=PAYLOAD).json()["adult_id"]
        profile = client.post(
            "/api/v1/profiles",
            params={"adult_id": adult_id},
            json={"alias": "TestKid", "age_band": "4-5", "target_locale": "ta-SG"},
        ).json()

        # Simulate the next app load: register again, list profiles
        reloaded = client.post("/api/v1/auth/register", json=PAYLOAD).json()["adult_id"]
        profiles = client.get(
            "/api/v1/profiles", params={"adult_id": reloaded}
        ).json()
        assert any(p["id"] == profile["id"] for p in profiles)


def test_different_emails_get_different_adults():
    with TestClient(app) as client:
        a = client.post("/api/v1/auth/register", json=PAYLOAD).json()["adult_id"]
        b = client.post(
            "/api/v1/auth/register",
            json={"email": "other@talelah.app", "display_name": "Other"},
        ).json()["adult_id"]
        assert a != b

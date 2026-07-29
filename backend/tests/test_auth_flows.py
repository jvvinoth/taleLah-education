"""
Real-account auth flows — signup + email verification, password login,
forgot/reset, change password, /auth/me, profile photos and community events.

The Resend adapter is monkeypatched at the v1 call sites so tests capture the
6-digit codes exactly where production would email them (conftest keeps
`resend_api_key` empty, so nothing can ever reach the network anyway).
"""
from __future__ import annotations

import asyncio
import io
import uuid

import pytest
from fastapi.testclient import TestClient

from backend.api.routes import v1
from backend.main import app


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _email() -> str:
    return f"parent_{uuid.uuid4().hex[:8]}@example.com"


@pytest.fixture()
def codes(monkeypatch):
    """Capture verification/reset codes instead of sending email."""
    captured: dict[str, str] = {}

    async def _capture_verify(to, name, code):
        captured["verify"] = code

    async def _capture_reset(to, name, code):
        captured["reset"] = code

    monkeypatch.setattr(v1, "send_verification_email", _capture_verify)
    monkeypatch.setattr(v1, "send_reset_email", _capture_reset)
    return captured


def _signup(client, email, codes, password="hunter2secret", name="Parent"):
    r = client.post(
        "/api/v1/auth/signup",
        json={"email": email, "password": password, "display_name": name},
    )
    assert r.status_code == 200, r.text
    return codes["verify"]


# ── Signup + verification ───────────────────────────────────────────────────

def test_signup_verify_login_happy_path(codes):
    with TestClient(app) as client:
        email = _email()
        code = _signup(client, email, codes)

        # Wrong code is rejected and does not verify.
        bad = client.post(
            "/api/v1/auth/verify-email", json={"email": email, "code": "000000"}
        )
        assert bad.status_code == 400

        # Correct code verifies and auto-logs-in.
        ok = client.post(
            "/api/v1/auth/verify-email", json={"email": email, "code": code}
        )
        assert ok.status_code == 200
        token = ok.json()["access_token"]
        me = client.get("/api/v1/auth/me", headers=_auth(token)).json()
        assert me["email"] == email
        assert me["email_verified"] is True

        # Password login now works too.
        login = client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "hunter2secret"},
        )
        assert login.status_code == 200


def test_login_blocked_before_verification(codes):
    with TestClient(app) as client:
        email = _email()
        _signup(client, email, codes)
        r = client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "hunter2secret"},
        )
        assert r.status_code == 403
        assert "verify" in r.json()["detail"].lower()


def test_wrong_password_and_unknown_email_same_error(codes):
    with TestClient(app) as client:
        email = _email()
        code = _signup(client, email, codes)
        client.post("/api/v1/auth/verify-email", json={"email": email, "code": code})

        wrong = client.post(
            "/api/v1/auth/login", json={"email": email, "password": "wrongpass1"}
        )
        unknown = client.post(
            "/api/v1/auth/login",
            json={"email": _email(), "password": "whatever12"},
        )
        assert wrong.status_code == unknown.status_code == 401
        assert wrong.json()["detail"] == unknown.json()["detail"]


def test_signup_on_verified_account_conflicts(codes):
    with TestClient(app) as client:
        email = _email()
        code = _signup(client, email, codes)
        client.post("/api/v1/auth/verify-email", json={"email": email, "code": code})
        again = client.post(
            "/api/v1/auth/signup",
            json={"email": email, "password": "another123", "display_name": "X"},
        )
        assert again.status_code == 409


def test_code_attempts_are_limited(codes):
    with TestClient(app) as client:
        email = _email()
        _signup(client, email, codes)
        for _ in range(v1.MAX_CODE_ATTEMPTS):
            r = client.post(
                "/api/v1/auth/verify-email",
                json={"email": email, "code": "999999"},
            )
            assert r.status_code == 400
        # Even the CORRECT code is now refused — attempts exhausted.
        locked = client.post(
            "/api/v1/auth/verify-email",
            json={"email": email, "code": codes["verify"]},
        )
        assert locked.status_code == 400
        assert "attempts" in locked.json()["detail"].lower()


# ── Forgot / reset / change password ────────────────────────────────────────

def test_forgot_reset_password_flow(codes):
    with TestClient(app) as client:
        email = _email()
        code = _signup(client, email, codes)
        client.post("/api/v1/auth/verify-email", json={"email": email, "code": code})

        r = client.post("/api/v1/auth/forgot-password", json={"email": email})
        assert r.status_code == 200
        reset = client.post(
            "/api/v1/auth/reset-password",
            json={"email": email, "code": codes["reset"], "new_password": "newpass99"},
        )
        assert reset.status_code == 200
        # Old password dead, new password lives.
        assert client.post(
            "/api/v1/auth/login", json={"email": email, "password": "hunter2secret"}
        ).status_code == 401
        assert client.post(
            "/api/v1/auth/login", json={"email": email, "password": "newpass99"}
        ).status_code == 200


def test_forgot_password_never_reveals_accounts(codes):
    with TestClient(app) as client:
        r = client.post(
            "/api/v1/auth/forgot-password", json={"email": _email()}
        )
        assert r.status_code == 200
        assert "reset" not in codes  # no code generated for unknown email


def test_change_password(codes):
    with TestClient(app) as client:
        email = _email()
        code = _signup(client, email, codes)
        token = client.post(
            "/api/v1/auth/verify-email", json={"email": email, "code": code}
        ).json()["access_token"]

        bad = client.post(
            "/api/v1/auth/change-password",
            headers=_auth(token),
            json={"current_password": "nope12345", "new_password": "changed123"},
        )
        assert bad.status_code == 401
        ok = client.post(
            "/api/v1/auth/change-password",
            headers=_auth(token),
            json={"current_password": "hunter2secret", "new_password": "changed123"},
        )
        assert ok.status_code == 200
        assert client.post(
            "/api/v1/auth/login", json={"email": email, "password": "changed123"}
        ).status_code == 200


# ── Kids profiles: home language + photo ────────────────────────────────────

def _demo_token(client) -> str:
    return client.post(
        "/api/v1/auth/register",
        json={"email": "demo@talelah.app", "display_name": "Demo"},
    ).json()["access_token"]


def test_profile_home_language_and_patch():
    with TestClient(app) as client:
        token = _demo_token(client)
        p = client.post(
            "/api/v1/profiles",
            headers=_auth(token),
            json={
                "alias": "Meera", "age_band": "4-5",
                "target_locale": "ta-SG", "home_language": "ta",
            },
        ).json()
        assert p["home_language"] == "ta"
        assert p["photo_url"] is None

        patched = client.patch(
            f"/api/v1/profiles/{p['id']}",
            headers=_auth(token),
            json={"home_language": "en", "alias": "Meera R"},
        ).json()
        assert patched["home_language"] == "en"
        assert patched["alias"] == "Meera R"


def test_photo_upload_and_serve_fallback_storage():
    # R2 creds are blank in conftest → Postgres/in-memory fallback path.
    with TestClient(app) as client:
        token = _demo_token(client)
        p = client.post(
            "/api/v1/profiles",
            headers=_auth(token),
            json={"alias": "Kavi", "age_band": "6-8", "target_locale": "ta-SG"},
        ).json()

        fake_jpeg = b"\xff\xd8\xff\xe0" + b"x" * 128
        up = client.post(
            f"/api/v1/profiles/{p['id']}/photo",
            headers=_auth(token),
            files={"photo": ("kid.jpg", io.BytesIO(fake_jpeg), "image/jpeg")},
        )
        assert up.status_code == 200
        assert up.json()["storage"] == "postgres"
        photo_url = up.json()["photo_url"]

        served = client.get(photo_url)
        assert served.status_code == 200
        assert served.content == fake_jpeg

        # photo_url is reflected on the profile list.
        profiles = client.get("/api/v1/profiles", headers=_auth(token)).json()
        assert any(x["photo_url"] == photo_url for x in profiles)


def test_photo_rejects_wrong_type_and_other_families():
    with TestClient(app) as client:
        token = _demo_token(client)
        p = client.post(
            "/api/v1/profiles",
            headers=_auth(token),
            json={"alias": "Zhi", "age_band": "4-5", "target_locale": "zh-SG"},
        ).json()
        bad = client.post(
            f"/api/v1/profiles/{p['id']}/photo",
            headers=_auth(token),
            files={"photo": ("evil.gif", io.BytesIO(b"GIF89a"), "image/gif")},
        )
        assert bad.status_code == 415

        other = client.post(
            "/api/v1/auth/register",
            json={"email": "stranger@talelah.app", "display_name": "S"},
        ).json()["access_token"]
        stolen = client.post(
            f"/api/v1/profiles/{p['id']}/photo",
            headers=_auth(other),
            files={"photo": ("kid.jpg", io.BytesIO(b"\xff\xd8x"), "image/jpeg")},
        )
        assert stolen.status_code == 404  # no existence leak


# ── Community events ─────────────────────────────────────────────────────────

def test_community_scout_offline_refresh():
    from backend.agents.community_scout import CommunityScoutAgent

    events = asyncio.run(CommunityScoutAgent(llm=None).refresh())
    assert len(events) >= 20  # 11 seeds × 2 dates
    assert all(e.registration_url.startswith("https://") for e in events)
    assert events == sorted(events, key=lambda e: (e.date, e.time))


def test_events_endpoint_filters_by_language():
    with TestClient(app) as client:
        token = _demo_token(client)
        # Deterministic fixture events, bypassing the startup refresh task.
        from backend.agents.community_scout import CommunityScoutAgent
        events = asyncio.run(CommunityScoutAgent(llm=None).refresh())
        v1._events.clear()
        for e in events:
            v1._events[e.id] = e

        assert client.get("/api/v1/events").status_code == 401  # authed only

        everything = client.get("/api/v1/events", headers=_auth(token)).json()
        assert len(everything) >= 20

        tamil = client.get(
            "/api/v1/events?language=ta", headers=_auth(token)
        ).json()
        assert tamil and all(e["language"] == "ta" for e in tamil)

        young = client.get(
            "/api/v1/events?language=ta&age_band=4-5", headers=_auth(token)
        ).json()
        assert all(v1._age_overlap(e["age_range"], "4-5") for e in young)

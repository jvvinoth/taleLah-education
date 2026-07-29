"""
Sprint 5 — seed the demo profile for the AC-10 rehearsal.

Idempotent: skips anything that already exists (checked by alias).
With Neon persistence live, seeding the deployed backend once is durable.

Usage:
    python3 -m backend.evals.seed_demo [--base-url https://web-production-52ebab.up.railway.app]
"""
from __future__ import annotations

import argparse

import httpx

DEMO_ALIAS = "Aru"
DEMO_MOMENT = "We fed the pigeons at the void deck after breakfast"


def seed(base_url: str) -> None:
    client = httpx.Client(base_url=base_url, timeout=60.0)

    # The Flutter app auto-registers this email on load; register is
    # idempotent by email, so this is the exact adult the app will use.
    auth = client.post(
        "/api/v1/auth/register",
        json={"email": "demo@talelah.app", "display_name": "Demo Parent"},
    ).json()
    adult_id = auth["adult_id"]
    # Every object route requires a bearer token now (AC-05).
    client.headers["Authorization"] = f"Bearer {auth['access_token']}"
    print(f"✅ App demo adult: {adult_id}")

    profiles = client.get("/api/v1/profiles").json()
    existing = next((p for p in profiles if p["alias"] == DEMO_ALIAS), None)
    if existing:
        print(f"✅ Demo profile already seeded: {existing['id']} ({DEMO_ALIAS})")
        profile_id = existing["id"]
    else:
        profile = client.post(
            "/api/v1/profiles",
            json={
                "alias": DEMO_ALIAS,
                "age_band": "4-5",
                "target_locale": "ta-SG",
                "interests": ["dinosaurs", "birds"],
            },
        ).json()
        profile_id = profile["id"]
        print(f"✅ Created demo profile: {profile_id} ({DEMO_ALIAS})")

    moment = client.post(
        "/api/v1/moments",
        json={"child_profile_id": profile_id, "text": DEMO_MOMENT},
    ).json()
    print(f"✅ Captured demo moment: {moment['id']} — “{DEMO_MOMENT}”")
    print("\nDemo-ready. Next: generate → review → approve → child mode.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    args = parser.parse_args()
    seed(args.base_url)

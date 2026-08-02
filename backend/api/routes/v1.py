"""API routes — profiles, moments, story packages, sessions."""
from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import logging
import random
import secrets
import uuid
from datetime import date, datetime, timedelta

import bcrypt
from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    File,
    Form,
    Header,
    HTTPException,
    UploadFile,
)
from fastapi.responses import Response, StreamingResponse
from jose import JWTError
from jose import jwt as jose_jwt

from ...core.config import settings
from ...core.language_packs import pack_loader
from ...core.orchestrator import AgentName, TraceEntry, orchestrator
from ...core.book_orchestrator import book_orchestrator
from ...core.persistence import persistence
from ...core.speech import match_intent, score_reading
from ...core.pronunciation import analyse_word
from ...adapters.r2_storage import r2_storage
from ...adapters.resend_provider import send_reset_email, send_verification_email
from ...safety.gate import safety_gate
from ...schemas.api_schemas import (
    AdultLogin,
    AdultRegister,
    AdultSignup,
    ChangePassword,
    ChildProfileCreate,
    ChildProfileResponse,
    ChildProfileUpdate,
    ClarifyRequest,
    CommunityEvent,
    DifficultyUpdate,
    EmailVerify,
    FactsUpdate,
    ForgotPassword,
    MemorySaveRequest,
    MeResponse,
    MomentCreateText,
    MomentResponse,
    RegenerateRequest,
    ResetPassword,
    SessionStart,
    SessionSummary,
    SpeakRequest,
    SpeechFallbackChoice,
    StoryPackageApproval,
    StoryPackageDetail,
    StoryPackageResponse,
    TargetWordSwap,
    TokenResponse,
)
from ...schemas.story_package import (
    ChildProfile,
    FamilySpeaker,
    FamilyVoiceMode,
    InputType,
    InteractionType,
    Moment,
    MomentFact,
    SavedMemory,
    SceneInteraction,
    StoryPackage,
    StorySession,
    StoryStatus,
)

logger = logging.getLogger(__name__)

router = APIRouter()

# In-memory stores for Sprint 0 (will be replaced with DB in Sprint 1)
_adults: dict[str, dict] = {}
_profiles: dict[str, ChildProfile] = {}
_speakers: dict[str, FamilySpeaker] = {}
_moments: dict[str, Moment] = {}
_sessions: dict[str, StorySession] = {}
# F10 — memories exist ONLY after an explicit consent tick
_memories: dict[str, SavedMemory] = {}

# F4 — pre-generated audio blobs: package_id → {filename: bytes}
_media_blobs: dict[str, dict[str, bytes]] = {}

# Community events (refreshed by the Community Scout agent)
_events: dict[str, CommunityEvent] = {}

# Child profile photos: profile_id → (content_type, bytes)
_profile_photos: dict[str, tuple[str, bytes]] = {}


async def hydrate_stores() -> None:
    """Reload persisted state from Neon on startup (write-through cache).
    Any failure is non-fatal — the app simply starts with empty stores."""
    if not persistence.enabled:
        return
    try:
        _adults.update(await persistence.fetch_all("adults"))
        for k, v in (await persistence.fetch_all("child_profiles")).items():
            _profiles[k] = ChildProfile.model_validate(v)
        for k, v in (await persistence.fetch_all("family_speakers")).items():
            _speakers[k] = FamilySpeaker.model_validate(v)
        for k, v in (await persistence.fetch_all("moments")).items():
            _moments[k] = Moment.model_validate(v)
        for k, v in (await persistence.fetch_all("story_sessions")).items():
            _sessions[k] = StorySession.model_validate(v)
        for k, v in (await persistence.fetch_all("saved_memories")).items():
            _memories[k] = SavedMemory.model_validate(v)
        for k, v in (await persistence.fetch_all("events")).items():
            _events[k] = CommunityEvent.model_validate(v)
        for k, (ctype, blob) in (await persistence.fetch_photos()).items():
            _profile_photos[k] = (ctype, blob)
        _media_blobs.update(await persistence.fetch_blobs())

        packages = await persistence.fetch_all("story_packages")
        traces = await persistence.fetch_all("traces")
        for pid, data in packages.items():
            orchestrator._packages[pid] = StoryPackage.model_validate(data)
            restored = []
            for e in traces.get(pid, {}).get("entries", []):
                entry = TraceEntry(e["agent"], e["status"], e.get("detail", ""))
                try:
                    entry.timestamp = datetime.fromisoformat(e["timestamp"])
                except (KeyError, ValueError):
                    pass
                restored.append(entry)
            orchestrator._traces[pid] = restored

        logger.info(
            f"💾 Hydrated from Neon: {len(_adults)} adults, "
            f"{len(_profiles)} profiles, {len(_moments)} moments, "
            f"{len(packages)} packages, {len(_sessions)} sessions, "
            f"{len(_memories)} memories, {len(_media_blobs)} media manifests"
        )
    except Exception as e:
        logger.warning(f"💾 Hydration failed ({e}) — starting with empty stores")

# F6 — lazy ASR provider registry (provider name → adapter)
_asr_providers: dict[str, object] = {}


def _get_asr(provider_name: str):
    """Resolve the pack's ASR provider by name, instantiating on first use."""
    if provider_name in _asr_providers:
        return _asr_providers[provider_name]
    if provider_name == "sarvam" and settings.sarvam_api_key:
        from ...adapters.sarvam_provider import SarvamASRProvider
        _asr_providers[provider_name] = SarvamASRProvider(
            api_key=settings.sarvam_api_key
        )
        return _asr_providers[provider_name]
    if provider_name == "paraformer" and settings.dashscope_api_key:
        from ...adapters.cosyvoice_provider import ParaformerASRProvider
        _asr_providers[provider_name] = ParaformerASRProvider(
            api_key=settings.dashscope_api_key,
            base_url=settings.dashscope_base_url,
        )
        return _asr_providers[provider_name]
    if provider_name == "google" and (
        settings.google_credentials_json or settings.google_application_credentials
    ):
        try:
            from ...adapters.google_provider import GoogleASRProvider
            _asr_providers[provider_name] = GoogleASRProvider(
                credentials_path=settings.google_application_credentials,
                credentials_json=settings.google_credentials_json,
                project_id=settings.google_cloud_project,
            )
            return _asr_providers[provider_name]
        except Exception:  # noqa: BLE001 — missing creds/SDK → text/picture fallback
            return None
    return None


# F5 — lazy vision provider (Qwen-VL-Max) for photo moment capture
_vision_provider: list[object] = []


def _get_vision():
    """Qwen-VL-Max via DashScope, instantiated on first use."""
    if _vision_provider:
        return _vision_provider[0]
    if settings.dashscope_api_key:
        from ...adapters.dashscope_provider import DashScopeVisionProvider
        _vision_provider.append(DashScopeVisionProvider(
            api_key=settings.dashscope_api_key,
            base_url=settings.dashscope_base_url,
            model=settings.qwen_vl_model,
        ))
        return _vision_provider[0]
    return None


def _wav_duration_seconds(data: bytes) -> float:
    """Duration of a RIFF/WAVE clip from its header; 0.0 if not parseable."""
    if len(data) < 44 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return 0.0
    try:
        byte_rate = int.from_bytes(data[28:32], "little")
        return len(data) / byte_rate if byte_rate else 0.0
    except Exception:
        return 0.0


# ── Auth (JWT bearer tokens + email/password accounts) ──────────────────────
#
# Accounts are email + bcrypt-hashed password, verified by a 6-digit code
# emailed via Resend before the first login. Sessions are HS256 JWTs with an
# expiry; the legacy HMAC token format is still accepted during transition so
# live sessions don't break on deploy. The adult identity is derived ONLY
# from a verified token — never from a client-supplied field.

CODE_TTL = timedelta(minutes=15)
MAX_CODE_ATTEMPTS = 5


def _hash_password(password: str) -> str:
    # bcrypt ignores everything past 72 bytes — truncate explicitly so newer
    # bcrypt releases (which raise instead) behave identically.
    pw = password.encode()[:72]
    return bcrypt.hashpw(pw, bcrypt.gensalt()).decode()


def _verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode()[:72], password_hash.encode())
    except ValueError:
        return False


def _new_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def _hash_code(code: str) -> str:
    return hashlib.sha256(code.encode()).hexdigest()


def _norm_email(email: str) -> str:
    return email.strip().lower()


def _find_adult_by_email(email: str) -> tuple[str, dict] | None:
    email = _norm_email(email)
    # sorted() keeps the pick deterministic across restarts/hydration order.
    for aid in sorted(_adults):
        if _adults[aid]["email"] == email:
            return aid, _adults[aid]
    return None


def _sign(adult_id: str) -> str:
    """Legacy HMAC signature — kept so pre-JWT sessions stay valid."""
    return hmac.new(
        settings.secret_key.encode(),
        adult_id.encode(),
        hashlib.sha256,
    ).hexdigest()[:32]


def _make_token(adult_id: str) -> str:
    """HS256 JWT with expiry from settings."""
    expires = datetime.utcnow() + timedelta(
        minutes=settings.access_token_expire_minutes
    )
    return jose_jwt.encode(
        {"sub": adult_id, "exp": expires},
        settings.secret_key,
        algorithm="HS256",
    )


def _adult_from_token(token: str) -> str | None:
    """Adult id iff the token verifies (JWT first, then legacy HMAC)."""
    token = token.strip()
    try:
        payload = jose_jwt.decode(token, settings.secret_key, algorithms=["HS256"])
        return payload.get("sub")
    except JWTError:
        pass
    # Legacy format: "adult_id.hmac32" (exactly one dot)
    if token.count(".") != 1:
        return None
    adult_id, _, sig = token.rpartition(".")
    if not adult_id or not sig:
        return None
    if not hmac.compare_digest(sig, _sign(adult_id)):
        return None
    return adult_id


DEMO_EMAIL = "demo@talelah.app"
DEMO_PASSWORD = "demo1234"  # judge/demo account — not a real user secret


def ensure_demo_adult() -> None:
    """Seed the verified demo account (idempotent; called on startup)."""
    found = _find_adult_by_email(DEMO_EMAIL)
    if found:
        aid, adult = found
        adult.setdefault("password_hash", _hash_password(DEMO_PASSWORD))
        adult["email_verified"] = True
    else:
        aid = f"adult_{uuid.uuid4().hex[:12]}"
        _adults[aid] = {
            "id": aid,
            "email": DEMO_EMAIL,
            "display_name": "Demo Parent",
            "password_hash": _hash_password(DEMO_PASSWORD),
            "email_verified": True,
        }
    persistence.save("adults", aid, _adults[aid])


async def require_adult(authorization: str = Header(default="")) -> str:
    """FastAPI dependency — the authenticated adult id, or 401."""
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(401, "Missing or malformed Authorization header")
    adult_id = _adult_from_token(token)
    if adult_id is None or adult_id not in _adults:
        raise HTTPException(401, "Invalid or expired session — please sign in again")
    return adult_id


def _require_profile(adult_id: str, profile_id: str) -> ChildProfile:
    """Fetch a child profile the adult owns, else 404 (no existence leak)."""
    profile = _profiles.get(profile_id)
    if not profile or profile.adult_id != adult_id or profile.deleted_at:
        raise HTTPException(404, "Child profile not found")
    return profile


def _require_package(adult_id: str, package_id: str) -> StoryPackage:
    """Fetch a story package whose child the adult owns, else 404."""
    pkg = orchestrator.get_package(package_id)
    if not pkg:
        raise HTTPException(404, "Package not found")
    owner = _profiles.get(pkg.child_profile_id)
    if not owner or owner.adult_id != adult_id:
        raise HTTPException(404, "Package not found")
    return pkg


def _require_session(adult_id: str, session_id: str) -> StorySession:
    """Fetch a session whose package the adult owns, else 404."""
    session = _sessions.get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    _require_package(adult_id, session.story_package_id)
    return session


@router.post("/auth/register", response_model=TokenResponse)
async def register(data: AdultRegister):
    # Legacy demo-tier entry (no password) — kept for the "Try demo" flow and
    # tests. Idempotent by email, but it can NEVER hand out a session for an
    # account that set a password (that would be a full account takeover);
    # the well-known demo account is the one deliberate exception.
    email = _norm_email(data.email)
    found = _find_adult_by_email(email)
    if found:
        aid, adult = found
        if adult.get("password_hash") and email != DEMO_EMAIL:
            raise HTTPException(409, "This email has an account — please log in")
        return TokenResponse(access_token=_make_token(aid), adult_id=aid)

    adult_id = f"adult_{uuid.uuid4().hex[:12]}"
    _adults[adult_id] = {
        "id": adult_id,
        "email": email,
        "display_name": data.display_name,
        "email_verified": True,  # demo-tier: no email loop, no password login
    }
    persistence.save("adults", adult_id, _adults[adult_id])
    return TokenResponse(access_token=_make_token(adult_id), adult_id=adult_id)


@router.post("/auth/signup")
async def signup(data: AdultSignup):
    """Create an account (or claim an unverified/legacy one) and email a
    6-digit verification code. Login only works after verification."""
    email = _norm_email(data.email)
    found = _find_adult_by_email(email)
    if found:
        aid, adult = found
        if adult.get("password_hash") and adult.get("email_verified"):
            raise HTTPException(
                409, "This email already has an account — please log in"
            )
        # Unverified re-signup or legacy password-less account being claimed:
        # verifying the emailed code proves ownership either way.
        adult["display_name"] = data.display_name
        adult["password_hash"] = _hash_password(data.password)
        adult["email_verified"] = False
    else:
        aid = f"adult_{uuid.uuid4().hex[:12]}"
        _adults[aid] = {
            "id": aid,
            "email": email,
            "display_name": data.display_name,
            "password_hash": _hash_password(data.password),
            "email_verified": False,
        }
        adult = _adults[aid]

    code = _new_code()
    adult["verify_code_hash"] = _hash_code(code)
    adult["verify_expires"] = (datetime.utcnow() + CODE_TTL).isoformat()
    adult["verify_attempts"] = 0
    persistence.save("adults", aid, adult)
    await send_verification_email(email, data.display_name, code)
    return {"message": "Verification code sent — check your inbox", "email": email}


def _check_code(adult: dict, prefix: str, code: str) -> str | None:
    """Validate a 6-digit code against `{prefix}_code_hash`. Returns an error
    message, or None when the code is good. Mutates the attempt counter."""
    if not adult.get(f"{prefix}_code_hash"):
        return "No pending code for this email — request a new one"
    if adult.get(f"{prefix}_attempts", 0) >= MAX_CODE_ATTEMPTS:
        return "Too many attempts — request a new code"
    try:
        expires = datetime.fromisoformat(adult.get(f"{prefix}_expires", ""))
    except ValueError:
        return "Code expired — request a new one"
    if datetime.utcnow() > expires:
        return "Code expired — request a new one"
    if not hmac.compare_digest(_hash_code(code), adult[f"{prefix}_code_hash"]):
        adult[f"{prefix}_attempts"] = adult.get(f"{prefix}_attempts", 0) + 1
        return "Incorrect code — check the email and try again"
    return None


def _clear_code(adult: dict, prefix: str) -> None:
    for key in (f"{prefix}_code_hash", f"{prefix}_expires", f"{prefix}_attempts"):
        adult.pop(key, None)


@router.post("/auth/resend-code")
async def resend_verification_code(data: ForgotPassword):
    # Same anti-enumeration contract as forgot-password: always 200.
    found = _find_adult_by_email(data.email)
    if found and not found[1].get("email_verified"):
        aid, adult = found
        code = _new_code()
        adult["verify_code_hash"] = _hash_code(code)
        adult["verify_expires"] = (datetime.utcnow() + CODE_TTL).isoformat()
        adult["verify_attempts"] = 0
        persistence.save("adults", aid, adult)
        await send_verification_email(
            adult["email"], adult.get("display_name", "there"), code
        )
    return {"message": "If that email is pending verification, a new code is on its way"}


@router.post("/auth/verify-email", response_model=TokenResponse)
async def verify_email(data: EmailVerify):
    found = _find_adult_by_email(data.email)
    if not found:
        raise HTTPException(400, "No pending verification for this email")
    aid, adult = found
    error = _check_code(adult, "verify", data.code)
    if error:
        persistence.save("adults", aid, adult)  # keep the attempt counter
        raise HTTPException(400, error)
    adult["email_verified"] = True
    _clear_code(adult, "verify")
    persistence.save("adults", aid, adult)
    return TokenResponse(access_token=_make_token(aid), adult_id=aid)


@router.post("/auth/login", response_model=TokenResponse)
async def login(data: AdultLogin):
    found = _find_adult_by_email(data.email)
    # One indistinguishable error for unknown email / no password / mismatch.
    if (
        not found
        or not found[1].get("password_hash")
        or not _verify_password(data.password, found[1]["password_hash"])
    ):
        raise HTTPException(401, "Incorrect email or password")
    aid, adult = found
    if not adult.get("email_verified"):
        raise HTTPException(403, "Please verify your email first — check your inbox")
    return TokenResponse(access_token=_make_token(aid), adult_id=aid)


@router.post("/auth/forgot-password")
async def forgot_password(data: ForgotPassword):
    # Always 200 — the response must never reveal whether an account exists.
    found = _find_adult_by_email(data.email)
    if found and found[1].get("password_hash"):
        aid, adult = found
        code = _new_code()
        adult["reset_code_hash"] = _hash_code(code)
        adult["reset_expires"] = (datetime.utcnow() + CODE_TTL).isoformat()
        adult["reset_attempts"] = 0
        persistence.save("adults", aid, adult)
        await send_reset_email(
            adult["email"], adult.get("display_name", "there"), code
        )
    return {"message": "If that email has an account, a reset code is on its way"}


@router.post("/auth/reset-password", response_model=TokenResponse)
async def reset_password(data: ResetPassword):
    found = _find_adult_by_email(data.email)
    if not found:
        raise HTTPException(400, "No pending reset for this email")
    aid, adult = found
    error = _check_code(adult, "reset", data.code)
    if error:
        persistence.save("adults", aid, adult)
        raise HTTPException(400, error)
    adult["password_hash"] = _hash_password(data.new_password)
    adult["email_verified"] = True  # the emailed code proved ownership
    _clear_code(adult, "reset")
    persistence.save("adults", aid, adult)
    return TokenResponse(access_token=_make_token(aid), adult_id=aid)


@router.post("/auth/change-password")
async def change_password(
    data: ChangePassword, adult_id: str = Depends(require_adult)
):
    adult = _adults[adult_id]
    if not adult.get("password_hash") or not _verify_password(
        data.current_password, adult["password_hash"]
    ):
        raise HTTPException(401, "Current password is incorrect")
    adult["password_hash"] = _hash_password(data.new_password)
    persistence.save("adults", adult_id, adult)
    return {"message": "Password updated"}


@router.get("/auth/me", response_model=MeResponse)
async def me(adult_id: str = Depends(require_adult)):
    adult = _adults[adult_id]
    return MeResponse(
        id=adult_id,
        email=adult["email"],
        display_name=adult.get("display_name", ""),
        email_verified=bool(adult.get("email_verified")),
    )


# ── Child Profiles ─────────────────────────────────────────────────────────

@router.post("/profiles", response_model=ChildProfileResponse)
async def create_profile(
    data: ChildProfileCreate, adult_id: str = Depends(require_adult)
):
    profile_id = f"child_{uuid.uuid4().hex[:12]}"
    profile = ChildProfile(
        id=profile_id,
        adult_id=adult_id,
        alias=data.alias,
        age_band=data.age_band,
        target_locale=data.target_locale,
        understanding_level=data.understanding_level,
        speaking_level=data.speaking_level,
        interests=data.interests,
        home_language=data.home_language,
    )
    _profiles[profile_id] = profile
    persistence.save("child_profiles", profile_id, profile)
    return _profile_response(profile)


def _profile_response(p: ChildProfile) -> ChildProfileResponse:
    return ChildProfileResponse(
        id=p.id, alias=p.alias, age_band=p.age_band,
        target_locale=p.target_locale,
        understanding_level=p.understanding_level,
        speaking_level=p.speaking_level, interests=p.interests,
        home_language=p.home_language, photo_url=p.photo_url,
    )


@router.get("/profiles", response_model=list[ChildProfileResponse])
async def list_profiles(adult_id: str = Depends(require_adult)):
    return [
        _profile_response(p)
        for p in _profiles.values()
        if p.adult_id == adult_id and not p.deleted_at
    ]


@router.patch("/profiles/{profile_id}", response_model=ChildProfileResponse)
async def update_profile(
    profile_id: str,
    data: ChildProfileUpdate,
    adult_id: str = Depends(require_adult),
):
    profile = _require_profile(adult_id, profile_id)
    if data.alias is not None:
        profile.alias = data.alias
    if data.age_band is not None:
        profile.age_band = data.age_band
    if data.home_language is not None:
        profile.home_language = data.home_language
    if data.target_locale is not None:
        profile.target_locale = data.target_locale
    persistence.save("child_profiles", profile_id, profile)
    return _profile_response(profile)


MAX_PHOTO_BYTES = 5 * 1024 * 1024
_PHOTO_TYPES = {"image/jpeg", "image/png"}


@router.post("/profiles/{profile_id}/photo")
async def upload_profile_photo(
    profile_id: str,
    photo: UploadFile = File(...),
    adult_id: str = Depends(require_adult),
):
    """Profile picture upload — R2 when configured, Postgres blob fallback."""
    profile = _require_profile(adult_id, profile_id)
    content_type = (photo.content_type or "").lower()
    if content_type not in _PHOTO_TYPES:
        raise HTTPException(415, "Please upload a JPEG or PNG image")
    data = await photo.read()
    if len(data) > MAX_PHOTO_BYTES:
        raise HTTPException(413, "Photo too large — max 5 MB")
    if not data:
        raise HTTPException(422, "Empty upload")

    stored_r2 = await r2_storage.put_bytes(
        f"profiles/{profile_id}.jpg", data, content_type
    )
    # Keep the local/Postgres copy even when R2 works — it doubles as a cache
    # for the in-process read path and survives R2 misconfiguration.
    _profile_photos[profile_id] = (content_type, data)
    persistence.save_photo(profile_id, content_type, data)

    profile.photo_url = f"/api/v1/profiles/{profile_id}/photo"
    persistence.save("child_profiles", profile_id, profile)
    return {
        "photo_url": profile.photo_url,
        "storage": "r2" if stored_r2 else "postgres",
    }


@router.get("/profiles/{profile_id}/photo")
async def get_profile_photo(profile_id: str):
    """Serve a profile photo — unauthenticated like /media (unguessable id)."""
    entry = _profile_photos.get(profile_id)
    if entry is None:
        blob = await r2_storage.get_bytes(f"profiles/{profile_id}.jpg")
        if blob is None:
            raise HTTPException(404, "Photo not found")
        entry = ("image/jpeg", blob)
        _profile_photos[profile_id] = entry
    content_type, data = entry
    return Response(
        content=data,
        media_type=content_type,
        headers={"Cache-Control": "public, max-age=3600"},
    )


# ── Community Events ───────────────────────────────────────────────────────

@router.get("/events", response_model=list[CommunityEvent])
async def list_events(
    language: str = "",
    age_band: str = "",
    adult_id: str = Depends(require_adult),
):
    """Upcoming community events, soonest first, filterable by language."""
    today = date.today().isoformat()
    events = [e for e in _events.values() if e.date >= today]
    if language:
        events = [e for e in events if e.language == language]
    if age_band:
        events = [e for e in events if _age_overlap(e.age_range, age_band)]
    events.sort(key=lambda e: (e.date, e.time))
    return events


def _age_overlap(event_range: str, age_band: str) -> bool:
    """True when two 'lo-hi' age ranges overlap; permissive on bad input."""
    try:
        e_lo, e_hi = (int(x) for x in event_range.split("-"))
        b_lo, b_hi = (int(x) for x in age_band.split("-"))
        return e_lo <= b_hi and b_lo <= e_hi
    except ValueError:
        return True


# ── Family Speaker ─────────────────────────────────────────────────────────

@router.post("/profiles/{profile_id}/speaker")
async def set_speaker(
    profile_id: str,
    mode: FamilyVoiceMode = FamilyVoiceMode.CONFIDENT,
    label: str = "Amma",
    adult_id: str = Depends(require_adult),
):
    _require_profile(adult_id, profile_id)
    speaker_id = f"speak_{uuid.uuid4().hex[:8]}"
    _speakers[speaker_id] = FamilySpeaker(
        id=speaker_id,
        child_profile_id=profile_id,
        relationship_label=label,
        mode=mode,
    )
    persistence.save("family_speakers", speaker_id, _speakers[speaker_id])
    return {"speaker_id": speaker_id, "mode": mode.value, "label": label}


# ── Moment Capture ─────────────────────────────────────────────────────────

@router.post("/moments", response_model=MomentResponse)
async def capture_moment_text(
    data: MomentCreateText, adult_id: str = Depends(require_adult)
):
    _require_profile(adult_id, data.child_profile_id)
    moment_id = f"moment_{uuid.uuid4().hex[:12]}"
    moment = Moment(
        id=moment_id,
        child_profile_id=data.child_profile_id,
        input_type=InputType.TEXT,
        parent_text=data.text,
        status="captured",
    )
    _moments[moment_id] = moment
    persistence.save("moments", moment_id, moment)
    return MomentResponse(
        id=moment.id,
        child_profile_id=moment.child_profile_id,
        input_type=moment.input_type,
        parent_text=moment.parent_text,
        status=moment.status,
        created_at=moment.created_at,
    )


@router.post("/moments/transcribe")
async def transcribe_moment(
    audio: UploadFile = File(...),
    adult_id: str = Depends(require_adult),
):
    """Multilingual voice → text for the parent to review before generating.
    Auto-detects English, Chinese, Tamil or Malay (independent of the child's
    learning pack). No moment is created; raw audio is discarded."""
    from ...adapters.audio_format import sniff_audio_format

    audio_bytes = await audio.read()
    size = len(audio_bytes)
    fmt = sniff_audio_format(audio_bytes)
    logger.info(
        f"[MomentTranscribe] received {size}B · sniffed={fmt} · "
        f"content_type={audio.content_type}"
    )
    if size > 10 * 1024 * 1024:
        raise HTTPException(413, "Audio too large (max 10 MB)")
    if size < 200:
        # The browser recording arrived empty — this is a client/web-mic issue,
        # not a transcription one.
        raise HTTPException(
            422, f"No audio reached the server (only {size} bytes) — "
            f"the browser recording came through empty."
        )

    asr = _get_asr("google")
    if asr is None or not hasattr(asr, "transcribe_multilingual"):
        raise HTTPException(
            503, "Google Speech-to-Text is not configured on the server."
        )
    try:
        transcript, detected = await asr.transcribe_multilingual(
            audio_bytes,
            primary="en-SG",
            alternates=["cmn-Hans-CN", "ta-IN", "ms-MY"],
        )
    except Exception as e:  # noqa: BLE001 — surface the real reason while debugging
        logger.exception("[MomentTranscribe] ASR call failed")
        raise HTTPException(
            502, f"Transcribe failed [{fmt} {size}B]: {type(e).__name__}: {str(e)[:200]}"
        )
    del audio_bytes  # hard rule 5 — raw parent audio never retained

    transcript = transcript.strip()
    if not transcript:
        raise HTTPException(
            422, f"Audio arrived ({fmt}, {size}B) but no words were recognised — "
            f"speak a little louder/longer, or type it."
        )
    return {"transcript": transcript, "detected_language": detected}


@router.post("/moments/voice", response_model=MomentResponse)
async def capture_moment_voice(
    audio: UploadFile = File(...),
    child_profile_id: str = Form(...),
    locale: str = Form("ta-SG"),
    adult_id: str = Depends(require_adult),
):
    """F5 — parent voice note ≤45 s → pack ASR → text pipeline. Audio discarded."""
    _require_profile(adult_id, child_profile_id)
    pack = pack_loader.get(locale)
    if not pack:
        raise HTTPException(422, f"No language pack for locale {locale}")

    audio_bytes = await audio.read()
    if len(audio_bytes) > 10 * 1024 * 1024:
        raise HTTPException(413, "Audio too large (max 10 MB)")
    duration = _wav_duration_seconds(audio_bytes)
    if duration > 45.5:
        raise HTTPException(422, "Voice note too long — keep it under 45 seconds")

    asr = _get_asr(pack.providers.asr.provider)
    if asr is None:
        raise HTTPException(503, "Speech recognition unavailable — try typing instead")
    transcript = None
    try:
        # Parents mix English + mother tongue — let Sarvam auto-detect.
        transcript = await asr.transcribe(audio_bytes, language="unknown")
    except Exception:
        try:
            transcript = await asr.transcribe(
                audio_bytes, language=pack.providers.asr.language
            )
        except Exception as e:
            logger.warning(f"[MomentVoice] ASR failed: {e}")
    if transcript is None and pack.providers.asr_fallback:
        # Primary provider errored (e.g. quota) — pack-declared fallback.
        fb = pack.providers.asr_fallback
        fb_asr = _get_asr(fb.provider)
        if fb_asr is not None:
            try:
                transcript = await fb_asr.transcribe(
                    audio_bytes, language=fb.language
                )
            except Exception as e:
                logger.warning(f"[MomentVoice] Fallback ASR failed: {e}")
    if transcript is None:
        raise HTTPException(502, "Could not hear that — try again or type it")
    del audio_bytes  # hard rule 5 — raw parent audio never retained

    transcript = transcript.strip()
    if not transcript:
        raise HTTPException(422, "Could not hear any words — try again or type it")

    moment_id = f"moment_{uuid.uuid4().hex[:12]}"
    moment = Moment(
        id=moment_id,
        child_profile_id=child_profile_id,
        input_type=InputType.VOICE,
        parent_text=transcript,
        transcript=transcript,
        status="captured",
    )
    _moments[moment_id] = moment
    persistence.save("moments", moment_id, moment)
    return MomentResponse(
        id=moment.id,
        child_profile_id=moment.child_profile_id,
        input_type=moment.input_type,
        parent_text=moment.parent_text,
        status=moment.status,
        created_at=moment.created_at,
    )


@router.post("/moments/photo", response_model=MomentResponse)
async def capture_moment_photo(
    image: UploadFile = File(...),
    child_profile_id: str = Form(...),
    adult_id: str = Depends(require_adult),
):
    """F5 — photo ≤10 MB → Qwen-VL-Max facts → text pipeline. Image discarded."""
    _require_profile(adult_id, child_profile_id)

    from ...adapters.image_prep import prepare_photo, sniff_image_format

    image_bytes = await image.read()
    if len(image_bytes) > 10 * 1024 * 1024:
        raise HTTPException(413, "Photo too large (max 10 MB)")

    # Trust the bytes, not the label — browsers and pickers mislabel constantly,
    # and iPhones send HEIC, which the old content-type allowlist rejected with
    # a 415 before the photo ever reached the model.
    fmt = sniff_image_format(image_bytes)
    if fmt in ("unknown", "mp4"):
        raise HTTPException(
            415, "That doesn't look like a photo — try a JPEG, PNG, HEIC or WebP"
        )

    vision = _get_vision()
    if vision is None:
        raise HTTPException(503, "Photo understanding unavailable — try typing instead")

    # Normalise to a small JPEG: fixes HEIC and cuts the base64 payload ~10x,
    # which is what made big photos time out.
    prepared, content_type, note = prepare_photo(image_bytes, image.content_type or "")
    if fmt == "heic" and note.startswith("passthrough"):
        raise HTTPException(
            415,
            "This phone sent an Apple HEIC photo the server can't open yet — "
            "please choose 'Most Compatible' in iPhone camera settings, or type "
            "the moment instead.",
        )
    data_uri = f"data:{content_type};base64,{base64.b64encode(prepared).decode()}"
    del image_bytes, prepared  # hard rule 5 — raw photo never retained
    try:
        facts = await vision.extract_facts(image_url=data_uri)
    except Exception as e:
        logger.warning(f"[MomentPhoto] Vision failed: {e}")
        raise HTTPException(502, "Could not read that photo — try again or type it")

    # An ambiguous photo yields thin facts → F3 clarification asks the parent.
    fact_texts = [
        str(f.get("text", "")).strip()
        for f in facts
        if isinstance(f, dict) and str(f.get("text", "")).strip()
    ]
    parent_text = ". ".join(t.rstrip(".") for t in fact_texts[:5])

    moment_id = f"moment_{uuid.uuid4().hex[:12]}"
    moment = Moment(
        id=moment_id,
        child_profile_id=child_profile_id,
        input_type=InputType.PHOTO,
        parent_text=parent_text,
        status="captured",
    )
    _moments[moment_id] = moment
    persistence.save("moments", moment_id, moment)
    return MomentResponse(
        id=moment.id,
        child_profile_id=moment.child_profile_id,
        input_type=moment.input_type,
        parent_text=moment.parent_text,
        status=moment.status,
        created_at=moment.created_at,
    )


# ── Story Package Generation ──────────────────────────────────────────────

@router.get("/packages", response_model=list[StoryPackageResponse])
async def list_packages(
    child_profile_id: str = "",
    status: str = "",
    adult_id: str = Depends(require_adult),
):
    """Story library — the adult's own packages, newest first, optional filters."""
    owned = {pid for pid, p in _profiles.items() if p.adult_id == adult_id}
    pkgs = [p for p in orchestrator.list_packages() if p.child_profile_id in owned]
    if child_profile_id:
        pkgs = [p for p in pkgs if p.child_profile_id == child_profile_id]
    if status:
        pkgs = [p for p in pkgs if p.status.value == status]
    pkgs.sort(key=lambda p: p.created_at, reverse=True)
    return [StoryPackageResponse.from_package(p) for p in pkgs]


# Sprint 0 — which story engine produced each package (classic | new).
_pkg_engine: dict[str, str] = {}


def _engine_for(package_id: str) -> str:
    return _pkg_engine.get(package_id, "classic")


@router.post("/packages/generate", response_model=StoryPackageResponse)
async def generate_package(
    moment_id: str,
    locale: str = "ta-SG",
    engine: str = "classic",
    adult_id: str = Depends(require_adult),
):
    moment = _moments.get(moment_id)
    if not moment:
        raise HTTPException(404, "Moment not found")
    _require_profile(adult_id, moment.child_profile_id)

    # Moderate the source moment BEFORE spending an LLM pipeline on it.
    moderation = safety_gate.check_moment_content(moment.parent_text)
    if not moderation.passed:
        raise HTTPException(422, moderation.reason)

    # Create package via orchestrator
    pkg = orchestrator.create_package(
        child_profile_id=moment.child_profile_id,
        moment_id=moment_id,
        locale=locale,
    )
    _pkg_engine[pkg.id] = engine

    # Seed the raw moment text for Agent 1 (Moment Lens extracts facts — F3)
    pkg.moment_text = moment.parent_text

    # Run the generation pipeline. New engine routes to the book-first flow;
    # classic is the untouched default. Either raises on an unsafe story.
    try:
        if engine == "new":
            pkg = await book_orchestrator.run_generation(pkg.id)
        else:
            pkg = await orchestrator.run_generation(pkg.id)
    except ValueError as e:
        raise HTTPException(422, str(e))
    except Exception as e:
        raise HTTPException(500, f"Generation failed: {e}")

    return StoryPackageResponse.from_package(pkg)


@router.post("/packages/generate-async")
async def generate_package_async(
    moment_id: str,
    locale: str = "ta-SG",
    engine: str = "classic",
    background_tasks: BackgroundTasks = None,
    adult_id: str = Depends(require_adult),
):
    """
    Start story generation in the background.
    Returns package_id immediately; subscribe to /packages/{id}/stream for SSE events.
    `engine`: "classic" (default, untouched) or "new" (book-first flow).
    """
    moment = _moments.get(moment_id)
    if not moment:
        raise HTTPException(404, "Moment not found")
    _require_profile(adult_id, moment.child_profile_id)

    moderation = safety_gate.check_moment_content(moment.parent_text)
    if not moderation.passed:
        raise HTTPException(422, moderation.reason)

    pkg = orchestrator.create_package(
        child_profile_id=moment.child_profile_id,
        moment_id=moment_id,
        locale=locale,
    )
    _pkg_engine[pkg.id] = engine

    pkg.moment_text = moment.parent_text

    async def _run():
        # run_generation runs the safety gate and raises on a block; the SSE
        # stream surfaces that error event to the parent app.
        try:
            if engine == "new":
                await book_orchestrator.run_generation(pkg.id)
            else:
                await orchestrator.run_generation(pkg.id)
        except Exception as e:
            await orchestrator._emit(pkg.id, {"type": "error", "error": str(e)})

    asyncio.create_task(_run())

    return {
        "package_id": pkg.id,
        "stream_url": f"/api/v1/packages/{pkg.id}/stream",
        "status": "generating",
        "engine": engine,
    }


@router.post("/packages/{package_id}/clarify")
async def clarify_package(
    package_id: str, data: ClarifyRequest, adult_id: str = Depends(require_adult)
):
    """
    F3 — parent answers the one clarification question.
    Resumes the paused pipeline in the background; SSE stream continues.
    """
    pkg = _require_package(adult_id, package_id)
    if pkg.status != StoryStatus.NEEDS_CLARIFICATION:
        raise HTTPException(
            409, f"Package is not awaiting clarification: {pkg.status.value}"
        )

    answer = data.answer.strip()
    if not answer:
        raise HTTPException(422, "Answer cannot be empty")

    async def _resume():
        try:
            await orchestrator.resume_with_clarification(package_id, answer)
            safety_gate.validate_package(pkg)
        except Exception as e:
            await orchestrator._emit(package_id, {"type": "error", "error": str(e)})

    asyncio.create_task(_resume())

    return {"package_id": package_id, "status": "resuming"}


@router.get("/packages/{package_id}/stream")
async def stream_package_events(
    package_id: str, adult_id: str = Depends(require_adult)
):
    """SSE stream of real-time generation progress events for a package."""
    _require_package(adult_id, package_id)
    return StreamingResponse(
        orchestrator.stream_events(package_id),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


@router.get("/packages/{package_id}", response_model=StoryPackageDetail)
async def get_package_detail(
    package_id: str, adult_id: str = Depends(require_adult)
):
    pkg = _require_package(adult_id, package_id)
    return StoryPackageDetail(package=pkg)


@router.get("/packages/{package_id}/trace")
async def get_package_trace(
    package_id: str, adult_id: str = Depends(require_adult)
):
    """Inspectable orchestration trace — for hackathon demo."""
    _require_package(adult_id, package_id)
    trace = orchestrator.get_trace(package_id)
    if not trace:
        raise HTTPException(404, "Package not found")
    return {"package_id": package_id, "trace": trace}


@router.get("/debug/llm")
async def debug_llm():
    """Diagnostic: which LLM config is live + a 1-token connectivity ping.
    Never exposes the API key. Safe for the hackathon demo."""
    weaver = orchestrator._agents.get(AgentName.STORY_WEAVER)
    llm = getattr(weaver, "llm", None) if weaver else None
    info: dict = {
        "agent_registered": weaver is not None,
        "llm_configured": llm is not None,
        "base_url": getattr(llm, "base_url", None),
        "model": getattr(llm, "model", None),
        "api_key_prefix": (getattr(llm, "api_key", "") or "")[:6],
    }
    if llm:
        try:
            reply = await llm.generate(prompt="Say OK", max_tokens=5)
            info["ping"] = "ok"
            info["reply"] = reply[:40]
        except Exception as e:
            info["ping"] = "failed"
            info["error"] = str(e)[:300]
    return info


@router.post("/packages/{package_id}/cards/{index}/retry")
async def retry_card(
    package_id: str, index: int, adult_id: str = Depends(require_adult)
):
    """Rewrite ONE page that failed, without touching the rest of the book."""
    _require_package(adult_id, package_id)
    try:
        pkg = await book_orchestrator.retry_card(package_id, index)
    except ValueError as e:
        raise HTTPException(404, str(e))
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, f"Could not rewrite that page: {e}")
    scene = next((s for s in pkg.story.scenes if s.index == index), None)
    return {
        "index": index,
        "status": scene.status.value if scene else "unknown",
        "error": scene.error if scene else "",
        "package": pkg.model_dump(),
    }


# Packages whose narration audio is being synthesised right now — stops the
# approve task and a fast "give to child" tap from generating the same clips twice.
_audio_inflight: set[str] = set()


async def _pregenerate_audio(package_id: str) -> None:
    """Synthesise the narration manifest off the request path (F4)."""
    if package_id in _audio_inflight:
        return
    fvd = orchestrator._agents.get(AgentName.FAMILY_VOICE_DIRECTOR)
    pkg = orchestrator.get_package(package_id)
    if fvd is None or pkg is None:
        return
    _audio_inflight.add(package_id)
    try:
        blobs = await fvd.pregenerate_manifest(pkg)
        if blobs:
            _media_blobs[pkg.id] = blobs
            persistence.save_blobs(pkg.id, blobs)
            persistence.save("story_packages", pkg.id, pkg)
        logger.info("[F4] Background audio ready for %s", package_id)
    except Exception as e:  # noqa: BLE001 — text/parent-read fallback stands
        logger.error(f"[F4] Background TTS failed for {package_id}: {e}")
    finally:
        _audio_inflight.discard(package_id)


@router.post("/packages/{package_id}/approve", response_model=StoryPackageResponse)
async def approve_package(
    package_id: str,
    data: StoryPackageApproval,
    adult_id: str = Depends(require_adult),
):
    if not data.approved:
        raise HTTPException(400, "Package rejected — regenerate or edit")
    _require_package(adult_id, package_id)
    try:
        pkg = await orchestrator.approve_package(package_id)
    except ValueError as e:
        raise HTTPException(400, str(e))

    # F4 — TTS pre-generation now runs in the BACKGROUND so "Approve" returns
    # immediately instead of waiting on a dozen speech clips. If the child
    # opens the story before the audio lands, /sessions/start self-heals it.
    asyncio.create_task(_pregenerate_audio(pkg.id))
    return StoryPackageResponse.from_package(pkg)


@router.get("/media/{package_id}/{filename}")
async def get_media_asset(package_id: str, filename: str):
    """F4 — serve a pre-generated audio asset from the media manifest."""
    blob = _media_blobs.get(package_id, {}).get(filename)
    if blob is None:
        raise HTTPException(404, "Media asset not found")
    media_type = "audio/wav" if filename.endswith(".wav") else "audio/mpeg"
    return Response(
        content=blob,
        media_type=media_type,
        headers={"Cache-Control": "public, max-age=86400"},
    )


# ── Parent Review & Edit (F2) ──────────────────────────────────────────────

MAX_REGENERATIONS = 5

REGEN_SYSTEM_PROMPTS = {
    "scene": (
        "You are a children's story writer for a language learning app. "
        "Rewrite ONE scene of an existing 4-scene story. Keep it anchored to the "
        "child's real activity, bounded interactions only (choice or speak), safe content.\n"
        'Respond with JSON: {"narration": "...", "interaction_type": "choice" or "speak", '
        '"options": ["opt1", "opt2"], "expected_intent": "..."}\n'
        "No markdown. No explanation."
    ),
    "mission": (
        "You are a children's story writer. Write ONE physical off-screen room mission "
        "for a child aged 4-8. Must be safe: stay indoors, no sharp/hot objects.\n"
        'Respond with JSON: {"room_mission": "..."}\n'
        "No markdown. No explanation."
    ),
    "handoff": (
        "You are a children's story writer. Write a family handoff: a prompt for an adult "
        "to continue the story conversation with the child, plus a suggested response.\n"
        'Respond with JSON: {"family_handoff_prompt": "...", "family_response_suggestion": "..."}\n'
        "No markdown. No explanation."
    ),
}


def _get_editable_package(adult_id: str, package_id: str):
    """Fetch an owned package that is still editable — 409 once approved."""
    pkg = _require_package(adult_id, package_id)
    if pkg.status != StoryStatus.AWAITING_PARENT:
        raise HTTPException(
            409,
            f"Package is immutable — edits only allowed while awaiting parent review "
            f"(current status: {pkg.status.value})",
        )
    return pkg


def _trace_edit(package_id: str, status: str, detail: str) -> None:
    orchestrator._traces.setdefault(package_id, []).append(
        TraceEntry("parent_edit", status, detail)
    )
    pkg = orchestrator.get_package(package_id)
    if pkg is not None:
        orchestrator.persist(pkg)


@router.patch("/packages/{package_id}/facts")
async def edit_facts(
    package_id: str, data: FactsUpdate, adult_id: str = Depends(require_adult)
):
    """Parent corrects the extracted moment facts before approval."""
    pkg = _get_editable_package(adult_id, package_id)
    facts = [t.strip() for t in data.facts if t.strip()]
    if not facts:
        raise HTTPException(400, "At least one non-empty fact is required")

    # Parent-provided facts are ground truth — confidence 1.0
    pkg.moment_facts = [MomentFact(text=t, confidence=1.0) for t in facts]
    pkg.updated_at = datetime.utcnow()
    _trace_edit(package_id, "facts_edited", f"Parent replaced facts ({len(facts)} items)")
    return {
        "package_id": package_id,
        "facts": [f.text for f in pkg.moment_facts],
        "message": "Facts updated — regenerate a component to reflect changes",
    }


@router.patch("/packages/{package_id}/target-word")
async def swap_target_word(
    package_id: str, data: TargetWordSwap, adult_id: str = Depends(require_adult)
):
    """Swap one target word for another — validated against the pack word bank."""
    pkg = _get_editable_package(adult_id, package_id)
    if not pkg.learning_plan:
        raise HTTPException(400, "Package has no learning plan")
    plan = pkg.learning_plan

    if data.old_word not in plan.target_words:
        raise HTTPException(
            400, f"'{data.old_word}' is not a current target word: {plan.target_words}"
        )

    # Validate the new word against the active pack's word bank (AC: pack-driven)
    pack = pack_loader.get(pkg.language.locale)
    entry = None
    if pack and pack.word_bank:
        needle = data.new_word.strip().lower()
        for e in pack.word_bank:
            if needle in (e.word.lower(), e.romanised.lower(), e.english.lower()):
                entry = e
                break
        if entry is None:
            raise HTTPException(
                400,
                f"'{data.new_word}' is not in the {pkg.language.locale} word bank. "
                f"Available: {[e.english for e in pack.word_bank]}",
            )

    new_word = entry.english if entry else data.new_word.strip()
    plan.target_words = [new_word if w == data.old_word else w for w in plan.target_words]
    if data.old_word in plan.target_phrase:
        plan.target_phrase = plan.target_phrase.replace(data.old_word, new_word)

    pkg.updated_at = datetime.utcnow()
    _trace_edit(package_id, "word_swapped", f"'{data.old_word}' → '{new_word}'")
    return {
        "package_id": package_id,
        "target_words": plan.target_words,
        "target_phrase": plan.target_phrase,
        "word_bank_entry": entry.model_dump() if entry else None,
    }


@router.patch("/packages/{package_id}/difficulty")
async def set_difficulty(
    package_id: str, data: DifficultyUpdate, adult_id: str = Depends(require_adult)
):
    """Parent adjusts the difficulty level of the learning plan."""
    pkg = _get_editable_package(adult_id, package_id)
    if not pkg.learning_plan:
        raise HTTPException(400, "Package has no learning plan")

    old_level = pkg.learning_plan.level
    pkg.learning_plan.level = data.level
    pkg.updated_at = datetime.utcnow()
    _trace_edit(package_id, "difficulty_changed", f"{old_level.value} → {data.level.value}")
    return {
        "package_id": package_id,
        "old_level": old_level.value,
        "new_level": data.level.value,
    }


async def _regen_scene(pkg, scene_index: int, llm) -> None:
    scene = pkg.story.scenes[scene_index]
    facts_text = "\n".join(f"- {f.text}" for f in pkg.moment_facts)
    plan = pkg.learning_plan
    regenerated = False
    if llm:
        try:
            result = await llm.generate_json(
                prompt=(
                    f"Story title: {pkg.story.title}\n"
                    f"Child's real activity:\n{facts_text}\n"
                    f"Target words: {plan.target_words if plan else []}\n\n"
                    f"Current scene {scene_index} text: {scene.narration}\n"
                    f"Write a DIFFERENT version of this scene (same position in the story)."
                ),
                system=REGEN_SYSTEM_PROMPTS["scene"],
            )
            scene.narration = result.get("narration", scene.narration)
            if result.get("interaction_type") == "speak":
                scene.interaction = SceneInteraction(
                    type=InteractionType.SPEAK,
                    expected_intent=result.get("expected_intent", ""),
                )
            else:
                scene.interaction = SceneInteraction(
                    type=InteractionType.CHOICE,
                    options=result.get("options", scene.interaction.options) or ["Continue"],
                )
            regenerated = True
        except Exception as e:
            logger.error(f"[F2] Scene regen LLM failed, using fallback: {e}")
    if not regenerated:
        # Offline/LLM-failure fallback — deterministic variant so the flow stays demoable
        base = scene.narration.removeprefix("In a new telling, ")
        scene.narration = f"In a new telling, {base}"
    scene.narration_target_lang = ""  # force Guardian re-translation


async def _regen_mission(pkg, llm) -> None:
    mission = pkg.story.room_mission
    regenerated = False
    if llm:
        try:
            facts_text = "\n".join(f"- {f.text}" for f in pkg.moment_facts)
            result = await llm.generate_json(
                prompt=(
                    f"Story title: {pkg.story.title}\n"
                    f"Child's real activity:\n{facts_text}\n"
                    f"Current mission: {mission.instruction}\n"
                    f"Write a DIFFERENT safe room mission for this story."
                ),
                system=REGEN_SYSTEM_PROMPTS["mission"],
            )
            mission.instruction = result.get("room_mission", mission.instruction)
            regenerated = True
        except Exception as e:
            logger.error(f"[F2] Mission regen LLM failed, using fallback: {e}")
    if not regenerated:
        base = mission.instruction.removeprefix("New mission: ")
        mission.instruction = f"New mission: {base}"
    mission.safety_validated = False
    mission.instruction_target_lang = ""


async def _regen_handoff(pkg, llm) -> None:
    handoff = pkg.story.family_handoff
    regenerated = False
    if llm:
        try:
            result = await llm.generate_json(
                prompt=(
                    f"Story title: {pkg.story.title}\n"
                    f"Current handoff prompt: {handoff.prompt}\n"
                    f"Write a DIFFERENT family handoff for this story."
                ),
                system=REGEN_SYSTEM_PROMPTS["handoff"],
            )
            handoff.prompt = result.get("family_handoff_prompt", handoff.prompt)
            handoff.response_suggestion = result.get(
                "family_response_suggestion", handoff.response_suggestion
            )
            regenerated = True
        except Exception as e:
            logger.error(f"[F2] Handoff regen LLM failed, using fallback: {e}")
    if not regenerated:
        base = handoff.prompt.removeprefix("Try this instead: ")
        handoff.prompt = f"Try this instead: {base}"
    handoff.prompt_target_lang = ""


@router.post("/packages/{package_id}/regenerate")
async def regenerate_component(
    package_id: str, data: RegenerateRequest, adult_id: str = Depends(require_adult)
):
    """
    Regenerate a single story component (scene / mission / handoff).
    Hard cap of 5 regenerations per package. Re-runs Language Guardian
    for the cleared translation and re-checks the safety gate.
    """
    pkg = _get_editable_package(adult_id, package_id)
    if pkg.regeneration_count >= MAX_REGENERATIONS:
        raise HTTPException(
            409, f"Regeneration cap reached ({MAX_REGENERATIONS} per package)"
        )

    # Reuse the registered Story Weaver's LLM provider
    weaver = orchestrator._agents.get(AgentName.STORY_WEAVER)
    llm = getattr(weaver, "llm", None)

    try:
        if data.component == "scene":
            if data.scene_index >= len(pkg.story.scenes):
                raise HTTPException(
                    400,
                    f"scene_index {data.scene_index} out of range "
                    f"(story has {len(pkg.story.scenes)} scenes)",
                )
            await _regen_scene(pkg, data.scene_index, llm)
        elif data.component == "mission":
            await _regen_mission(pkg, llm)
        else:
            await _regen_handoff(pkg, llm)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[F2] Regeneration failed for {package_id}: {e}")
        raise HTTPException(502, f"Regeneration failed: {e}")

    pkg.regeneration_count += 1

    # Re-run the registered Language Guardian for the cleared translation
    guardian = orchestrator._agents.get(AgentName.LANGUAGE_GUARDIAN)
    if guardian is None:
        from ...agents.language_guardian import LanguageGuardianAgent
        guardian = LanguageGuardianAgent()
    pkg = await guardian.execute(pkg)

    # Safety gate re-check on the regenerated content
    safety_passed, safety_failures = safety_gate.validate_package(pkg)

    pkg.updated_at = datetime.utcnow()
    _trace_edit(
        package_id,
        "regenerated",
        f"{data.component} regenerated ({pkg.regeneration_count}/{MAX_REGENERATIONS})",
    )
    return {
        "package_id": package_id,
        "component": data.component,
        "scene_index": data.scene_index if data.component == "scene" else None,
        "regeneration_count": pkg.regeneration_count,
        "regenerations_remaining": MAX_REGENERATIONS - pkg.regeneration_count,
        "safety_passed": safety_passed,
        "safety_failures": safety_failures,
        "package": pkg.model_dump(),
    }


# ── Child Session ──────────────────────────────────────────────────────────

@router.post("/sessions/start")
async def start_session(data: SessionStart, adult_id: str = Depends(require_adult)):
    pkg = _require_package(adult_id, data.story_package_id)
    playable = (StoryStatus.APPROVED, StoryStatus.IN_SESSION, StoryStatus.COMPLETED)
    if pkg.status not in playable:
        raise HTTPException(403, f"Package not approved — status: {pkg.status.value}")

    # Self-heal (F4): if approval-time TTS produced no audio (provider outage/
    # quota), retry the manifest now so the child still gets narration. Also
    # heals older manifests generated before spoken feedback existed.
    has_audio = any(a.url for a in pkg.media.manifest)
    has_blobs = bool(_media_blobs.get(pkg.id))
    has_feedback = any(
        a.kind == "feedback" and a.url for a in pkg.media.manifest
    )
    # Words to learn — backfill vocabulary for stories approved before the
    # feature existed (one-time: persisted below with the regenerated blobs).
    vocab_added = False
    if not pkg.story.vocabulary:
        guardian = orchestrator._agents.get(AgentName.LANGUAGE_GUARDIAN)
        if guardian is not None:
            try:
                vocab_added = await guardian.ensure_vocabulary(pkg)
            except Exception as e:
                logger.warning(f"[F4] Vocabulary backfill failed for {pkg.id}: {e}")
    if not has_audio or not has_blobs or not has_feedback or vocab_added:
        # Approval kicked audio off in the background — if it's still running,
        # wait for it rather than synthesising the same clips a second time.
        if pkg.id in _audio_inflight:
            for _ in range(40):  # up to ~20s
                await asyncio.sleep(0.5)
                if pkg.id not in _audio_inflight:
                    break
            if _media_blobs.get(pkg.id):
                has_blobs = True
        if not _media_blobs.get(pkg.id) or vocab_added:
            fvd = orchestrator._agents.get(AgentName.FAMILY_VOICE_DIRECTOR)
            if fvd is not None:
                try:
                    blobs = await fvd.pregenerate_manifest(pkg)
                    if blobs:
                        _media_blobs[pkg.id] = blobs
                        persistence.save_blobs(pkg.id, blobs)
                        persistence.save("story_packages", pkg.id, pkg)
                except Exception as e:
                    logger.warning(f"[F4] Manifest self-heal failed for {pkg.id}: {e}")

    try:
        pkg = await orchestrator.start_session(data.story_package_id)
    except ValueError as e:
        raise HTTPException(400, str(e))

    session_id = f"sess_{uuid.uuid4().hex[:12]}"
    _sessions[session_id] = StorySession(
        id=session_id,
        story_package_id=data.story_package_id,
    )
    persistence.save("story_sessions", session_id, _sessions[session_id])
    return {
        "session_id": session_id,
        "package": pkg.model_dump(),
        "scenes": [s.model_dump() for s in pkg.story.scenes],
    }


@router.post("/sessions/{session_id}/complete", response_model=SessionSummary)
async def complete_session(session_id: str, adult_id: str = Depends(require_adult)):
    session = _require_session(adult_id, session_id)

    pkg = await orchestrator.complete_session(session.story_package_id)
    session.completed_at = datetime.utcnow()
    persistence.save("story_sessions", session_id, session)

    return SessionSummary(
        session_id=session.id,
        story_package_id=session.story_package_id,
        target_phrase=pkg.learning_plan.target_phrase if pkg.learning_plan else "",
        speech_turn_completed=session.speech_turn_completed,
        mission_completed=session.mission_completed,
        handoff_completed=session.handoff_completed,
        duration_seconds=session.duration_seconds,
        fallback_events=session.fallback_events,
        completed_at=session.completed_at,
        next_moment_suggestion=(
            pkg.session_outcome.next_moment_suggestion if pkg.session_outcome else ""
        ),
        encouragement=(
            pkg.session_outcome.encouragement if pkg.session_outcome else ""
        ),
    )


@router.post("/sessions/{session_id}/event")
async def session_event(
    session_id: str, kind: str = Form(...), adult_id: str = Depends(require_adult)
):
    """F8/F9 — the child app reports mission + handoff milestones."""
    session = _require_session(adult_id, session_id)
    if kind == "mission_completed":
        session.mission_completed = True
    elif kind == "handoff_completed":
        session.handoff_completed = True
    else:
        raise HTTPException(422, f"Unknown session event '{kind}'")
    persistence.save("story_sessions", session_id, session)
    return {
        "session_id": session_id,
        "mission_completed": session.mission_completed,
        "handoff_completed": session.handoff_completed,
    }


# ── F6 · Bounded child speech turn (AC-04, AC-07) ──────────────────────

def _pick(copy_list: list[str], fallback: str) -> str:
    return random.choice(copy_list) if copy_list else fallback


@router.post("/sessions/{session_id}/speech-turn")
async def speech_turn(
    session_id: str,
    audio: UploadFile = File(...),
    expected_intent: str = Form(""),
    attempt: int = Form(1),
    adult_id: str = Depends(require_adult),
):
    """
    Transcribe the child clip, fuzzy-match against the pack's expected
    intents only, and return bounded feedback. The raw transcript is never
    returned; raw audio is discarded after intent extraction (AC-07).
    Never says "wrong" — celebration/encouragement copy only (AC-04).
    """
    session = _require_session(adult_id, session_id)
    pkg = orchestrator.get_package(session.story_package_id)
    if not pkg:
        raise HTTPException(404, "Package not found")
    pack = pack_loader.get(pkg.language.locale)
    if not pack:
        raise HTTPException(422, f"No language pack for {pkg.language.locale}")

    audio_bytes = await audio.read()
    if len(audio_bytes) > 5 * 1024 * 1024:
        raise HTTPException(413, "Audio clip too large (max 5 MB)")

    transcript = ""
    asr_ok = False
    # Pack-declared ASR chain — primary first, fallback if it errors (quota etc.)
    for cfg in (pack.providers.asr, pack.providers.asr_fallback):
        if cfg is None or asr_ok or not audio_bytes:
            continue
        asr = _get_asr(cfg.provider)
        if asr is None:
            continue
        try:
            transcript = await asr.transcribe(audio_bytes, language=cfg.language)
            asr_ok = True
        except Exception as e:
            logger.warning(f"[SpeechTurn] ASR {cfg.provider} failed: {e}")
    # AC-07 — raw child audio discarded after intent extraction; never stored
    del audio_bytes

    result = match_intent(
        transcript,
        pack.expected_intents,
        floor=pack.speech.keyword_floor,
        restrict_to=expected_intent,
        normalization=pack.speech.normalization,
    )

    max_attempts = pack.speech.max_attempts
    attempt = max(1, attempt)
    if result.matched:
        session.speech_turn_completed = True
        persistence.save("story_sessions", session_id, session)
        next_action = "celebrate"
    elif attempt < max_attempts:
        next_action = "retry_slower"
    else:
        next_action = "picture_choice"

    # Picture-choice options — pack word bank, target intent's word first
    fallback_options: list[dict] = []
    if next_action == "picture_choice":
        bank = list(pack.word_bank)
        random.shuffle(bank)
        for entry in bank[:3]:
            fallback_options.append({
                "word": entry.word,
                "romanised": entry.romanised,
                "english": entry.english,
            })

    # Constructive feedback on a miss — teach the expected word politely
    # (AC-04: appreciation first, never "wrong").
    correction_word = ""
    correction_copy = ""
    if next_action != "celebrate":
        words = pack.expected_intents.get(expected_intent) or []
        if words and pack.child_copy.gentle_correction:
            correction_word = words[0]
            correction_copy = pack.child_copy.gentle_correction.format(
                word=correction_word
            )

    _trace_edit(
        session.story_package_id,
        "speech_turn",
        f"attempt={attempt} matched={result.matched} "
        f"intent={result.intent or '-'} score={result.score} "
        f"asr_ok={asr_ok} (raw audio discarded)",
    )

    return {
        "session_id": session_id,
        "matched": result.matched,
        "intent": result.intent,
        "confidence": result.score,
        "attempt": attempt,
        "max_attempts": max_attempts,
        "next_action": next_action,
        "celebration_copy": _pick(pack.child_copy.celebration, "🎉"),
        "encourage_copy": _pick(
            pack.child_copy.encourage_retry, "Let's listen once more!"
        ),
        "correction_word": correction_word,
        "correction_copy": correction_copy,
        "listen_prompt": pack.child_copy.listen_prompt,
        "fallback_options": fallback_options,
        "audio_retained": False,
    }


@router.post("/sessions/{session_id}/speech-fallback")
async def speech_fallback(
    session_id: str,
    data: SpeechFallbackChoice,
    adult_id: str = Depends(require_adult),
):
    """Picture-choice fallback — any tap celebrates; the story continues."""
    session = _require_session(adult_id, session_id)
    pkg = orchestrator.get_package(session.story_package_id)
    if not pkg:
        raise HTTPException(404, "Package not found")
    pack = pack_loader.get(pkg.language.locale)

    session.speech_turn_completed = True
    session.fallback_events += 1
    persistence.save("story_sessions", session_id, session)
    _trace_edit(
        session.story_package_id,
        "speech_fallback",
        f"picture_choice selected='{data.selected_word}' "
        f"(fallback_events={session.fallback_events})",
    )
    celebration = _pick(pack.child_copy.celebration, "🎉") if pack else "🎉"
    return {
        "session_id": session_id,
        "celebration_copy": celebration,
        "speech_turn_completed": True,
    }


@router.post("/sessions/{session_id}/read-aloud")
async def read_aloud_turn(
    session_id: str,
    audio: UploadFile = File(...),
    scene_index: int = Form(0),
    adult_id: str = Depends(require_adult),
):
    """
    "I read" mode — the child reads the scene aloud and Mina listens.
    Coverage is scored fuzzily against the scene narration; the response is
    ALWAYS appreciation, plus at most one word to practise together when
    coverage is partial (AC-04 — constructive, never demotivating).
    Raw transcript is never returned; raw audio discarded (AC-07).
    """
    session = _require_session(adult_id, session_id)
    pkg = orchestrator.get_package(session.story_package_id)
    if not pkg:
        raise HTTPException(404, "Package not found")
    pack = pack_loader.get(pkg.language.locale)
    if not pack:
        raise HTTPException(422, f"No language pack for {pkg.language.locale}")
    scene = next(
        (s for s in pkg.story.scenes if s.index == scene_index), None
    )
    if scene is None:
        raise HTTPException(404, f"No scene {scene_index} in this story")

    audio_bytes = await audio.read()
    if len(audio_bytes) > 5 * 1024 * 1024:
        raise HTTPException(413, "Audio clip too large (max 5 MB)")

    transcript = ""
    asr_ok = False
    for cfg in (pack.providers.asr, pack.providers.asr_fallback):
        if cfg is None or asr_ok or not audio_bytes:
            continue
        asr = _get_asr(cfg.provider)
        if asr is None:
            continue
        try:
            transcript = await asr.transcribe(audio_bytes, language=cfg.language)
            asr_ok = True
        except Exception as e:
            logger.warning(f"[ReadAloud] ASR {cfg.provider} failed: {e}")
    del audio_bytes  # AC-07 — never stored

    narration = scene.narration_target_lang or scene.narration
    reading = score_reading(
        transcript, narration, normalization=pack.speech.normalization
    )

    # One practice word max — a parent corrects gently, not with a list.
    # Pick the longest missed word: the meatiest thing to practise together.
    practice_word = ""
    practice_copy = ""
    focus_part = ""
    if reading.heard and reading.missed_words and reading.score < 0.9:
        practice_word = max(reading.missed_words, key=len)
        if pack.child_copy.reading_practice:
            practice_copy = pack.child_copy.reading_practice.format(
                word=practice_word
            )
        # Cross-check that word against what was heard, down to the letters,
        # so the child is pointed at the syllable rather than the whole word.
        focus_part = analyse_word(
            transcript, practice_word, normalization=pack.speech.normalization
        ).focus_part

    # Tiered verdict — what Mina says depends on how much was actually read,
    # not on a coin flip over the same three praise lines.
    if not reading.heard:
        verdict = "unclear"
    elif reading.score >= 0.9:
        verdict = "fluent"
    elif reading.score >= 0.5:
        verdict = "most_of_it"
    else:
        verdict = "a_few_words"

    if reading.heard:
        session.speech_turn_completed = True
        persistence.save("story_sessions", session_id, session)

    _trace_edit(
        session.story_package_id,
        "read_aloud",
        f"scene={scene_index} heard={reading.heard} score={reading.score} "
        f"verdict={verdict} asr_ok={asr_ok} (raw audio discarded)",
    )

    return {
        "session_id": session_id,
        "heard": reading.heard,
        "score": reading.score,
        "verdict": verdict,
        "words_total": reading.words_total,
        "words_read": reading.words_read,
        "praise_copy": _pick(pack.child_copy.praise_reading, "🌟"),
        "practice_word": practice_word,
        "practice_copy": practice_copy,
        "focus_part": focus_part,
        "encourage_copy": _pick(
            pack.child_copy.encourage_retry, "Let's try once more!"
        ),
        "audio_retained": False,
    }


@router.post("/sessions/{session_id}/word-practice")
async def word_practice_turn(
    session_id: str,
    audio: UploadFile = File(...),
    word_index: int = Form(0),
    adult_id: str = Depends(require_adult),
):
    """
    ✨ Words to learn — the child repeats one word and Mina TUTORS.

    Hear → analyse → cross-check against the letters of the word → answer
    what was actually said. Never a stock "Super!": a perfect attempt is
    named as perfect, a near miss names the exact syllable to fix, and a
    very different attempt gets the word modelled again.

    Honest-uncertainty rule: when ASR gives us nothing we say we could not
    hear — we never tell a child they were wrong on evidence we don't have.
    Raw transcript never returned; raw audio discarded (AC-07).
    """
    session = _require_session(adult_id, session_id)
    pkg = orchestrator.get_package(session.story_package_id)
    if not pkg:
        raise HTTPException(404, "Package not found")
    pack = pack_loader.get(pkg.language.locale)
    if not pack:
        raise HTTPException(422, f"No language pack for {pkg.language.locale}")
    vocab = pkg.story.vocabulary
    if not 0 <= word_index < len(vocab):
        raise HTTPException(404, f"No vocabulary word {word_index} in this story")
    target = vocab[word_index]
    spoken = target.word_target_lang or target.word

    audio_bytes = await audio.read()
    if len(audio_bytes) > 5 * 1024 * 1024:
        raise HTTPException(413, "Audio clip too large (max 5 MB)")

    transcript = ""
    asr_ok = False
    for cfg in (pack.providers.asr, pack.providers.asr_fallback):
        if cfg is None or asr_ok or not audio_bytes:
            continue
        asr = _get_asr(cfg.provider)
        if asr is None:
            continue
        try:
            transcript = await asr.transcribe(audio_bytes, language=cfg.language)
            asr_ok = True
        except Exception as e:
            logger.warning(f"[WordPractice] ASR {cfg.provider} failed: {e}")
    del audio_bytes  # AC-07 — never stored

    analysis = analyse_word(
        transcript, spoken, normalization=pack.speech.normalization
    )
    copy = pack.child_copy

    # One template per verdict — the child hears a different, specific answer
    # depending on what they actually said.
    if analysis.verdict == "perfect":
        feedback = _pick(copy.word_perfect, "🌟").format(word=spoken)
        next_action = "celebrate"
    elif analysis.verdict == "close":
        feedback = (copy.word_close or "").format(
            word=spoken, part=analysis.focus_part or spoken
        )
        next_action = "practise_part"
    elif analysis.verdict == "different":
        feedback = (copy.word_retry or "").format(word=spoken)
        next_action = "model_again"
    else:
        # Nothing audible (silence, or ASR outage) — not the child's fault.
        feedback = (copy.word_unclear or "").format(word=spoken)
        next_action = "model_again"

    if analysis.verdict == "perfect":
        session.speech_turn_completed = True
        persistence.save("story_sessions", session_id, session)

    _trace_edit(
        session.story_package_id,
        "word_practice",
        f"word={word_index} verdict={analysis.verdict} score={analysis.score} "
        f"asr_ok={asr_ok} (raw audio discarded)",
    )

    return {
        "session_id": session_id,
        "word_index": word_index,
        "word": spoken,
        "heard": analysis.heard,
        "verdict": analysis.verdict,
        "score": analysis.score,
        # Both derived from the TARGET word, never from the transcript.
        "focus_part": analysis.focus_part,
        "got_parts": analysis.matched_parts,
        "feedback_copy": feedback,
        "next_action": next_action,
        "audio_retained": False,
    }


@router.post("/sessions/{session_id}/speak")
async def speak_text(
    session_id: str,
    data: SpeakRequest,
    adult_id: str = Depends(require_adult),
):
    """On-demand TTS in the story's voice — for feedback Mina composes live
    (e.g. "the tricky bit is ன"), which cannot be pre-generated at approval.

    Bounded on purpose: short text only, and the voice/pace come from the
    pack, so a session can never synthesize arbitrary long content.
    """
    session = _require_session(adult_id, session_id)
    pkg = orchestrator.get_package(session.story_package_id)
    if not pkg:
        raise HTTPException(404, "Package not found")
    fvd = orchestrator._agents.get(AgentName.FAMILY_VOICE_DIRECTOR)
    if fvd is None:
        raise HTTPException(503, "Voice director unavailable")

    chain = fvd._resolve_tts_chain(pkg.language.locale)
    if not chain:
        raise HTTPException(503, "No TTS provider configured for this locale")
    try:
        audio, _used = await fvd._synthesize_with(chain, data.text)
    except Exception as e:
        logger.warning(f"[Speak] TTS failed for session {session_id}: {e}")
        raise HTTPException(502, "TTS failed")
    media_type = "audio/wav" if audio[:4] == b"RIFF" else "audio/mpeg"
    return Response(content=audio, media_type=media_type)


# ── F10 · Memory consent + progress (AC-07, hard rule 6) ───────────────

@router.post("/memories", status_code=201)
async def save_memory(
    data: MemorySaveRequest, adult_id: str = Depends(require_adult)
):
    """Save a family memory — refused without the explicit consent tick."""
    if not data.consent:
        raise HTTPException(403, "Memory consent required — nothing was saved")
    session = _require_session(adult_id, data.session_id)
    pkg = orchestrator.get_package(session.story_package_id)
    memory_id = f"mem_{uuid.uuid4().hex[:10]}"
    memory = SavedMemory(
        id=memory_id,
        session_id=data.session_id,
        story_package_id=session.story_package_id,
        child_profile_id=pkg.child_profile_id if pkg else "",
        title=pkg.story.title if pkg else "",
        target_phrase=(
            pkg.learning_plan.target_phrase if pkg and pkg.learning_plan else ""
        ),
        note=data.note,
    )
    _memories[memory_id] = memory
    persistence.save("saved_memories", memory_id, memory)
    return memory.model_dump()


@router.get("/memories")
async def list_memories(
    child_profile_id: str = "", adult_id: str = Depends(require_adult)
):
    owned = {pid for pid, p in _profiles.items() if p.adult_id == adult_id}
    items = [
        m.model_dump()
        for m in _memories.values()
        if m.child_profile_id in owned
        and (not child_profile_id or m.child_profile_id == child_profile_id)
    ]
    items.sort(key=lambda m: m["created_at"], reverse=True)
    return {"memories": items}


@router.delete("/memories/{memory_id}")
async def delete_memory(memory_id: str, adult_id: str = Depends(require_adult)):
    """Delete a saved memory — removes the row AND the package media blobs."""
    memory = _memories.get(memory_id)
    if not memory:
        raise HTTPException(404, "Memory not found")
    # Ownership — the memory's child must belong to this adult.
    _require_profile(adult_id, memory.child_profile_id)
    _memories.pop(memory_id, None)
    media_purged = _media_blobs.pop(memory.story_package_id, None) is not None
    persistence.delete("saved_memories", memory_id)
    if media_purged:
        persistence.delete_blobs(memory.story_package_id)
    return {"deleted": memory_id, "media_purged": media_purged}


@router.get("/progress/{child_profile_id}")
async def get_progress(
    child_profile_id: str, adult_id: str = Depends(require_adult)
):
    """North-star metric ONLY — completed family language moments this week.
    No scores, no streaks, no proficiency claims (hard rule 6)."""
    _require_profile(adult_id, child_profile_id)
    week_ago = datetime.utcnow() - timedelta(days=7)
    count = 0
    for session in _sessions.values():
        if not session.completed_at or session.completed_at < week_ago:
            continue
        pkg = orchestrator.get_package(session.story_package_id)
        if pkg and pkg.child_profile_id == child_profile_id:
            count += 1
    return {
        "child_profile_id": child_profile_id,
        "metric": "completed family language moments this week",
        "family_moments_this_week": count,
    }


# ── Language Pack Swap (AC-08 reusability proof) ───────────────────────

@router.get("/packs")
async def list_packs():
    """List the loaded language packs — all locale behaviour lives here."""
    return {
        "packs": [
            {
                "locale": p.locale,
                "pack_version": p.pack_version,
                "language_name": p.language_name,
                "script": p.script,
                "tts_provider": p.providers.tts.provider,
                "asr_provider": p.providers.asr.provider,
            }
            for locale in pack_loader.available_locales()
            if (p := pack_loader.get(locale))
        ]
    }


@router.get("/packs/{locale}/family-copy")
async def get_family_copy(locale: str):
    """F9 — parent-facing handoff copy straight from the pack (AC-08)."""
    pack = pack_loader.get(locale)
    if not pack:
        raise HTTPException(404, f"No language pack for '{locale}'")
    return {
        "locale": locale,
        "pack_version": pack.pack_version,
        "family_copy": pack.family_copy.model_dump(),
    }


@router.get("/packs/{locale}/word-bank")
async def get_word_bank(locale: str):
    """Word bank for the parent's target-word swap picker (F2)."""
    pack = pack_loader.get(locale)
    if not pack:
        raise HTTPException(404, f"No language pack for '{locale}'")
    return {
        "locale": locale,
        "pack_version": pack.pack_version,
        "word_bank": [e.model_dump() for e in pack.word_bank],
    }


@router.post("/packages/{package_id}/swap-language")
async def swap_language(
    package_id: str,
    new_locale: str = "ms-SG",
    adult_id: str = Depends(require_adult),
):
    """
    Demonstrate language-pack reuse: swap the locale on an existing package
    and re-run Language Guardian. No child-flow code changes.
    """
    pkg = _require_package(adult_id, package_id)

    new_pack = pack_loader.get(new_locale)
    if not new_pack:
        raise HTTPException(
            400,
            f"No language pack for '{new_locale}'. Available: {pack_loader.available_locales()}",
        )

    old_locale = pkg.language.locale
    pkg.language.locale = new_locale
    pkg.language.pack_version = new_pack.pack_version

    # Clear previous translations so the Guardian re-translates with the new pack
    pkg.story.title_target_lang = ""
    for scene in pkg.story.scenes:
        scene.narration_target_lang = ""
    pkg.story.room_mission.instruction_target_lang = ""
    pkg.story.family_handoff.prompt_target_lang = ""

    # Re-run the registered Language Guardian (keeps its LLM provider) with new pack
    guardian = orchestrator._agents.get(AgentName.LANGUAGE_GUARDIAN)
    if guardian is None:
        from ...agents.language_guardian import LanguageGuardianAgent
        guardian = LanguageGuardianAgent()
    pkg = await guardian.execute(pkg)

    return {
        "package_id": package_id,
        "old_locale": old_locale,
        "new_locale": new_locale,
        "pack_version": new_pack.pack_version,
        "validation": pkg.validation.language.value,
        "message": "Language pack swapped — no application code changed",
    }


# ── Health ─────────────────────────────────────────────────────────────────

@router.get("/health")
async def health():
    return {
        "status": "ok",
        "app": "TaleLah",
        "version": "0.1.0",
        "agents": ["moment_lens", "learning_planner", "story_weaver",
                   "language_guardian", "family_voice_director", "growth_coach"],
        "language_packs": pack_loader.available_locales(),
        "persistence": "neon" if persistence.enabled else "memory-only",
    }

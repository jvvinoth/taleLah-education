"""TaleLah — Build Constitution (loaded from AGENTS.md)."""
from enum import Enum
from pydantic_settings import BaseSettings


class Environment(str, Enum):
    DEVELOPMENT = "development"
    STAGING = "staging"
    PRODUCTION = "production"


class Settings(BaseSettings):
    """Application settings — all secrets via environment variables."""

    # App
    app_name: str = "TaleLah"
    app_version: str = "0.1.0"
    environment: Environment = Environment.DEVELOPMENT
    debug: bool = True
    api_prefix: str = "/api/v1"

    # Server
    host: str = "0.0.0.0"
    port: int = 8000

    # Database
    database_url: str = "sqlite+aiosqlite:///./talelah.db"

    # Alibaba Cloud — Qwen (LLM + Vision)
    dashscope_api_key: str = ""
    dashscope_base_url: str = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
    qwen_model: str = "qwen-max"
    qwen_vl_model: str = "qwen-vl-max"

    # New book engine: which LLM authors the book (gemini = best instruction-
    # following + strong multilingual; qwen = original; sarvam = most native
    # Tamil). Flip via BOOK_AUTHOR_LLM to A/B. Empty → fallback chain picks
    # the first available registered LLM (Gemini → Qwen → Sarvam).
    book_author_llm: str = ""
    # DashScope text-to-image model. Try "wan2.2-t2i-plus" or "qwen-image"
    # for higher quality; override via IMAGE_MODEL without touching code.
    image_model: str = "wan2.1-t2i-turbo"

    # Google Gemini — LLM for story generation (OpenAI-compatible endpoint).
    # When GEMINI_API_KEY is set, Gemini becomes the default story LLM and
    # Qwen-Max stays as a fallback. Packs can also route to it via "llm": "gemini".
    gemini_api_key: str = ""
    gemini_base_url: str = "https://generativelanguage.googleapis.com/v1beta/openai"
    # NOTE: verify this against your key (`/debug/llm` pings it). A wrong id
    # makes every Book Author call fail and silently fall back to the slow
    # classic pipeline — which is what made story creation take ~5 minutes.
    gemini_model: str = "gemini-2.5-flash"

    # Sarvam AI — Tamil speech
    sarvam_api_key: str = ""

    # Google Cloud — Malay speech + multilingual moment ASR.
    # On a host without a filesystem (Railway) supply the whole JSON inline via
    # GOOGLE_CREDENTIALS_JSON; locally the file path is used as a fallback.
    google_application_credentials: str = "./google-credentials.json"
    google_credentials_json: str = ""
    google_cloud_project: str = ""

    # Cloudflare R2 — object storage
    r2_account_id: str = ""
    r2_access_key_id: str = ""
    r2_secret_access_key: str = ""
    r2_bucket_name: str = "tale-lah"
    r2_endpoint: str = ""

    # ElevenLabs — P1 voice clone
    elevenlabs_api_key: str = ""

    # Resend — transactional email (signup verification, password reset).
    # Without an API key the code is logged instead of emailed (dev/CI mode).
    resend_api_key: str = ""
    resend_from_email: str = "TaleLah <hello@talelah.app>"

    # Media storage
    media_storage_path: str = "./media"
    max_photo_size_mb: int = 10
    max_voice_duration_sec: int = 45
    max_text_length: int = 500

    # Security
    # Shared secret for destructive maintenance endpoints (demo reseed).
    # Unset = those endpoints are disabled, which is the right default for a
    # deployment nobody is actively demoing.
    admin_token: str = ""
    secret_key: str = "dev-secret-change-in-production"
    access_token_expire_minutes: int = 60 * 24  # 24 hours

    # CORS
    # Production lives on talelah.com subdomains; the regex in main.py also
    # allows any *.talelah.com so a new subdomain never needs a code change.
    cors_origins: list[str] = [
        "https://app.talelah.com",     # Flutter web app
        "https://talelah.com",         # marketing site
        "https://www.talelah.com",
        "https://deck.talelah.com",    # pitch deck
        "http://localhost:3000",
        "http://localhost:8080",
        "https://jvvinoth.github.io",  # Flutter web on GitHub Pages
    ]

    # URLs
    backend_url: str = "https://api.talelah.com"
    frontend_url: str = "https://app.talelah.com"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8", "extra": "ignore"}


settings = Settings()

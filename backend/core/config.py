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
    qwen_model: str = "qwen-max"
    qwen_vl_model: str = "qwen-vl-max"

    # Sarvam AI — Tamil speech
    sarvam_api_key: str = ""

    # Google Cloud — Malay speech
    google_credentials_json: str = ""

    # ElevenLabs — P1 voice clone
    elevenlabs_api_key: str = ""

    # Media storage
    media_storage_path: str = "./media"
    max_photo_size_mb: int = 10
    max_voice_duration_sec: int = 45
    max_text_length: int = 500

    # Security
    secret_key: str = "dev-secret-change-in-production"
    access_token_expire_minutes: int = 60 * 24  # 24 hours

    # CORS
    cors_origins: list[str] = ["http://localhost:3000", "http://localhost:8080"]

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()

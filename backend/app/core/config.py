"""
Configuration loader.

On Vercel, sensitive values live as encrypted Environment Variables (set via
the Vercel dashboard or CLI, never committed to the repo). This replaces the
Secret Manager approach from the GCP version -- same principle (secrets never
touch source control or plain .env files in the repo), different vendor.

Required environment variables (set in Vercel project settings):
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY   (server-side only -- never exposed to frontend)
  SUPABASE_DB_HOST
  SUPABASE_DB_PASSWORD
  SUPABASE_DB_NAME              (default: postgres)
  SUPABASE_DB_USER               (default: postgres)
  GOOGLE_AI_API_KEY               (Google AI Studio key, for Gemini calls)
  AADHAAR_HASH_SALT
  DOCUMENT_SIGNING_PRIVATE_KEY     (PEM-encoded ECDSA P-256 private key)
"""

import os
from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    supabase_url: str = os.environ.get("SUPABASE_URL", "")
    supabase_service_role_key: str = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    supabase_jwt_secret: str = os.environ.get("SUPABASE_JWT_SECRET", "")

    db_host: str = os.environ.get("SUPABASE_DB_HOST", "")
    db_port: str = os.environ.get("SUPABASE_DB_PORT", "6543")  # 6543 = transaction pooler, 5432 = direct
    db_name: str = os.environ.get("SUPABASE_DB_NAME", "postgres")
    db_user: str = os.environ.get("SUPABASE_DB_USER", "")  # pooler format: postgres.<project-ref>
    db_password: str = os.environ.get("SUPABASE_DB_PASSWORD", "")

    google_ai_api_key: str = os.environ.get("GOOGLE_AI_API_KEY", "")

    aadhaar_hash_salt: str = os.environ.get("AADHAAR_HASH_SALT", "")

    # PEM-encoded ECDSA P-256 private key, single-line with literal \n escapes
    # (Vercel env vars are single strings -- store the PEM with \n separators
    # and .replace("\\n", "\n") when loading; see app/services/signing.py)
    document_signing_private_key: str = os.environ.get("DOCUMENT_SIGNING_PRIVATE_KEY", "")

    class Config:
        case_sensitive = False


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    missing = [
        name
        for name, value in [
            ("SUPABASE_URL", settings.supabase_url),
            ("SUPABASE_DB_HOST", settings.db_host),
            ("SUPABASE_DB_PASSWORD", settings.db_password),
            ("SUPABASE_JWT_SECRET", settings.supabase_jwt_secret),
            ("GOOGLE_AI_API_KEY", settings.google_ai_api_key),
            ("AADHAAR_HASH_SALT", settings.aadhaar_hash_salt),
            ("DOCUMENT_SIGNING_PRIVATE_KEY", settings.document_signing_private_key),
        ]
        if not value
    ]
    if missing:
        raise RuntimeError(
            f"Missing required environment variables: {', '.join(missing)}. "
            "Set these in the Vercel project's Environment Variables settings."
        )
    return settings

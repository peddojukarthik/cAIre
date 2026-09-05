"""
Database session management.

Same isolation guarantee as before, now pointed at Supabase's Postgres
instance: every request-scoped session sets `app.current_user_id` BEFORE any
query runs, and the RLS policies in migrations/001_init_schema.sql use that
variable to decide row visibility. Patient isolation is enforced by Postgres
itself -- a missing WHERE clause in a route handler still can't leak another
patient's data.

We connect directly to Supabase's underlying Postgres (via the connection
pooler, port 6543, or direct connection, port 5432) rather than going through
PostgREST, because we need our own RLS session-variable pattern rather than
Supabase's `auth.uid()` helper (which only auto-populates when going through
Supabase's own API gateway).
"""

from contextlib import contextmanager
from typing import Generator

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session

from app.core.config import get_settings

settings = get_settings()

_db_url = (
    f"postgresql+psycopg2://{settings.db_user}:{settings.db_password}"
    f"@{settings.db_host}:{settings.db_port}/{settings.db_name}?sslmode=require"
)

# Supabase's Transaction pooler (Supavisor, port 6543) is what we connect
# through -- Vercel serverless functions open many short-lived connections,
# and the pooler is designed for exactly that pattern (a direct connection
# on 5432 would exhaust Postgres's connection limit under this traffic shape).
# PgBouncer in transaction mode doesn't support server-side prepared statement
# caching, so we disable it here to avoid intermittent "prepared statement
# already exists" errors.
engine = create_engine(
    _db_url,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
    connect_args={"prepare_threshold": None},
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


@contextmanager
def get_db_session(user_id: str) -> Generator[Session, None, None]:
    """
    Yields a SQLAlchemy session scoped to a single authenticated user.
    `user_id` must come from a verified Supabase JWT (see app/core/auth.py)
    -- never from a client-supplied header or body field -- or the RLS
    boundary is meaningless.
    """
    session = SessionLocal()
    try:
        session.execute(
            text("SET LOCAL app.current_user_id = :uid"),
            {"uid": user_id},
        )
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()

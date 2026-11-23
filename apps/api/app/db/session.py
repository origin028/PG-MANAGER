from typing import Generator
import sqlalchemy as sa
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings

# Engine configuration for PostgreSQL with Psycopg 3
if settings.DATABASE_URL.startswith("sqlite"):
    engine = sa.create_engine(
        settings.DATABASE_URL,
        connect_args={"check_same_thread": False},
        pool_pre_ping=True,
    )
else:
    engine = sa.create_engine(
        settings.DATABASE_URL,
        pool_size=10,
        max_overflow=20,
        pool_timeout=30,
        pool_recycle=1800,
        pool_pre_ping=True,
    )

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
    expire_on_commit=False,
)


def get_db() -> Generator[Session, None, None]:
    """Dependency yielding a managed database session per request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

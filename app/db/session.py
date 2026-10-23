from typing import Generator
import sqlalchemy as sa
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings
from app.core.logging import logger

connect_args = {}
engine_kwargs = {
    "pool_pre_ping": True,
}

if settings.DATABASE_URL.startswith("sqlite"):
    connect_args["check_same_thread"] = False
else:
    # Production PostgreSQL pool tuning
    engine_kwargs.update(
        {
            "pool_size": 10,
            "max_overflow": 20,
            "pool_timeout": 30,
            "pool_recycle": 1800,
        }
    )

engine = sa.create_engine(
    settings.DATABASE_URL,
    connect_args=connect_args,
    **engine_kwargs,
)

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
    expire_on_commit=False,
)


def get_db() -> Generator[Session, None, None]:
    """Dependency that yields a database session for each request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

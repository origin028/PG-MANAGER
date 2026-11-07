import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.logging import logger
from app.db.base import Base
from app.db.session import engine, SessionLocal


def init_db(db: Session) -> None:
    """Verifies PostgreSQL connectivity and ensures metadata schema is initialized."""
    logger.info("Verifying database schema...")
    try:
        # Check connection
        db.execute(sa.text("SELECT 1"))
        logger.info("PostgreSQL connection confirmed.")
        # Create tables if not existing
        Base.metadata.create_all(bind=engine)
        logger.info("Database schema verification completed.")
    except Exception as e:
        logger.error(f"Database initialization failed: {e}", exc_info=True)
        raise


if __name__ == "__main__":
    db = SessionLocal()
    try:
        init_db(db)
    finally:
        db.close()

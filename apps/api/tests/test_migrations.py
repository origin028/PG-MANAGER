"""Fails CI when models and migrations drift apart."""
from alembic import command


def test_models_and_migrations_are_in_sync(migrated_test_database):
    # Raises alembic.util.CommandError if autogenerate would produce any operation.
    command.check(migrated_test_database)

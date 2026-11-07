"""add company bed_limit and bed is_deleted

Revision ID: b8c9d0e1f2a3
Revises: a7b8c9d0e1f2
Create Date: 2026-11-03 18:15:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b8c9d0e1f2a3'
down_revision: Union[str, None] = 'a7b8c9d0e1f2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Add bed_limit to companies table (default 240)
    op.add_column(
        'companies',
        sa.Column('bed_limit', sa.Integer(), nullable=False, server_default='240'),
    )

    # 2. Add is_deleted and deleted_at to beds table
    op.add_column(
        'beds',
        sa.Column('is_deleted', sa.Boolean(), nullable=False, server_default='false'),
    )
    op.add_column(
        'beds',
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('beds', 'deleted_at')
    op.drop_column('beds', 'is_deleted')
    op.drop_column('companies', 'bed_limit')

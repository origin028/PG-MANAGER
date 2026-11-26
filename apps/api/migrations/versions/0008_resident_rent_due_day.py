"""per-resident rent due day

Revision ID: 0008
Revises: 0007
Create Date: 2026-11-27 12:00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0008'
down_revision: Union[str, Sequence[str], None] = '0007'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Day of the month rent is due (1-28); empty means the company default (RENT_DUE_DAY).
    op.add_column('residents', sa.Column('rent_due_day', sa.SmallInteger(), nullable=True))


def downgrade() -> None:
    op.drop_column('residents', 'rent_due_day')

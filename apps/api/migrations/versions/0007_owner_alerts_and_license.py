"""owner alerts (notification links) and licence (super key) fields

Revision ID: 0007
Revises: 0006
Create Date: 2026-11-24 15:00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0007'
down_revision: Union[str, Sequence[str], None] = '0006'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # What an alert is about and which screen it opens in the app.
    op.add_column('notifications', sa.Column('kind', sa.String(length=50), nullable=True))
    op.add_column('notifications', sa.Column('link', sa.String(length=300), nullable=True))
    # Licence ("super key"): signed key that sets the bed limit. Stored even while enforcement is off.
    op.add_column('companies', sa.Column('license_key', sa.Text(), nullable=True))
    op.add_column('companies', sa.Column('license_max_beds', sa.Integer(), nullable=True))
    op.add_column('companies', sa.Column('license_activated_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('companies', sa.Column('license_expires_at', sa.DateTime(timezone=True), nullable=True))
    # Total capacity across all homes of a company.
    op.alter_column('companies', 'bed_limit', server_default='250')


def downgrade() -> None:
    op.alter_column('companies', 'bed_limit', server_default='240')
    op.drop_column('companies', 'license_expires_at')
    op.drop_column('companies', 'license_activated_at')
    op.drop_column('companies', 'license_max_beds')
    op.drop_column('companies', 'license_key')
    op.drop_column('notifications', 'link')
    op.drop_column('notifications', 'kind')

"""enforce_room_bed_composite_fk

Revision ID: b518259e353b
Revises: 2f6bb8bc3b44
Create Date: 2026-10-23 17:35:55.529313

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b518259e353b'
down_revision: Union[str, Sequence[str], None] = '2f6bb8bc3b44'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Enforce unique (id, property_id) pair on rooms
    op.create_unique_constraint(
        'uq_rooms_id_property_id',
        'rooms',
        ['id', 'property_id'],
    )

    # 2. Replace simple room_id FK on beds with composite FK (room_id, property_id) -> rooms(id, property_id)
    # This guarantees at the database level that a bed cannot reference a room in a different property,
    # and enforces ON DELETE RESTRICT to prevent accidental deletion of operational bed data.
    op.drop_constraint('beds_room_id_fkey', 'beds', type_='foreignkey')
    op.create_foreign_key(
        'fk_beds_room_id_property_id',
        'beds',
        'rooms',
        ['room_id', 'property_id'],
        ['id', 'property_id'],
        ondelete='RESTRICT',
    )


def downgrade() -> None:
    # 1. Revert composite FK to simple room_id FK
    op.drop_constraint('fk_beds_room_id_property_id', 'beds', type_='foreignkey')
    op.create_foreign_key(
        'beds_room_id_fkey',
        'beds',
        'rooms',
        ['room_id'],
        ['id'],
        ondelete='CASCADE',
    )

    # 2. Drop unique constraint on rooms (id, property_id)
    op.drop_constraint('uq_rooms_id_property_id', 'rooms', type_='unique')

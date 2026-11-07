"""phase2a_rooms_and_beds

Revision ID: 2f6bb8bc3b44
Revises: 910643d8744a
Create Date: 2026-10-23 17:11:09.777403

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '2f6bb8bc3b44'
down_revision: Union[str, Sequence[str], None] = '910643d8744a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Rooms Table
    op.create_table(
        'rooms',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True, nullable=False),
        sa.Column('property_id', sa.Uuid(as_uuid=True), sa.ForeignKey('properties.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('room_number', sa.String(length=50), nullable=False),
        sa.Column('floor_number', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('room_type', sa.String(length=50), nullable=False, server_default='DOUBLE'),
        sa.Column('base_monthly_rent', sa.Numeric(precision=10, scale=2), nullable=False, server_default='0.00'),
        sa.Column('deposit_amount', sa.Numeric(precision=10, scale=2), nullable=False, server_default='0.00'),
        sa.Column('amenities', sa.JSON(), nullable=False, server_default='[]'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('property_id', 'room_number', name='uq_room_property_room_number'),
    )
    op.create_index('ix_rooms_id', 'rooms', ['id'], unique=False)
    op.create_index('ix_rooms_property_id', 'rooms', ['property_id'], unique=False)
    op.create_index('ix_rooms_property_floor', 'rooms', ['property_id', 'floor_number'], unique=False)

    # 2. Beds Table
    op.create_table(
        'beds',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True, nullable=False),
        sa.Column('property_id', sa.Uuid(as_uuid=True), sa.ForeignKey('properties.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('room_id', sa.Uuid(as_uuid=True), sa.ForeignKey('rooms.id', ondelete='CASCADE'), nullable=False),
        sa.Column('bed_number', sa.String(length=50), nullable=False),
        sa.Column('monthly_rent', sa.Numeric(precision=10, scale=2), nullable=False, server_default='0.00'),
        sa.Column('status', sa.String(length=50), nullable=False, server_default='AVAILABLE'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('room_id', 'bed_number', name='uq_bed_room_bed_number'),
    )
    op.create_index('ix_beds_id', 'beds', ['id'], unique=False)
    op.create_index('ix_beds_property_id', 'beds', ['property_id'], unique=False)
    op.create_index('ix_beds_room_id', 'beds', ['room_id'], unique=False)
    op.create_index('ix_beds_property_status', 'beds', ['property_id', 'status'], unique=False)


def downgrade() -> None:
    op.drop_table('beds')
    op.drop_table('rooms')

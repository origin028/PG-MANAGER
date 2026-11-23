"""add resident registration fields and pending registrations table

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8
Create Date: 2026-10-30 22:15:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd4e5f6a7b8c9'
down_revision: Union[str, None] = 'c3d4e5f6a7b8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Inspect existing columns to prevent duplicate additions
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    existing_cols = {c['name'] for c in inspector.get_columns('residents')}

    # 2. Add resident onboarding and KYC columns to 'residents' table
    for col_name, col_type in [
        ('date_of_birth', sa.Date()),
        ('gender', sa.String(length=20)),
        ('occupation', sa.String(length=100)),
        ('emergency_contact', sa.String(length=150)),
        ('house_flat_no', sa.String(length=100)),
        ('street', sa.String(length=150)),
        ('landmark', sa.String(length=150)),
        ('city', sa.String(length=100)),
        ('state', sa.String(length=100)),
        ('pincode', sa.String(length=20)),
        ('verification_method', sa.String(length=50)),
        ('aadhaar_front_path', sa.String(length=512)),
        ('aadhaar_back_path', sa.String(length=512)),
        ('pan_card_path', sa.String(length=512)),
        ('passport_path', sa.String(length=512)),
        ('resident_selfie_path', sa.String(length=512)),
        ('kyc_documents', sa.JSON()),
    ]:
        if col_name not in existing_cols:
            op.add_column('residents', sa.Column(col_name, col_type, nullable=True))

    # 3. Create 'pending_resident_registrations' staging table
    existing_tables = inspector.get_table_names()
    if 'pending_resident_registrations' not in existing_tables:
        op.create_table(
            'pending_resident_registrations',
            sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True),
            sa.Column('phone', sa.String(length=30), nullable=False),
            sa.Column('email', sa.String(length=255), nullable=False),
            sa.Column('registration_data', sa.JSON(), nullable=False),
            sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        )
        op.create_index(
            'ix_pending_resident_registrations_phone',
            'pending_resident_registrations',
            ['phone'],
            unique=True,
        )
        op.create_index(
            'ix_pending_resident_registrations_email',
            'pending_resident_registrations',
            ['email'],
            unique=False,
        )


def downgrade() -> None:
    # 1. Strict safety check
    conn = op.get_bind()
    current_db = conn.execute(sa.text("SELECT current_database()")).scalar()
    if current_db != "pg_management_test":
        err_msg = f"Safety check aborted: Migration can only execute on 'pg_management_test', not '{current_db}'."
        raise RuntimeError(err_msg)

    # 2. Drop staging table
    op.drop_index('ix_pending_resident_registrations_email', table_name='pending_resident_registrations')
    op.drop_index('ix_pending_resident_registrations_phone', table_name='pending_resident_registrations')
    op.drop_table('pending_resident_registrations')

    # 3. Drop added columns from 'residents'
    op.drop_column('residents', 'kyc_documents')
    op.drop_column('residents', 'resident_selfie_path')
    op.drop_column('residents', 'passport_path')
    op.drop_column('residents', 'pan_card_path')
    op.drop_column('residents', 'aadhaar_back_path')
    op.drop_column('residents', 'aadhaar_front_path')
    op.drop_column('residents', 'verification_method')
    op.drop_column('residents', 'pincode')
    op.drop_column('residents', 'state')
    op.drop_column('residents', 'city')
    op.drop_column('residents', 'landmark')
    op.drop_column('residents', 'street')
    op.drop_column('residents', 'house_flat_no')
    op.drop_column('residents', 'emergency_contact')
    op.drop_column('residents', 'occupation')
    op.drop_column('residents', 'gender')
    op.drop_column('residents', 'date_of_birth')

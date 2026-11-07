"""phase1_initial_auth_and_properties

Revision ID: 910643d8744a
Revises: 
Create Date: 2026-10-23 14:38:54.599343

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '910643d8744a'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Companies Table
    op.create_table(
        'companies',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True, nullable=False),
        sa.Column('name', sa.String(length=150), nullable=False),
        sa.Column('code', sa.String(length=50), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=True),
        sa.Column('phone', sa.String(length=30), nullable=True),
        sa.Column('address', sa.Text(), nullable=True),
        sa.Column('tax_id', sa.String(length=50), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_companies_id', 'companies', ['id'], unique=False)
    op.create_index('ix_companies_code', 'companies', ['code'], unique=True)

    # 2. Roles Table
    op.create_table(
        'roles',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True, nullable=False),
        sa.Column('name', sa.String(length=50), nullable=False),
        sa.Column('display_name', sa.String(length=100), nullable=False),
        sa.Column('description', sa.String(length=255), nullable=True),
        sa.Column('is_system_role', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('permissions', sa.JSON(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_roles_id', 'roles', ['id'], unique=False)
    op.create_index('ix_roles_name', 'roles', ['name'], unique=True)

    # 3. Properties Table
    op.create_table(
        'properties',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True, nullable=False),
        sa.Column('company_id', sa.Uuid(as_uuid=True), sa.ForeignKey('companies.id', ondelete='CASCADE'), nullable=False),
        sa.Column('name', sa.String(length=150), nullable=False),
        sa.Column('code', sa.String(length=50), nullable=False),
        sa.Column('property_type', sa.String(length=50), nullable=False, server_default='CO_LIVING'),
        sa.Column('address_line1', sa.String(length=255), nullable=False),
        sa.Column('address_line2', sa.String(length=255), nullable=True),
        sa.Column('city', sa.String(length=100), nullable=False, server_default='Bangalore'),
        sa.Column('state', sa.String(length=100), nullable=False, server_default='Karnataka'),
        sa.Column('pincode', sa.String(length=20), nullable=False),
        sa.Column('contact_phone', sa.String(length=30), nullable=True),
        sa.Column('contact_email', sa.String(length=255), nullable=True),
        sa.Column('total_floors', sa.Integer(), nullable=False, server_default='4'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('settings', sa.JSON(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_properties_id', 'properties', ['id'], unique=False)
    op.create_index('ix_properties_code', 'properties', ['code'], unique=True)
    op.create_index('ix_properties_company_id', 'properties', ['company_id'], unique=False)

    # 4. Users Table
    op.create_table(
        'users',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True, nullable=False),
        sa.Column('company_id', sa.Uuid(as_uuid=True), sa.ForeignKey('companies.id', ondelete='CASCADE'), nullable=False),
        sa.Column('role_id', sa.Uuid(as_uuid=True), sa.ForeignKey('roles.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=True),
        sa.Column('phone', sa.String(length=30), nullable=False),
        sa.Column('full_name', sa.String(length=150), nullable=False),
        sa.Column('password_hash', sa.String(length=255), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('is_verified', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('avatar_url', sa.String(length=512), nullable=True),
        sa.Column('last_login_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_users_id', 'users', ['id'], unique=False)
    op.create_index('ix_users_email', 'users', ['email'], unique=True)
    op.create_index('ix_users_phone', 'users', ['phone'], unique=True)
    op.create_index('ix_users_company_id', 'users', ['company_id'], unique=False)
    op.create_index('ix_users_role_id', 'users', ['role_id'], unique=False)

    # 5. User Property Access Junction Table
    op.create_table(
        'user_property_access',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True, nullable=False),
        sa.Column('user_id', sa.Uuid(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('property_id', sa.Uuid(as_uuid=True), sa.ForeignKey('properties.id', ondelete='CASCADE'), nullable=False),
        sa.Column('access_level', sa.String(length=50), nullable=False, server_default='MANAGER'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('user_id', 'property_id', name='uq_user_property_access'),
    )
    op.create_index('ix_user_property_access_id', 'user_property_access', ['id'], unique=False)
    op.create_index('ix_user_property_access_user_id', 'user_property_access', ['user_id'], unique=False)
    op.create_index('ix_user_property_access_property_id', 'user_property_access', ['property_id'], unique=False)

    # 6. Refresh Tokens Table
    op.create_table(
        'refresh_tokens',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True, nullable=False),
        sa.Column('user_id', sa.Uuid(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('token_hash', sa.String(length=255), nullable=False),
        sa.Column('client_type', sa.String(length=50), nullable=False, server_default='admin_web'),
        sa.Column('device_info', sa.String(length=255), nullable=True),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('is_revoked', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_refresh_tokens_id', 'refresh_tokens', ['id'], unique=False)
    op.create_index('ix_refresh_tokens_user_id', 'refresh_tokens', ['user_id'], unique=False)
    op.create_index('ix_refresh_tokens_token_hash', 'refresh_tokens', ['token_hash'], unique=False)

    # 7. Audit Logs Table
    op.create_table(
        'audit_logs',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True, nullable=False),
        sa.Column('company_id', sa.Uuid(as_uuid=True), sa.ForeignKey('companies.id', ondelete='SET NULL'), nullable=True),
        sa.Column('property_id', sa.Uuid(as_uuid=True), sa.ForeignKey('properties.id', ondelete='SET NULL'), nullable=True),
        sa.Column('user_id', sa.Uuid(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('user_email', sa.String(length=255), nullable=True),
        sa.Column('user_role', sa.String(length=50), nullable=True),
        sa.Column('action', sa.String(length=100), nullable=False),
        sa.Column('resource_type', sa.String(length=100), nullable=False),
        sa.Column('resource_id', sa.String(length=100), nullable=True),
        sa.Column('details', sa.JSON(), nullable=False),
        sa.Column('ip_address', sa.String(length=50), nullable=True),
        sa.Column('user_agent', sa.String(length=255), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_audit_logs_id', 'audit_logs', ['id'], unique=False)
    op.create_index('ix_audit_logs_action', 'audit_logs', ['action'], unique=False)
    op.create_index('ix_audit_logs_resource_type', 'audit_logs', ['resource_type'], unique=False)
    op.create_index('ix_audit_logs_company_id', 'audit_logs', ['company_id'], unique=False)
    op.create_index('ix_audit_logs_property_id', 'audit_logs', ['property_id'], unique=False)
    op.create_index('ix_audit_logs_user_id', 'audit_logs', ['user_id'], unique=False)
    op.create_index('ix_audit_logs_created_at', 'audit_logs', ['created_at'], unique=False)


def downgrade() -> None:
    op.drop_table('audit_logs')
    op.drop_table('refresh_tokens')
    op.drop_table('user_property_access')
    op.drop_table('users')
    op.drop_table('properties')
    op.drop_table('roles')
    op.drop_table('companies')

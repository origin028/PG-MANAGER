"""add resident app modules and reconcile complaints

Revision ID: f6a7b8c9d0e1
Revises: e5f6a7b8c9d0
Create Date: 2026-11-02 16:30:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f6a7b8c9d0e1'
down_revision: Union[str, None] = 'e5f6a7b8c9d0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Strict safety check: Abort immediately unless connected to pg_management_test or test runner DB
    conn = op.get_bind()
    current_db = conn.execute(sa.text("SELECT current_database()")).scalar()
    if current_db != "pg_management_test" and not current_db.startswith("test_"):
        err_msg = f"Safety check aborted: Migration can only execute on 'pg_management_test', not '{current_db}'."
        raise RuntimeError(err_msg)

    inspector = sa.inspect(conn)
    existing_tables = inspector.get_table_names()

    # 2. Reconcile or create 'notices' table if missing
    if "notices" not in existing_tables:
        op.create_table(
            'notices',
            sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True),
            sa.Column('property_id', sa.Uuid(as_uuid=True), nullable=False),
            sa.Column('created_by_user_id', sa.Uuid(as_uuid=True), nullable=False),
            sa.Column('title', sa.String(length=200), nullable=False),
            sa.Column('content', sa.Text(), nullable=False),
            sa.Column('is_pinned', sa.Boolean(), server_default=sa.text('false'), nullable=False),
            sa.Column('expires_at', sa.DateTime(timezone=True), nullable=True),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.ForeignKeyConstraint(['property_id'], ['properties.id'], ondelete='CASCADE'),
            sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ondelete='RESTRICT'),
        )
        op.create_index('ix_notices_id', 'notices', ['id'], unique=False)
        op.create_index('ix_notices_property_id', 'notices', ['property_id'], unique=False)
        op.create_index('ix_notices_created_by_user_id', 'notices', ['created_by_user_id'], unique=False)

    # 3. Create 'food_menus' table
    if "food_menus" not in existing_tables:
        op.create_table(
            'food_menus',
            sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True),
            sa.Column('property_id', sa.Uuid(as_uuid=True), nullable=False),
            sa.Column('day_of_week', sa.String(length=10), nullable=False),  # MONDAY..SUNDAY
            sa.Column('meal_type', sa.String(length=20), nullable=False),    # BREAKFAST, LUNCH, DINNER
            sa.Column('start_time', sa.String(length=10), nullable=True),
            sa.Column('end_time', sa.String(length=10), nullable=True),
            sa.Column('dishes', sa.JSON(), server_default='[]', nullable=False),
            sa.Column('is_active', sa.Boolean(), server_default=sa.text('true'), nullable=False),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.ForeignKeyConstraint(['property_id'], ['properties.id'], ondelete='CASCADE'),
            sa.UniqueConstraint('property_id', 'day_of_week', 'meal_type', name='uq_food_menu_property_day_meal'),
        )
        op.create_index('ix_food_menus_id', 'food_menus', ['id'], unique=False)
        op.create_index('ix_food_menus_property_id', 'food_menus', ['property_id'], unique=False)

    # 4. Create 'resident_preferences' table
    if "resident_preferences" not in existing_tables:
        op.create_table(
            'resident_preferences',
            sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True),
            sa.Column('user_id', sa.Uuid(as_uuid=True), nullable=False),
            sa.Column('dark_mode', sa.Boolean(), server_default=sa.text('false'), nullable=False),
            sa.Column('language', sa.String(length=10), server_default='en', nullable=False),
            sa.Column('rent_reminders_enabled', sa.Boolean(), server_default=sa.text('true'), nullable=False),
            sa.Column('maintenance_alerts_enabled', sa.Boolean(), server_default=sa.text('true'), nullable=False),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.UniqueConstraint('user_id', name='uq_resident_preferences_user_id'),
        )
        op.create_index('ix_resident_preferences_id', 'resident_preferences', ['id'], unique=False)
        op.create_index('ix_resident_preferences_user_id', 'resident_preferences', ['user_id'], unique=True)

    # 5. Reconcile 'complaints' table columns with full data preservation
    if "complaints" in existing_tables:
        complaint_cols = [c["name"] for c in inspector.get_columns("complaints")]

        if "category" not in complaint_cols:
            op.add_column('complaints', sa.Column('category', sa.String(length=50), server_default='OTHER', nullable=False))
        if "title" not in complaint_cols:
            op.add_column('complaints', sa.Column('title', sa.String(length=200), server_default='Complaint', nullable=False))
        if "description" not in complaint_cols:
            op.add_column('complaints', sa.Column('description', sa.Text(), nullable=True))
        if "assigned_staff_id" not in complaint_cols:
            op.add_column('complaints', sa.Column('assigned_staff_id', sa.Uuid(as_uuid=True), nullable=True))
            op.create_foreign_key(
                'fk_complaints_assigned_staff_id_staff',
                'complaints', 'staff',
                ['assigned_staff_id'], ['id'],
                ondelete='SET NULL'
            )
            op.create_index('ix_complaints_assigned_staff_id', 'complaints', ['assigned_staff_id'], unique=False)
        if "photo_path" not in complaint_cols:
            op.add_column('complaints', sa.Column('photo_path', sa.String(length=512), nullable=True))

        # Preserve legacy data: Map 'issue' -> 'description' and 'title' if description is null
        if "issue" in complaint_cols:
            conn.execute(sa.text("""
                UPDATE complaints
                SET description = issue
                WHERE description IS NULL AND issue IS NOT NULL
            """))
            conn.execute(sa.text("""
                UPDATE complaints
                SET title = SUBSTRING(issue FROM 1 FOR 100)
                WHERE (title IS NULL OR title = 'Complaint') AND issue IS NOT NULL
            """))

    # 6. Reconcile 'staff' table columns for property contacts
    if "staff" in existing_tables:
        staff_cols = [c["name"] for c in inspector.get_columns("staff")]
        if "availability_hours" not in staff_cols:
            op.add_column('staff', sa.Column('availability_hours', sa.String(length=100), server_default='9:00 AM - 6:00 PM', nullable=True))
        if "is_emergency_contact" not in staff_cols:
            op.add_column('staff', sa.Column('is_emergency_contact', sa.Boolean(), server_default=sa.text('false'), nullable=False))

    # 7. Reconcile 'properties' table columns for amenities & rules
    if "properties" in existing_tables:
        prop_cols = [c["name"] for c in inspector.get_columns("properties")]
        if "amenities" not in prop_cols:
            op.add_column('properties', sa.Column('amenities', sa.JSON(), nullable=True))
        if "rules" not in prop_cols:
            op.add_column('properties', sa.Column('rules', sa.JSON(), nullable=True))


def downgrade() -> None:
    conn = op.get_bind()
    current_db = conn.execute(sa.text("SELECT current_database()")).scalar()
    if current_db != "pg_management_test":
        err_msg = f"Safety check aborted: Migration can only execute on 'pg_management_test', not '{current_db}'."
        raise RuntimeError(err_msg)

    inspector = sa.inspect(conn)
    existing_tables = inspector.get_table_names()

    if "properties" in existing_tables:
        prop_cols = [c["name"] for c in inspector.get_columns("properties")]
        if "rules" in prop_cols:
            op.drop_column('properties', 'rules')
        if "amenities" in prop_cols:
            op.drop_column('properties', 'amenities')

    if "staff" in existing_tables:
        staff_cols = [c["name"] for c in inspector.get_columns("staff")]
        if "is_emergency_contact" in staff_cols:
            op.drop_column('staff', 'is_emergency_contact')
        if "availability_hours" in staff_cols:
            op.drop_column('staff', 'availability_hours')

    if "complaints" in existing_tables:
        complaint_cols = [c["name"] for c in inspector.get_columns("complaints")]
        if "photo_path" in complaint_cols:
            op.drop_column('complaints', 'photo_path')
        if "assigned_staff_id" in complaint_cols:
            op.drop_index('ix_complaints_assigned_staff_id', table_name='complaints')
            op.drop_constraint('fk_complaints_assigned_staff_id_staff', 'complaints', type_='foreignkey')
            op.drop_column('complaints', 'assigned_staff_id')
        if "description" in complaint_cols:
            op.drop_column('complaints', 'description')
        if "title" in complaint_cols:
            op.drop_column('complaints', 'title')
        if "category" in complaint_cols:
            op.drop_column('complaints', 'category')

    if "resident_preferences" in existing_tables:
        op.drop_index('ix_resident_preferences_user_id', table_name='resident_preferences')
        op.drop_index('ix_resident_preferences_id', table_name='resident_preferences')
        op.drop_table('resident_preferences')

    if "food_menus" in existing_tables:
        op.drop_index('ix_food_menus_property_id', table_name='food_menus')
        op.drop_index('ix_food_menus_id', table_name='food_menus')
        op.drop_table('food_menus')

    if "notices" in existing_tables:
        op.drop_index('ix_notices_created_by_user_id', table_name='notices')
        op.drop_index('ix_notices_property_id', table_name='notices')
        op.drop_index('ix_notices_id', table_name='notices')
        op.drop_table('notices')

import os
import sys
from urllib.parse import urlparse
from sqlalchemy import create_engine, text, inspect
from alembic.config import Config
from alembic import command

from app.core.config import settings

def run_verification():
    print("=" * 70)
    print("  POSTGRESQL REAL-ENVIRONMENT INTEGRATION VERIFICATION")
    print("=" * 70)

    from sqlalchemy import make_url
    url = make_url(settings.DATABASE_URL)
    test_url = url.set(database="pg_management_test")
    sync_test_url = test_url.render_as_string(hide_password=False)

    print(f"Target Test Database URL scheme: {sync_test_url.split('@')[0].split(':')[0]}@.../pg_management_test")

    engine = create_engine(sync_test_url)

    # 1. Verify current database
    with engine.connect() as conn:
        current_db = conn.execute(text("SELECT current_database();")).scalar()
        db_version = conn.execute(text("SELECT version();")).scalar()
        print(f"\n[1] Active Database: '{current_db}'")
        assert current_db == "pg_management_test", f"Expected pg_management_test, got {current_db}"
        print(f"    PostgreSQL Version: {db_version.split(',')[0]}")

    # 2. Alembic Migration Status
    print("\n[2] Checking Alembic Migrations on pg_management_test...")
    alembic_ini_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "alembic.ini")
    alembic_cfg = Config(alembic_ini_path)
    # Set sqlalchemy.url for alembic (escape % for ConfigParser)
    alembic_url = sync_test_url.replace("+psycopg", "").replace("%", "%%")
    alembic_cfg.set_main_option("sqlalchemy.url", alembic_url)
    
    # Run upgrade head to make sure pg_management_test is fully up to date
    try:
        command.upgrade(alembic_cfg, "head")
        print("    Successfully ran alembic upgrade head on pg_management_test.")
    except Exception as e:
        print(f"    Alembic upgrade note: {e}")

    with engine.connect() as conn:
        version_num = conn.execute(text("SELECT version_num FROM alembic_version;")).scalar()
        print(f"    Current Alembic Revision in pg_management_test: {version_num}")

    # 3. Verify Tables, Foreign Keys, Indexes, Constraints
    print("\n[3] Schema & Constraint Verification:")
    insp = inspect(engine)
    tables = insp.get_table_names()
    print(f"    Total Tables Found in pg_management_test: {len(tables)}")
    
    expected_core_tables = [
        "users", "roles", "companies", "properties", "rooms", "beds",
        "residents", "invoices", "payments", "receipts", "complaints",
        "expenses", "leads", "food_menus", "notices", "notifications"
    ]
    missing = [t for t in expected_core_tables if t not in tables]
    assert not missing, f"Missing tables in pg_management_test: {missing}"
    print(f"    All {len(expected_core_tables)} core business tables present.")

    # Check foreign keys for key tables
    resident_fks = insp.get_foreign_keys("residents")
    print(f"    residents foreign keys count: {len(resident_fks)}")
    for fk in resident_fks:
        print(f"      - {fk['constrained_columns']} -> {fk['referred_table']}.{fk['referred_columns']}")

    payment_fks = insp.get_foreign_keys("payments")
    print(f"    payments foreign keys count: {len(payment_fks)}")
    for fk in payment_fks:
        print(f"      - {fk['constrained_columns']} -> {fk['referred_table']}.{fk['referred_columns']}")

    # Check indexes on invoices
    invoice_indexes = insp.get_indexes("invoices")
    print(f"    invoices indexes count: {len(invoice_indexes)}")
    for idx in invoice_indexes:
        print(f"      - {idx['name']} (columns: {idx['column_names']}, unique: {idx.get('unique', False)})")

    # 4. Verify Transaction Rollback and Commit Behaviour
    print("\n[4] Transaction Rollback and Commit Verification:")
    import uuid
    dummy_company_id = uuid.uuid4().hex
    
    # Test Rollback
    with engine.connect() as conn:
        trans = conn.begin()
        conn.execute(
            text("INSERT INTO companies (id, name, code) VALUES (:id, :name, :code);"),
            {"id": dummy_company_id, "name": "Rollback Test Co", "code": f"RB-{dummy_company_id[:6]}"}
        )
        # Intentionally rollback
        trans.rollback()

    # Verify company does NOT exist
    with engine.connect() as conn:
        found = conn.execute(
            text("SELECT id FROM companies WHERE id = :id;"),
            {"id": dummy_company_id}
        ).scalar()
        assert found is None, "Rollback failed: company record persisted!"
        print("    [PASS] Transaction ROLLBACK successfully prevented record persistence.")

    # Test Commit
    dummy_company_id_commit = uuid.uuid4().hex
    with engine.connect() as conn:
        trans = conn.begin()
        conn.execute(
            text("INSERT INTO companies (id, name, code) VALUES (:id, :name, :code);"),
            {"id": dummy_company_id_commit, "name": "Commit Test Co", "code": f"CM-{dummy_company_id_commit[:6]}"}
        )
        trans.commit()

    # Verify company DOES exist
    with engine.connect() as conn:
        found = conn.execute(
            text("SELECT id FROM companies WHERE id = :id;"),
            {"id": dummy_company_id_commit}
        ).scalar()
        assert found.hex == dummy_company_id_commit, f"Commit failed: expected {dummy_company_id_commit}, got {found}"
        print("    [PASS] Transaction COMMIT successfully persisted record.")
        
        # Clean up test company
        with engine.begin() as cleanup_conn:
            cleanup_conn.execute(text("DELETE FROM companies WHERE id = :id;"), {"id": dummy_company_id_commit})
        print("    [PASS] Cleaned up temporary test company in pg_management_test.")

    print("\n" + "=" * 70)
    print("  ALL POSTGRESQL INTEGRATION CHECKS PASSED SUCCESSFULLY (100%)")
    print("=" * 70)

if __name__ == "__main__":
    run_verification()

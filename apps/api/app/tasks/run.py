"""Job runner for scheduled work (cron). Usage:

    python -m app.tasks.run monthly-invoices [YYYY-MM]
    python -m app.tasks.run reminders
    python -m app.tasks.run kyc-deadlines
"""
import sys

from app.core.logging import setup_logging
from app.tasks.invoice_jobs import generate_monthly_invoices_job
from app.tasks.reminder_jobs import send_payment_reminders_job


def main(argv: list) -> int:
    setup_logging()
    if not argv:
        print(__doc__)
        return 2
    job = argv[0]
    if job == "monthly-invoices":
        print(generate_monthly_invoices_job(argv[1] if len(argv) > 1 else None))
    elif job == "reminders":
        print(send_payment_reminders_job())
    elif job == "kyc-deadlines":
        from app.db.session import SessionLocal
        from app.services.portal_service import run_daily

        db = SessionLocal()
        try:
            print(run_daily(db))
        finally:
            db.close()
    else:
        print(f"Unknown job '{job}'.\n{__doc__}")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

"""Background worker script to process pending WhatsApp receipt delivery outbox.

DELIVERY SEMANTICS:
  - External WhatsApp message delivery operates with AT-LEAST-ONCE guarantees.
  - While pessimistic row locks (`with_for_update()`) prevent concurrent worker collisions,
    an unexpected process termination or network failure occurring between Meta provider
    acceptance and the local database commit can result in a retry that sends a duplicate
    message.
  - In contrast, internal payment settlement, invoice crediting, and receipt issuance are
    strictly atomic and EXACTLY-ONCE under database ACID transaction isolation.

Usage:
  # Run a single batch run (e.g. from cron or periodic task runner):
  python -m scripts.run_receipt_delivery_worker --once

  # Run continuously as a background daemon polling every interval (default 10s):
  python -m scripts.run_receipt_delivery_worker --poll-interval 10
"""

import argparse
import logging
import sys
import time

from app.db.session import SessionLocal
from app.services.receipt_delivery_service import ReceiptDeliveryService

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger("receipt_delivery_worker")


def run_delivery_pass() -> int:
    """Executes a single delivery pass processing all due pending receipts."""
    db = SessionLocal()
    try:
        service = ReceiptDeliveryService(db)
        sent = service.process_due_receipts(limit=50)
        return sent
    finally:
        db.close()


def main():
    parser = argparse.ArgumentParser(description="PG Management WhatsApp Receipt Delivery Worker")
    parser.add_argument("--once", action="store_true", help="Run one batch pass and exit.")
    parser.add_argument("--poll-interval", type=int, default=10, help="Poll interval in seconds for daemon mode.")
    args = parser.parse_args()

    logger.info("Starting WhatsApp Receipt Delivery Worker...")

    if args.once:
        sent = run_delivery_pass()
        logger.info(f"One-time delivery pass finished. Delivered {sent} receipts.")
        return

    logger.info(f"Worker running in continuous daemon mode (polling every {args.poll_interval}s). Press Ctrl+C to stop.")
    try:
        while True:
            try:
                sent = run_delivery_pass()
                if sent > 0:
                    logger.info(f"Delivered {sent} due receipts.")
            except Exception as exc:
                logger.error(f"Error during receipt delivery pass: {exc}", exc_info=True)
            time.sleep(args.poll_interval)
    except KeyboardInterrupt:
        logger.info("WhatsApp Receipt Delivery Worker stopped gracefully.")


if __name__ == "__main__":
    main()

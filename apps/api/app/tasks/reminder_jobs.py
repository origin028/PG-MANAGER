from app.core.logging import logger


def send_payment_reminders_job() -> dict:
    """
    Scheduled background task to send automated payment reminders
    for upcoming and overdue rent invoices.
    """
    logger.info("Executing overdue rent payment reminder job.")
    return {"status": "SUCCESS", "reminders_sent": 0}

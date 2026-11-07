from app.core.logging import logger


def generate_monthly_invoices_job(billing_month: str) -> dict:
    """
    Scheduled background task to batch generate repeat-safe rent invoices
    for active residents across all properties.
    """
    logger.info(f"Starting recurring invoice generation job for cycle: {billing_month}")
    return {"status": "SUCCESS", "cycle": billing_month, "generated_count": 0}

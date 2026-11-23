import pytest

from app.integrations.whatsapp import WhatsAppCloudProvider


def test_whatsapp_provider_requires_configured_business_credentials():
    with pytest.raises(ValueError, match="not configured"):
        WhatsAppCloudProvider("", "")

import hashlib
import hmac
import logging

import requests
from django.conf import settings

logger = logging.getLogger(__name__)


class MaxicashClient:
    """Client for Maxicash Mobile Money API."""

    def __init__(self):
        self.merchant_id = settings.MAXICASH_MERCHANT_ID
        self.merchant_secret = settings.MAXICASH_MERCHANT_SECRET
        self.api_url = settings.MAXICASH_API_URL

    def initiate_payment(self, phone_number: str, amount: float, reference: str, currency: str = "CDF") -> dict:
        """Initiate a mobile money payment."""
        payload = {
            "merchantId": self.merchant_id,
            "amount": str(amount),
            "currency": currency,
            "phone": phone_number,
            "reference": reference,
            "description": f"Mwamba Taxi - Course {reference}",
        }

        # Sign request
        sign_string = f"{self.merchant_id}{amount}{currency}{reference}{self.merchant_secret}"
        payload["signature"] = hmac.new(
            self.merchant_secret.encode(),
            sign_string.encode(),
            hashlib.sha256,
        ).hexdigest()

        try:
            response = requests.post(
                f"{self.api_url}/v1/payments/initiate",
                json=payload,
                timeout=30,
            )
            response.raise_for_status()
            data = response.json()
            return {
                "success": data.get("status") == "success",
                "transaction_id": data.get("transactionId", ""),
                "message": data.get("message", ""),
                "raw": data,
            }
        except requests.RequestException as e:
            logger.error("Maxicash payment failed: %s", e)
            return {
                "success": False,
                "transaction_id": "",
                "message": str(e),
                "raw": {},
            }

    def check_status(self, transaction_id: str) -> dict:
        """Check payment status."""
        try:
            response = requests.get(
                f"{self.api_url}/v1/payments/{transaction_id}/status",
                params={"merchantId": self.merchant_id},
                timeout=30,
            )
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            logger.error("Maxicash status check failed: %s", e)
            return {"status": "error", "message": str(e)}

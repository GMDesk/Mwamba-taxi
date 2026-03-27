"""
PawaPay Mobile Money integration.

Handles deposits (customer top-up), payouts (driver withdrawal),
and refunds via the PawaPay REST API.

API docs: https://docs.pawapay.io/
"""
import hashlib
import hmac
import logging
import uuid

import requests
from django.conf import settings

logger = logging.getLogger(__name__)

PAWAPAY_API_URL = getattr(settings, "PAWAPAY_API_URL", "https://api.sandbox.pawapay.io")
TIMEOUT = 30


def _headers() -> dict:
    return {
        "Authorization": f"Bearer {settings.PAWAPAY_API_TOKEN}",
        "Content-Type": "application/json",
    }


def _correspondent(phone: str) -> str:
    """Map phone prefix to PawaPay correspondent ID (DRC operators)."""
    clean = phone.lstrip("+")
    if clean.startswith("243"):
        suffix = clean[3:5]
        if suffix in ("81", "82", "83"):
            return "VODACOM_CD"        # M-Pesa
        if suffix in ("97", "99", "98"):
            return "AIRTEL_CD"          # Airtel Money
        if suffix in ("80", "84", "85", "89"):
            return "ORANGE_CD"          # Orange Money
    return "VODACOM_CD"  # default fallback


# ───────────────────────── DEPOSIT (Top-up wallet) ─────────────────────
def initiate_deposit(
    phone_number: str,
    amount: float,
    deposit_id: str | None = None,
    description: str = "Mwamba Taxi – Rechargement wallet",
) -> dict:
    """Request a deposit from a customer's mobile money account.

    Returns: {"success": bool, "deposit_id": str, "status": str, "raw": dict}
    """
    dep_id = deposit_id or str(uuid.uuid4())
    payload = {
        "depositId": dep_id,
        "amount": str(int(amount)),
        "currency": "CDF",
        "correspondent": _correspondent(phone_number),
        "payer": {
            "type": "MSISDN",
            "address": {"value": phone_number.lstrip("+")},
        },
        "customerTimestamp": None,  # PawaPay uses server time
        "statementDescription": description[:22],  # max 22 chars
    }
    # Remove None values
    payload = {k: v for k, v in payload.items() if v is not None}

    try:
        resp = requests.post(
            f"{PAWAPAY_API_URL}/deposits",
            json=payload,
            headers=_headers(),
            timeout=TIMEOUT,
        )
        data = resp.json() if resp.content else {}
        logger.info("PawaPay deposit %s → %s %s", dep_id, resp.status_code, data.get("status", ""))
        return {
            "success": resp.status_code in (200, 201),
            "deposit_id": dep_id,
            "status": data.get("status", "UNKNOWN"),
            "raw": data,
        }
    except requests.RequestException as e:
        logger.error("PawaPay deposit failed: %s", e)
        return {"success": False, "deposit_id": dep_id, "status": "ERROR", "raw": {}}


# ───────────────────────── PAYOUT (Driver withdrawal) ──────────────────
def initiate_payout(
    phone_number: str,
    amount: float,
    payout_id: str | None = None,
    description: str = "Mwamba Taxi – Retrait",
) -> dict:
    """Send money to a driver's mobile money account.

    Returns: {"success": bool, "payout_id": str, "status": str, "raw": dict}
    """
    pay_id = payout_id or str(uuid.uuid4())
    payload = {
        "payoutId": pay_id,
        "amount": str(int(amount)),
        "currency": "CDF",
        "correspondent": _correspondent(phone_number),
        "recipient": {
            "type": "MSISDN",
            "address": {"value": phone_number.lstrip("+")},
        },
        "statementDescription": description[:22],
    }

    try:
        resp = requests.post(
            f"{PAWAPAY_API_URL}/payouts",
            json=payload,
            headers=_headers(),
            timeout=TIMEOUT,
        )
        data = resp.json() if resp.content else {}
        logger.info("PawaPay payout %s → %s %s", pay_id, resp.status_code, data.get("status", ""))
        return {
            "success": resp.status_code in (200, 201),
            "payout_id": pay_id,
            "status": data.get("status", "UNKNOWN"),
            "raw": data,
        }
    except requests.RequestException as e:
        logger.error("PawaPay payout failed: %s", e)
        return {"success": False, "payout_id": pay_id, "status": "ERROR", "raw": {}}


# ───────────────────────── REFUND ──────────────────────────────────────
def initiate_refund(deposit_id: str, refund_id: str | None = None) -> dict:
    """Refund a previously completed deposit.

    Returns: {"success": bool, "refund_id": str, "status": str, "raw": dict}
    """
    ref_id = refund_id or str(uuid.uuid4())
    payload = {
        "refundId": ref_id,
        "depositId": deposit_id,
    }

    try:
        resp = requests.post(
            f"{PAWAPAY_API_URL}/refunds",
            json=payload,
            headers=_headers(),
            timeout=TIMEOUT,
        )
        data = resp.json() if resp.content else {}
        logger.info("PawaPay refund %s → %s", ref_id, resp.status_code)
        return {
            "success": resp.status_code in (200, 201),
            "refund_id": ref_id,
            "status": data.get("status", "UNKNOWN"),
            "raw": data,
        }
    except requests.RequestException as e:
        logger.error("PawaPay refund failed: %s", e)
        return {"success": False, "refund_id": ref_id, "status": "ERROR", "raw": {}}


# ───────────────────────── SIGNATURE VERIFICATION ──────────────────────
def verify_callback_signature(payload_bytes: bytes, signature: str) -> bool:
    """Verify PawaPay webhook callback signature using HMAC-SHA256."""
    secret = settings.PAWAPAY_WEBHOOK_SECRET
    if not secret:
        logger.warning("PAWAPAY_WEBHOOK_SECRET not set — skipping verification")
        return True  # Allow in dev
    expected = hmac.new(
        secret.encode(),
        payload_bytes,
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, signature)

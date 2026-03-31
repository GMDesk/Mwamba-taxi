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


# ───────────────── DRC Mobile Money operator prefixes ──────────────────
# Complete prefix mapping for République Démocratique du Congo (+243)
#
# Vodacom (M-Pesa):  81, 82, 83
# Airtel Money:      97, 98, 99, 96, 95, 94
# Orange Money:      80, 84, 85, 89, 86, 87, 88
#
# PawaPay active correspondents for DRC:
#   - VODACOM_CD  (deposits + payouts)
#   - AIRTEL_CD   (deposits + payouts)
#   - ORANGE_CD   (deposits + payouts)
# ───────────────────────────────────────────────────────────────────────

VODACOM_PREFIXES = ("81", "82", "83")
AIRTEL_PREFIXES  = ("97", "98", "99", "96", "95", "94")
ORANGE_PREFIXES  = ("80", "84", "85", "86", "87", "88", "89")

CORRESPONDENT_MAP = {
    "VODACOM_CD": VODACOM_PREFIXES,
    "AIRTEL_CD":  AIRTEL_PREFIXES,
    "ORANGE_CD":  ORANGE_PREFIXES,
}


def _correspondent(phone: str) -> str:
    """Map phone prefix to PawaPay correspondent ID (DRC operators).

    Raises ValueError if the phone number doesn't match a known DRC operator.
    """
    clean = phone.lstrip("+")
    if not clean.startswith("243") or len(clean) < 12:
        raise ValueError(f"Numéro invalide pour la RDC: {phone}")

    suffix = clean[3:5]
    if suffix in VODACOM_PREFIXES:
        return "VODACOM_CD"
    if suffix in AIRTEL_PREFIXES:
        return "AIRTEL_CD"
    if suffix in ORANGE_PREFIXES:
        return "ORANGE_CD"
    raise ValueError(f"Opérateur non reconnu pour le préfixe +243{suffix}")


def get_operator_name(phone: str) -> str:
    """Return the human-readable operator name for a DRC phone number."""
    try:
        corr = _correspondent(phone)
    except ValueError:
        return "Inconnu"
    return {"VODACOM_CD": "Vodacom M-Pesa", "AIRTEL_CD": "Airtel Money", "ORANGE_CD": "Orange Money"}.get(corr, "Inconnu")


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

    try:
        correspondent = _correspondent(phone_number)
    except ValueError as e:
        logger.warning("PawaPay deposit rejected: %s", e)
        return {"success": False, "deposit_id": dep_id, "status": "INVALID_NUMBER", "raw": {"error": str(e)}}

    payload = {
        "depositId": dep_id,
        "amount": str(int(amount)),
        "currency": "CDF",
        "correspondent": correspondent,
        "payer": {
            "type": "MSISDN",
            "address": {"value": phone_number.lstrip("+")},
        },
        "statementDescription": description[:22],  # max 22 chars
    }

    try:
        resp = requests.post(
            f"{PAWAPAY_API_URL}/deposits",
            json=payload,
            headers=_headers(),
            timeout=TIMEOUT,
        )
        data = resp.json() if resp.content else {}
        logger.info("PawaPay deposit %s [%s] → %s %s", dep_id, correspondent, resp.status_code, data.get("status", ""))
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

    try:
        correspondent = _correspondent(phone_number)
    except ValueError as e:
        logger.warning("PawaPay payout rejected: %s", e)
        return {"success": False, "payout_id": pay_id, "status": "INVALID_NUMBER", "raw": {"error": str(e)}}

    payload = {
        "payoutId": pay_id,
        "amount": str(int(amount)),
        "currency": "CDF",
        "correspondent": correspondent,
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
        logger.info("PawaPay payout %s [%s] → %s %s", pay_id, correspondent, resp.status_code, data.get("status", ""))
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
        if settings.DEBUG:
            logger.warning("PAWAPAY_WEBHOOK_SECRET not set \u2014 skipping verification (DEBUG)")
            return True
        logger.error("PAWAPAY_WEBHOOK_SECRET not set in PRODUCTION \u2014 rejecting callback")
        return False
    expected = hmac.new(
        secret.encode(),
        payload_bytes,
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, signature)


# \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500 ACTIVE CORRESPONDENTS \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
def get_active_correspondents() -> dict:
    """Query which correspondents are active on this PawaPay account.

    Use to verify that VODACOM_CD, AIRTEL_CD, and ORANGE_CD are all live.
    Returns: {"success": bool, "correspondents": [...], "raw": dict}
    """
    try:
        resp = requests.get(
            f"{PAWAPAY_API_URL}/active-conf",
            headers=_headers(),
            timeout=TIMEOUT,
        )
        data = resp.json() if resp.content else {}
        return {
            "success": resp.status_code == 200,
            "correspondents": data if isinstance(data, list) else data.get("correspondents", []),
            "raw": data,
        }
    except requests.RequestException as e:
        logger.error("PawaPay active-conf failed: %s", e)
        return {"success": False, "correspondents": [], "raw": {}}

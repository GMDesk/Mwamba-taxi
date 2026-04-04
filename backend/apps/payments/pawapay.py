"""
PawaPay Mobile Money integration — V2 API.

Handles deposits (customer top-up), payouts (driver withdrawal),
and refunds via the PawaPay REST API V2.

Migration from V1 → V2:
  - Endpoints:  /deposits  → /v2/deposits  (same for payouts, refunds, active-conf)
  - Payload:    correspondent → provider (inside accountDetails)
  -             type: MSISDN → type: MMO
  -             address.value → accountDetails.phoneNumber
  -             statementDescription → customerMessage

API docs: https://docs.pawapay.io/v2/
"""
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
# PawaPay active providers for DRC:
#   - VODACOM_MPESA_COD  (deposits + payouts)
#   - AIRTEL_COD          (deposits + payouts)
#   - ORANGE_COD          (deposits + payouts)
# ───────────────────────────────────────────────────────────────────────

VODACOM_PREFIXES = ("81", "82", "83")
AIRTEL_PREFIXES  = ("97", "98", "99", "96", "95", "94")
ORANGE_PREFIXES  = ("80", "84", "85", "86", "87", "88", "89")

PROVIDER_MAP = {
    "VODACOM_MPESA_COD": VODACOM_PREFIXES,
    "AIRTEL_COD":        AIRTEL_PREFIXES,
    "ORANGE_COD":        ORANGE_PREFIXES,
}

# Backward compatibility alias
CORRESPONDENT_MAP = PROVIDER_MAP


def _resolve_provider(phone: str) -> str:
    """Map phone prefix to PawaPay provider ID (DRC operators).

    Raises ValueError if the phone number doesn't match a known DRC operator.
    """
    clean = phone.lstrip("+")
    if not clean.startswith("243") or len(clean) < 12:
        raise ValueError(f"Numéro invalide pour la RDC: {phone}")

    suffix = clean[3:5]
    if suffix in VODACOM_PREFIXES:
        return "VODACOM_MPESA_COD"
    if suffix in AIRTEL_PREFIXES:
        return "AIRTEL_COD"
    if suffix in ORANGE_PREFIXES:
        return "ORANGE_COD"
    raise ValueError(f"Opérateur non reconnu pour le préfixe +243{suffix}")


# Backward compatibility alias
_correspondent = _resolve_provider


def get_operator_name(phone: str) -> str:
    """Return the human-readable operator name for a DRC phone number."""
    try:
        provider = _resolve_provider(phone)
    except ValueError:
        return "Inconnu"
    return {
        "VODACOM_MPESA_COD": "Vodacom M-Pesa",
        "AIRTEL_COD": "Airtel Money",
        "ORANGE_COD": "Orange Money",
    }.get(provider, "Inconnu")


# ───────────────────────── DEPOSIT (Top-up wallet) ─────────────────────
def initiate_deposit(
    phone_number: str,
    amount: float,
    deposit_id: str | None = None,
    description: str = "Mwamba Taxi",
) -> dict:
    """Request a deposit from a customer's mobile money account (V2 API).

    Returns: {"success": bool, "deposit_id": str, "status": str, "raw": dict}
    """
    dep_id = deposit_id or str(uuid.uuid4())

    try:
        provider = _resolve_provider(phone_number)
    except ValueError as e:
        logger.warning("PawaPay deposit rejected: %s", e)
        return {"success": False, "deposit_id": dep_id, "status": "INVALID_NUMBER", "raw": {"error": str(e)}}

    payload = {
        "depositId": dep_id,
        "amount": str(int(amount)),
        "currency": "CDF",
        "payer": {
            "type": "MMO",
            "accountDetails": {
                "phoneNumber": phone_number.lstrip("+"),
                "provider": provider,
            },
        },
        "customerMessage": description[:22],
    }

    try:
        resp = requests.post(
            f"{PAWAPAY_API_URL}/v2/deposits",
            json=payload,
            headers=_headers(),
            timeout=TIMEOUT,
        )
        data = resp.json() if resp.content else {}
        logger.info("PawaPay deposit %s [%s] → %s %s", dep_id, provider, resp.status_code, data.get("status", ""))
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
    description: str = "Mwamba Taxi",
) -> dict:
    """Send money to a driver's mobile money account (V2 API).

    Returns: {"success": bool, "payout_id": str, "status": str, "raw": dict}
    """
    pay_id = payout_id or str(uuid.uuid4())

    try:
        provider = _resolve_provider(phone_number)
    except ValueError as e:
        logger.warning("PawaPay payout rejected: %s", e)
        return {"success": False, "payout_id": pay_id, "status": "INVALID_NUMBER", "raw": {"error": str(e)}}

    payload = {
        "payoutId": pay_id,
        "amount": str(int(amount)),
        "currency": "CDF",
        "recipient": {
            "type": "MMO",
            "accountDetails": {
                "phoneNumber": phone_number.lstrip("+"),
                "provider": provider,
            },
        },
        "customerMessage": description[:22],
    }

    try:
        resp = requests.post(
            f"{PAWAPAY_API_URL}/v2/payouts",
            json=payload,
            headers=_headers(),
            timeout=TIMEOUT,
        )
        data = resp.json() if resp.content else {}
        logger.info("PawaPay payout %s [%s] → %s %s", pay_id, provider, resp.status_code, data.get("status", ""))
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
    """Refund a previously completed deposit (V2 API).

    Returns: {"success": bool, "refund_id": str, "status": str, "raw": dict}
    """
    ref_id = refund_id or str(uuid.uuid4())
    payload = {
        "refundId": ref_id,
        "depositId": deposit_id,
    }

    try:
        resp = requests.post(
            f"{PAWAPAY_API_URL}/v2/refunds",
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


# ───────────────────────── CALLBACK VERIFICATION ──────────────────────
def verify_callback_signature(payload_bytes: bytes, signature: str) -> bool:
    """Verify PawaPay callback origin.

    PawaPay V2 uses RFC-9421 HTTP Message Signatures (asymmetric keys),
    NOT a shared HMAC secret.  Signed callbacks are an optional feature
    enabled in Dashboard → System configuration → API tokens → Security.

    For now we accept all callbacks.  Enable RFC-9421 verification later
    once signed callbacks are turned on in the PawaPay dashboard.
    """
    # TODO: implement RFC-9421 signature verification when signed callbacks
    #       are enabled in the PawaPay production dashboard.
    return True


# ───────────────────────── ACTIVE CONFIGURATION ──────────────────────
def get_active_correspondents() -> dict:
    """Query which providers are active on this PawaPay account (V2 API).

    Returns: {"success": bool, "correspondents": [...], "raw": dict}
    """
    try:
        resp = requests.get(
            f"{PAWAPAY_API_URL}/v2/active-conf",
            headers=_headers(),
            timeout=TIMEOUT,
        )
        data = resp.json() if resp.content else {}
        return {
            "success": resp.status_code == 200,
            "correspondents": data if isinstance(data, list) else data.get("countries", []),
            "raw": data,
        }
    except requests.RequestException as e:
        logger.error("PawaPay active-conf failed: %s", e)
        return {"success": False, "correspondents": [], "raw": {}}

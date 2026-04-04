"""
PawaPay Mobile Money integration — V2 API.

Handles deposits (customer top-up), payouts (driver withdrawal),
and refunds via the PawaPay REST API V2.

API docs: https://docs.pawapay.io/v2/
Signatures: https://docs.pawapay.io/v2/docs/signatures
"""
import base64
import hashlib
import json
import logging
import uuid
from datetime import datetime, timezone
from urllib.parse import urlparse

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils
from django.conf import settings

logger = logging.getLogger(__name__)

PAWAPAY_API_URL = getattr(settings, "PAWAPAY_API_URL", "https://api.sandbox.pawapay.io")
TIMEOUT = 30

# ───────────────── RFC-9421 HTTP Message Signatures ────────────────────
_SIGNING_KEY = None
_SIGNING_KEY_ID = getattr(settings, "PAWAPAY_SIGNING_KEY_ID", "")


def _get_signing_key():
    """Lazy-load the ECDSA P-256 private key from settings."""
    global _SIGNING_KEY
    if _SIGNING_KEY is not None:
        return _SIGNING_KEY
    key_pem = getattr(settings, "PAWAPAY_SIGNING_KEY", "")
    if not key_pem:
        return None
    _SIGNING_KEY = serialization.load_pem_private_key(
        key_pem.encode() if isinstance(key_pem, str) else key_pem,
        password=None,
    )
    return _SIGNING_KEY


def _sign_request(method: str, url: str, body: bytes, content_type: str) -> dict:
    """Build RFC-9421 signature headers for a PawaPay financial request.

    Returns dict of extra headers (Content-Digest, Signature-Date,
    Signature, Signature-Input).  Returns {} if no signing key is configured.
    """
    key = _get_signing_key()
    if key is None:
        return {}

    key_id = _SIGNING_KEY_ID or "MWAMBA_KEY"
    parsed = urlparse(url)
    authority = parsed.netloc
    path = parsed.path

    # 1. Content-Digest (SHA-512)
    digest_bytes = hashlib.sha512(body).digest()
    content_digest = f"sha-512=:{base64.b64encode(digest_bytes).decode()}:"

    # 2. Signature-Date
    now = datetime.now(timezone.utc)
    sig_date = now.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    created = int(now.timestamp())
    expires = created + 60

    # 3. Signature base (RFC-9421 §2.5)
    sig_params = (
        f'("@method" "@authority" "@path" "signature-date" '
        f'"content-digest" "content-type");'
        f'alg="ecdsa-p256-sha256";keyid="{key_id}";'
        f"created={created};expires={expires}"
    )
    sig_base = "\n".join([
        f'"@method": {method}',
        f'"@authority": {authority}',
        f'"@path": {path}',
        f'"signature-date": {sig_date}',
        f'"content-digest": {content_digest}',
        f'"content-type": {content_type}',
        f'"@signature-params": {sig_params}',
    ])

    # 4. ECDSA P-256 SHA-256 signature
    signature = key.sign(sig_base.encode("utf-8"), ec.ECDSA(hashes.SHA256()))
    sig_b64 = base64.b64encode(signature).decode()

    return {
        "Content-Digest": content_digest,
        "Signature-Date": sig_date,
        "Signature": f"sig-pp=:{sig_b64}:",
        "Signature-Input": f"sig-pp={sig_params}",
    }


def _signed_post(url: str, payload: dict) -> requests.Response:
    """POST with Bearer auth + optional RFC-9421 HTTP Message Signature."""
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    hdrs = {
        "Authorization": f"Bearer {settings.PAWAPAY_API_TOKEN}",
        "Content-Type": "application/json",
    }
    hdrs.update(_sign_request("POST", url, body, hdrs["Content-Type"]))
    return requests.post(url, data=body, headers=hdrs, timeout=TIMEOUT)


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
        resp = _signed_post(f"{PAWAPAY_API_URL}/v2/deposits", payload)
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
        resp = _signed_post(f"{PAWAPAY_API_URL}/v2/payouts", payload)
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
        resp = _signed_post(f"{PAWAPAY_API_URL}/v2/refunds", payload)
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

"""
Wallet service — business logic for wallet operations.

All wallet mutations go through this module to ensure proper
transaction logging and consistency.
"""
import logging
from decimal import Decimal

from django.db import transaction as db_transaction

from .models import Wallet, WalletTransaction

logger = logging.getLogger(__name__)


def get_or_create_wallet(user) -> Wallet:
    """Get existing wallet or create one for the user."""
    wallet, _ = Wallet.objects.get_or_create(user=user)
    return wallet


@db_transaction.atomic
def credit_wallet(
    wallet: Wallet,
    amount: Decimal,
    tx_type: str = WalletTransaction.TxType.DEPOSIT,
    description: str = "",
    ride=None,
    provider_reference: str = "",
    metadata: dict | None = None,
) -> WalletTransaction:
    """Credit (add money to) a wallet and log the transaction."""
    # Lock the wallet row
    wallet = Wallet.objects.select_for_update().get(pk=wallet.pk)
    wallet.credit(amount)
    tx = WalletTransaction.objects.create(
        wallet=wallet,
        tx_type=tx_type,
        amount=amount,
        balance_after=wallet.balance,
        status=WalletTransaction.Status.COMPLETED,
        description=description,
        ride=ride,
        provider_reference=provider_reference,
        metadata=metadata,
    )
    logger.info("Wallet %s credited %s → balance %s", wallet.user_id, amount, wallet.balance)
    return tx


@db_transaction.atomic
def debit_wallet(
    wallet: Wallet,
    amount: Decimal,
    tx_type: str = WalletTransaction.TxType.RIDE_PAYMENT,
    description: str = "",
    ride=None,
    provider_reference: str = "",
    metadata: dict | None = None,
) -> WalletTransaction:
    """Debit (remove money from) a wallet and log the transaction."""
    wallet = Wallet.objects.select_for_update().get(pk=wallet.pk)
    wallet.debit(amount)
    tx = WalletTransaction.objects.create(
        wallet=wallet,
        tx_type=tx_type,
        amount=-amount,
        balance_after=wallet.balance,
        status=WalletTransaction.Status.COMPLETED,
        description=description,
        ride=ride,
        provider_reference=provider_reference,
        metadata=metadata,
    )
    logger.info("Wallet %s debited %s → balance %s", wallet.user_id, amount, wallet.balance)
    return tx


@db_transaction.atomic
def hold_funds(wallet: Wallet, amount: Decimal, ride=None) -> WalletTransaction:
    """Pre-authorize funds for an upcoming ride."""
    wallet = Wallet.objects.select_for_update().get(pk=wallet.pk)
    wallet.hold(amount)
    tx = WalletTransaction.objects.create(
        wallet=wallet,
        tx_type=WalletTransaction.TxType.RIDE_HOLD,
        amount=-amount,
        balance_after=wallet.balance,
        status=WalletTransaction.Status.COMPLETED,
        description="Pré-autorisation course",
        ride=ride,
    )
    logger.info("Wallet %s hold %s for ride %s", wallet.user_id, amount, ride)
    return tx


@db_transaction.atomic
def release_hold(wallet: Wallet, amount: Decimal, ride=None) -> WalletTransaction:
    """Release previously held funds."""
    wallet = Wallet.objects.select_for_update().get(pk=wallet.pk)
    wallet.release_hold(amount)
    tx = WalletTransaction.objects.create(
        wallet=wallet,
        tx_type=WalletTransaction.TxType.RIDE_HOLD_RELEASE,
        amount=amount,
        balance_after=wallet.balance,
        status=WalletTransaction.Status.COMPLETED,
        description="Libération pré-autorisation",
        ride=ride,
    )
    logger.info("Wallet %s released hold %s for ride %s", wallet.user_id, amount, ride)
    return tx


@db_transaction.atomic
def process_ride_payment(ride) -> dict:
    """End-of-ride payment: debit passenger, credit driver, take commission.

    Returns dict with payment details.
    """
    from django.conf import settings as conf

    price = ride.final_price or ride.estimated_price
    commission_rate = Decimal(str(conf.COMMISSION_RATE)) / Decimal("100")
    commission = round(price * commission_rate, 2)
    driver_share = price - commission

    # Update ride financials
    ride.commission_amount = commission
    ride.driver_earnings = driver_share
    ride.save(update_fields=["commission_amount", "driver_earnings"])

    passenger_wallet = get_or_create_wallet(ride.passenger)

    # Release any hold first
    if passenger_wallet.held_amount > 0:
        release_hold(passenger_wallet, passenger_wallet.held_amount, ride=ride)
        # Refresh after release
        passenger_wallet.refresh_from_db()

    # Debit passenger
    debit_wallet(
        passenger_wallet,
        price,
        tx_type=WalletTransaction.TxType.RIDE_PAYMENT,
        description=f"Course → {ride.destination_address[:50]}",
        ride=ride,
    )

    # Credit driver
    if ride.driver:
        driver_wallet = get_or_create_wallet(ride.driver)
        credit_wallet(
            driver_wallet,
            driver_share,
            tx_type=WalletTransaction.TxType.RIDE_EARNING,
            description=f"Revenu course de {ride.pickup_address[:50]}",
            ride=ride,
        )

    return {
        "total_price": price,
        "commission": commission,
        "driver_share": driver_share,
        "method": "wallet",
    }

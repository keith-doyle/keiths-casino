import os
from datetime import datetime, timezone
from dotenv import load_dotenv
from firebase_service import get_db

load_dotenv()

MONTHLY_PRICE_ID = os.getenv("STRIPE_MONTHLY_PRICE_ID")
YEARLY_PRICE_ID = os.getenv("STRIPE_YEARLY_PRICE_ID")


def now_utc():
    return datetime.now(timezone.utc)


def read_stripe_value(obj, key, default=None):
    try:
        if key in obj:
            return obj[key]
    except Exception:
        pass

    return default


def get_price_id_from_subscription(subscription):
    try:
        return subscription["items"]["data"][0]["price"]["id"]
    except Exception:
        return None


def get_period_end_from_subscription(subscription):
    try:
        current_period_end = subscription["current_period_end"]
        return datetime.fromtimestamp(current_period_end, tz=timezone.utc)
    except Exception:
        return None


def get_premium_tier(price_id):
    if price_id == MONTHLY_PRICE_ID:
        return "monthly"

    if price_id == YEARLY_PRICE_ID:
        return "yearly"

    return "unknown"


def get_premium_status(subscription):
    status = read_stripe_value(subscription, "status", "unknown")
    cancel_at_period_end = read_stripe_value(subscription, "cancel_at_period_end", False)

    if cancel_at_period_end and status in ["active", "trialing"]:
        return "canceling"

    return status


def subscription_has_premium_access(subscription):
    status = read_stripe_value(subscription, "status", "unknown")
    return status in ["active", "trialing"]


def find_user_by_stripe_customer_id(customer_id):
    if not customer_id:
        return None

    db = get_db()

    matches = (
        db.collection("users")
        .where("stripeCustomerId", "==", customer_id)
        .limit(1)
        .stream()
    )

    for doc in matches:
        return doc.id

    return None


def update_user_subscription_from_checkout(uid, customer_id, subscription_id, subscription):
    db = get_db()

    price_id = get_price_id_from_subscription(subscription)

    db.collection("users").document(uid).set(
        {
            "isPremium": subscription_has_premium_access(subscription),
            "premiumTier": get_premium_tier(price_id),
            "premiumStatus": get_premium_status(subscription),
            "premiumUpdatedAt": now_utc(),
            "premiumExpiresAt": get_period_end_from_subscription(subscription),
            "premiumSource": "stripe",
            "stripeCustomerId": customer_id,
            "stripeSubscriptionId": subscription_id,
            "stripePriceId": price_id,
        },
        merge=True,
    )


def update_user_subscription(subscription):
    customer_id = read_stripe_value(subscription, "customer")
    uid = find_user_by_stripe_customer_id(customer_id)

    if not uid:
        return False

    db = get_db()
    price_id = get_price_id_from_subscription(subscription)
    subscription_id = read_stripe_value(subscription, "id")

    db.collection("users").document(uid).set(
        {
            "isPremium": subscription_has_premium_access(subscription),
            "premiumTier": get_premium_tier(price_id),
            "premiumStatus": get_premium_status(subscription),
            "premiumUpdatedAt": now_utc(),
            "premiumExpiresAt": get_period_end_from_subscription(subscription),
            "premiumSource": "stripe",
            "stripeCustomerId": customer_id,
            "stripeSubscriptionId": subscription_id,
            "stripePriceId": price_id,
        },
        merge=True,
    )

    return True


def cancel_user_subscription(subscription):
    customer_id = read_stripe_value(subscription, "customer")
    uid = find_user_by_stripe_customer_id(customer_id)

    if not uid:
        return False

    db = get_db()

    db.collection("users").document(uid).set(
        {
            "isPremium": False,
            "premiumStatus": "canceled",
            "premiumUpdatedAt": now_utc(),
            "premiumExpiresAt": now_utc(),
            "premiumSource": "stripe",
            "stripeSubscriptionId": read_stripe_value(subscription, "id"),
        },
        merge=True,
    )

    return True


def get_user_premium_status(uid):
    db = get_db()
    doc = db.collection("users").document(uid).get()

    if not doc.exists:
        return None

    user = doc.to_dict() or {}

    return {
        "uid": uid,
        "isPremium": bool(user.get("isPremium", False)),
        "premiumTier": user.get("premiumTier", "free"),
        "premiumStatus": user.get("premiumStatus", "free"),
        "premiumExpiresAt": str(user.get("premiumExpiresAt")) if user.get("premiumExpiresAt") else None,
        "stripeCustomerId": user.get("stripeCustomerId"),
        "stripeSubscriptionId": user.get("stripeSubscriptionId"),
        "stripePriceId": user.get("stripePriceId"),
    }
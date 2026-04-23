from firebase_service import get_db
from datetime import datetime


def upgrade_user_to_premium(uid, customer_id, subscription_id, price_id):
    db = get_db()

    user_ref = db.collection("users").document(uid)

    user_ref.set({
        "isPremium": True,
        "premiumTier": "pro",
        "premiumStatus": "active",
        "stripeCustomerId": customer_id,
        "stripeSubscriptionId": subscription_id,
        "stripePriceId": price_id,
        "premiumUpdatedAt": datetime.utcnow(),
    }, merge=True)
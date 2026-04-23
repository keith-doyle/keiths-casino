import os
import stripe
from dotenv import load_dotenv

load_dotenv()

stripe.api_key = os.getenv("STRIPE_SECRET_KEY")


def get_price_id(plan: str) -> str:
    clean_plan = plan.lower().strip()

    if clean_plan == "monthly":
        price_id = os.getenv("STRIPE_MONTHLY_PRICE_ID")
    elif clean_plan == "yearly":
        price_id = os.getenv("STRIPE_YEARLY_PRICE_ID")
    else:
        raise ValueError("Invalid plan")

    if not price_id:
        raise ValueError("Stripe price id is missing")

    return price_id


def create_checkout_session(uid: str, email: str, plan: str) -> str:
    price_id = get_price_id(plan)

    session = stripe.checkout.Session.create(
        mode="subscription",
        customer_email=email,
        client_reference_id=uid,
        line_items=[
            {
                "price": price_id,
                "quantity": 1,
            }
        ],
        success_url=os.getenv("STRIPE_SUCCESS_URL"),
        cancel_url=os.getenv("STRIPE_CANCEL_URL"),
        metadata={
            "uid": uid,
            "email": email,
            "plan": plan,
        },
        subscription_data={
            "metadata": {
                "uid": uid,
                "email": email,
                "plan": plan,
            }
        },
    )

    return session.url


def construct_webhook_event(payload: bytes, signature: str):
    webhook_secret = os.getenv("STRIPE_WEBHOOK_SECRET")

    return stripe.Webhook.construct_event(
        payload=payload,
        sig_header=signature,
        secret=webhook_secret,
    )
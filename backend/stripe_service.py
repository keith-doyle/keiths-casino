import os
import stripe
from dotenv import load_dotenv

load_dotenv()

stripe.api_key = os.getenv("STRIPE_SECRET_KEY")


def require_env(name: str) -> str:
    value = os.getenv(name)

    if not value:
        raise ValueError(f"{name} is missing")

    return value


def get_price_id(plan: str) -> str:
    clean_plan = plan.lower().strip()

    if clean_plan == "monthly":
        return require_env("STRIPE_MONTHLY_PRICE_ID")

    if clean_plan == "yearly":
        return require_env("STRIPE_YEARLY_PRICE_ID")

    raise ValueError("Invalid plan")


def create_checkout_session(uid: str, email: str, plan: str) -> str:
    if not stripe.api_key:
        raise ValueError("STRIPE_SECRET_KEY is missing")

    clean_plan = plan.lower().strip()
    price_id = get_price_id(clean_plan)

    success_url = require_env("STRIPE_SUCCESS_URL")
    cancel_url = require_env("STRIPE_CANCEL_URL")

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
        success_url=success_url,
        cancel_url=cancel_url,
        metadata={
            "uid": uid,
            "email": email,
            "plan": clean_plan,
        },
        subscription_data={
            "metadata": {
                "uid": uid,
                "email": email,
                "plan": clean_plan,
            }
        },
    )

    return session.url


def construct_webhook_event(payload: bytes, signature: str):
    webhook_secret = require_env("STRIPE_WEBHOOK_SECRET")

    return stripe.Webhook.construct_event(
        payload=payload,
        sig_header=signature,
        secret=webhook_secret,
    )


def retrieve_subscription(subscription_id: str):
    return stripe.Subscription.retrieve(subscription_id)


def create_portal_session(customer_id: str) -> str:
    return_url = require_env("STRIPE_PORTAL_RETURN_URL")

    session = stripe.billing_portal.Session.create(
        customer=customer_id,
        return_url=return_url,
    )

    return session.url
from fastapi import APIRouter, HTTPException, Request, Header
from pydantic import BaseModel

from stripe_service import (
    create_checkout_session,
    construct_webhook_event,
    retrieve_subscription,
    create_portal_session,
)
from premium_service import (
    update_user_subscription_from_checkout,
    update_user_subscription,
    cancel_user_subscription,
    get_user_premium_status,
)

router = APIRouter(prefix="/billing", tags=["billing"])


class CheckoutRequest(BaseModel):
    uid: str
    email: str
    plan: str


class PortalRequest(BaseModel):
    uid: str


def read_stripe_value(obj, key, default=None):
    try:
        if key in obj:
            return obj[key]
    except Exception:
        pass

    return default


@router.post("/create-checkout-session")
async def create_checkout_session_route(data: CheckoutRequest):
    try:
        checkout_url = create_checkout_session(
            uid=data.uid,
            email=data.email,
            plan=data.plan,
        )

        return {
            "checkoutUrl": checkout_url,
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/create-portal-session")
async def create_portal_session_route(data: PortalRequest):
    try:
        premium_status = get_user_premium_status(data.uid)

        if not premium_status:
            raise HTTPException(status_code=404, detail="User not found")

        customer_id = premium_status.get("stripeCustomerId")

        if not customer_id:
            raise HTTPException(status_code=400, detail="No Stripe customer found for user")

        portal_url = create_portal_session(customer_id)

        return {
            "portalUrl": portal_url,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/status/{uid}")
async def billing_status_route(uid: str):
    premium_status = get_user_premium_status(uid)

    if not premium_status:
        raise HTTPException(status_code=404, detail="User not found")

    return premium_status


@router.post("/webhook")
async def stripe_webhook_route(
    request: Request,
    stripe_signature: str | None = Header(default=None, alias="stripe-signature"),
):
    if not stripe_signature:
        raise HTTPException(status_code=400, detail="Missing Stripe signature")

    payload = await request.body()

    try:
        event = construct_webhook_event(payload, stripe_signature)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    event_type = event["type"]
    data_object = event["data"]["object"]
    object_id = read_stripe_value(data_object, "id")

    if event_type == "checkout.session.completed":
        metadata = read_stripe_value(data_object, "metadata", {})
        uid = read_stripe_value(metadata, "uid")
        customer_id = read_stripe_value(data_object, "customer")
        subscription_id = read_stripe_value(data_object, "subscription")

        if not uid:
            raise HTTPException(status_code=400, detail="Missing uid in Stripe metadata")

        if not subscription_id:
            raise HTTPException(status_code=400, detail="Missing subscription id")

        subscription = retrieve_subscription(subscription_id)

        update_user_subscription_from_checkout(
            uid=uid,
            customer_id=customer_id,
            subscription_id=subscription_id,
            subscription=subscription,
        )

    elif event_type == "customer.subscription.updated":
        update_user_subscription(data_object)

    elif event_type == "customer.subscription.deleted":
        cancel_user_subscription(data_object)

    return {
        "received": True,
        "eventType": event_type,
        "objectId": object_id,
    }


@router.get("/success")
async def billing_success():
    return {
        "status": "success",
        "message": "Payment completed. You can return to the app.",
    }


@router.get("/cancel")
async def billing_cancel():
    return {
        "status": "cancelled",
        "message": "Checkout was cancelled.",
    }


@router.get("/return")
async def billing_return():
    return {
        "status": "returned",
        "message": "You can return to the app.",
    }
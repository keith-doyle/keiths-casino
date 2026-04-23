import stripe
from fastapi import APIRouter, HTTPException, Request, Header
from pydantic import BaseModel

from stripe_service import create_checkout_session, construct_webhook_event
from premium_service import upgrade_user_to_premium

router = APIRouter(prefix="/billing", tags=["billing"])


class CheckoutRequest(BaseModel):
    uid: str
    email: str
    plan: str


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

    if event_type == "checkout.session.completed":
        uid = data_object.get("metadata", {}).get("uid")
        customer_id = data_object.get("customer")
        subscription_id = data_object.get("subscription")

        if not uid:
            raise HTTPException(status_code=400, detail="Missing uid in Stripe metadata")

        if not subscription_id:
            raise HTTPException(status_code=400, detail="Missing subscription id")

        subscription = stripe.Subscription.retrieve(subscription_id)
        price_id = subscription["items"]["data"][0]["price"]["id"]

        upgrade_user_to_premium(
            uid=uid,
            customer_id=customer_id,
            subscription_id=subscription_id,
            price_id=price_id,
        )

    return {
        "received": True,
        "eventType": event_type,
        "objectId": data_object.get("id"),
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
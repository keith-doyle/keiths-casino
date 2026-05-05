from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from firebase_service import get_db

router = APIRouter(prefix="/rewards", tags=["rewards"])

PREMIUM_REWARDS = [10, 25, 50, 100, 150, 250, 500]
FREE_REWARD = 10

#body with uid for claiming daily reward
class DailyRewardRequest(BaseModel):
    uid: str

#create timezone aware 
def now_utc():
    return datetime.now(timezone.utc)

#normalises firestore timestamps
def normalize_firestore_datetime(value):
    if value is None:
        return None

    if hasattr(value, "timestamp"):
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)

        return value.astimezone(timezone.utc)

    return None

#chooses reward from premium reward track based on streak
def calculate_premium_reward(streak: int) -> int:
    if streak <= 0:
        return PREMIUM_REWARDS[0]

    index = min(streak, len(PREMIUM_REWARDS)) - 1
    return PREMIUM_REWARDS[index]

#Blocks claim if under 20 hours, resets streak if over 48 hours 
def calculate_next_streak(last_claim, current_streak: int) -> int:
    current_time = now_utc()

    if last_claim is None:
        return 1

    elapsed = current_time - last_claim

    if elapsed < timedelta(hours=20):
        raise HTTPException(
            status_code=400,
            detail="Daily reward already claimed",
        )

    if elapsed > timedelta(hours=48):
        return 1

    return current_streak + 1

#Claims daily coins and updates streak
@router.post("/claim-daily")
async def claim_daily_reward(data: DailyRewardRequest):
    db = get_db()

    user_ref = db.collection("users").document(data.uid)
    user_snapshot = user_ref.get()

    if not user_snapshot.exists:
        raise HTTPException(status_code=404, detail="User not found")

    user_data = user_snapshot.to_dict() or {}

    coins = int(user_data.get("coins", 0))
    current_streak = int(user_data.get("loginStreak", 0))
    is_premium = bool(user_data.get("isPremium", False))
    last_claim = normalize_firestore_datetime(user_data.get("lastLoginReward"))

    next_streak = calculate_next_streak(last_claim, current_streak)

    if is_premium:
        reward = calculate_premium_reward(next_streak)
    else:
        reward = FREE_REWARD

    new_coin_total = coins + reward
    current_time = now_utc()

    user_ref.set(
        {
            "coins": new_coin_total,
            "loginStreak": next_streak,
            "lastLoginReward": current_time,
            "lastLoginRewardAmount": reward,
            "lastLoginRewardWasPremium": is_premium,
            "updatedAt": current_time,
        },
        merge=True,
    )

    return {
        "claimed": True,
        "reward": reward,
        "coins": new_coin_total,
        "loginStreak": next_streak,
        "isPremium": is_premium,
        "message": "Daily reward claimed successfully",
    }

#Reads user reward state and returns can claim, timer ,streak, next reward etc 
@router.get("/status/{uid}")
async def get_daily_reward_status(uid: str):
    db = get_db()

    user_ref = db.collection("users").document(uid)
    user_snapshot = user_ref.get()

    if not user_snapshot.exists:
        raise HTTPException(status_code=404, detail="User not found")

    user_data = user_snapshot.to_dict() or {}

    current_streak = int(user_data.get("loginStreak", 0))
    is_premium = bool(user_data.get("isPremium", False))
    last_claim = normalize_firestore_datetime(user_data.get("lastLoginReward"))
    current_time = now_utc()

    can_claim = True
    seconds_until_next_claim = 0

    if last_claim is not None:
        next_available_time = last_claim + timedelta(hours=20)

        if current_time < next_available_time:
            can_claim = False
            seconds_until_next_claim = int(
                (next_available_time - current_time).total_seconds()
            )

    if can_claim:
        try:
            next_streak = calculate_next_streak(last_claim, current_streak)
        except HTTPException:
            next_streak = current_streak
    else:
        next_streak = current_streak

    if is_premium:
        next_reward = calculate_premium_reward(next_streak)
        reward_track = PREMIUM_REWARDS
    else:
        next_reward = FREE_REWARD
        reward_track = [FREE_REWARD]

    return {
        "canClaim": can_claim,
        "secondsUntilNextClaim": seconds_until_next_claim,
        "loginStreak": current_streak,
        "nextStreak": next_streak,
        "nextReward": next_reward,
        "isPremium": is_premium,
        "rewardTrack": reward_track,
    }
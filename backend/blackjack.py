import random
from dataclasses import dataclass
from typing import Dict, List, Optional
from uuid import uuid4

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
SUITS = ["H", "D", "C", "S"]

router = APIRouter(prefix="/blackjack", tags=["blackjack"])


def _fresh_ordered_deck() -> List[str]:
    return [f"{rank}{suit}" for suit in SUITS for rank in RANKS]


def _shuffled_deck() -> List[str]:
    deck = _fresh_ordered_deck()
    random.shuffle(deck)
    return deck


def _card_value(card_id: str) -> int:
    rank = card_id[:-1]
    if rank == "A":
        return 11
    if rank in {"J", "Q", "K"}:
        return 10
    return int(rank)


class ActionRequest(BaseModel):
    game_id: Optional[str] = None


@dataclass
class BlackjackState:
    game_id: str
    deck: List[str]
    player: List[str]
    dealer: List[str]
    status: str
    game_over: bool
    result: Optional[str]  # "Win" | "Loss" | "Push" | None


_games: Dict[str, BlackjackState] = {}


def _hand_value(cards: List[str]) -> int:
    total = sum(_card_value(c) for c in cards)
    aces = sum(1 for c in cards if c[:-1] == "A")

    while total > 21 and aces > 0:
        total -= 10
        aces -= 1

    return total


def _deal_card(state: BlackjackState, target: List[str]) -> None:
    if not state.deck:
        state.deck = _shuffled_deck()
    target.append(state.deck.pop())


def _start_new_game_state() -> BlackjackState:
    state = BlackjackState(
        game_id=uuid4().hex,
        deck=_shuffled_deck(),
        player=[],
        dealer=[],
        status="Your turn",
        game_over=False,
        result=None,
    )

    _deal_card(state, state.player)
    _deal_card(state, state.dealer)
    _deal_card(state, state.player)
    _deal_card(state, state.dealer)

    p = _hand_value(state.player)
    d = _hand_value(state.dealer)

    if p == 21 and d == 21:
        state.status = "Push: both have blackjack"
        state.game_over = True
        state.result = "Push"
    elif p == 21:
        state.status = "Blackjack! You win"
        state.game_over = True
        state.result = "Win"
    elif d == 21:
        state.status = "Dealer has blackjack"
        state.game_over = True
        state.result = "Loss"
    else:
        state.status = "Your turn"

    return state


def _finish_round(state: BlackjackState) -> None:
    if state.game_over:
        return

    while _hand_value(state.dealer) < 17:
        _deal_card(state, state.dealer)

    p = _hand_value(state.player)
    d = _hand_value(state.dealer)

    if p > 21:
        state.status = "You bust – dealer wins"
        state.result = "Loss"
    elif d > 21:
        state.status = "Dealer busts – you win!"
        state.result = "Win"
    elif p > d:
        state.status = "You win!"
        state.result = "Win"
    elif p < d:
        state.status = "Dealer wins"
        state.result = "Loss"
    else:
        state.status = "Push (tie)"
        state.result = "Push"

    state.game_over = True


def _state_to_payload(state: BlackjackState) -> dict:
    return {
        "game_id": state.game_id,
        "player_cards": state.player,
        "dealer_cards": state.dealer,
        "player_total": _hand_value(state.player),
        "dealer_total": _hand_value(state.dealer),
        "status": state.status,
        "game_over": state.game_over,
        "dealer_revealed": state.game_over,
        "result": state.result,
    }


def _get_game_or_404(game_id: str) -> BlackjackState:
    state = _games.get(game_id)
    if state is None:
        raise HTTPException(status_code=404, detail="Game not found. Start a new hand.")
    return state


def deal() -> dict:
    state = _start_new_game_state()
    _games[state.game_id] = state
    return _state_to_payload(state)


def hit(game_id: Optional[str]) -> dict:
    if not game_id:
        raise HTTPException(status_code=400, detail="Missing game_id. Send deal first.")

    state = _get_game_or_404(game_id)

    if state.game_over:
        return _state_to_payload(state)

    _deal_card(state, state.player)
    p = _hand_value(state.player)

    if p > 21:
        state.status = "You bust – dealer wins"
        state.game_over = True
        state.result = "Loss"
    else:
        state.status = "Your turn"

    return _state_to_payload(state)


def stand(game_id: Optional[str]) -> dict:
    if not game_id:
        raise HTTPException(status_code=400, detail="Missing game_id. Send deal first.")

    state = _get_game_or_404(game_id)
    _finish_round(state)
    return _state_to_payload(state)


@router.post("/deal")
def blackjack_deal():
    return deal()


@router.post("/hit")
def blackjack_hit(req: ActionRequest):
    return hit(req.game_id)


@router.post("/stand")
def blackjack_stand(req: ActionRequest):
    return stand(req.game_id)

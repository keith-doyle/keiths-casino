import random
from dataclasses import dataclass
from typing import List, Optional

from fastapi import APIRouter

RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
SUITS = ["H", "D", "C", "S"]  


def new_deck() -> List[str]:
#Return a fresh ordered 52-card deck as IDs like 'AH', '10S'.
    return [f"{rank}{suit}" for suit in SUITS for rank in RANKS]


def card_value(card_id: str) -> int:
    rank = card_id[:-1] 
    if rank == "A":
        return 11
    if rank in ["J", "Q", "K"]:
        return 10
    return int(rank)



router = APIRouter(prefix="/blackjack", tags=["blackjack"])


#BLACKJACK STATE
@dataclass
class BlackjackState:
    deck: List[str]
    player: List[str]
    dealer: List[str]
    status: str
    game_over: bool


_current_blackjack: Optional[BlackjackState] = None


def _new_deck() -> List[str]:
#Shuffled 52-card deck of IDs.
    deck = new_deck()
    random.shuffle(deck)
    return deck


def _hand_value(cards: List[str]) -> int:
#Blackjack hand value with soft Aces.
    total = sum(card_value(c) for c in cards)
    aces = sum(1 for c in cards if c[:-1] == "A") 
    while total > 21 and aces > 0:
        total -= 10  
        aces -= 1
    return total


def _deal_card(state: BlackjackState, target: List[str]) -> None:
    if not state.deck:
        state.deck = _new_deck()
    target.append(state.deck.pop())


def _start_new_game() -> BlackjackState:
    deck = _new_deck()
    state = BlackjackState(
        deck=deck,
        player=[],
        dealer=[],
        status="Your turn",
        game_over=False,
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
    elif p == 21:
        state.status = "Blackjack! You win"
        state.game_over = True
    else:
        state.status = "Your turn"

    return state


def _finish_round(state: BlackjackState) -> None:
#Dealer plays out hand and result is decided.
    if state.game_over:
        return

    while _hand_value(state.dealer) < 16:
        _deal_card(state, state.dealer)

    p = _hand_value(state.player)
    d = _hand_value(state.dealer)

    if p > 21:
        state.status = "You bust – dealer wins"
    elif d > 21:
        state.status = "Dealer busts – you win!"
    elif p > d:
        state.status = "You win!"
    elif p < d:
        state.status = "Dealer wins"
    else:
        state.status = "Push (tie)"

    state.game_over = True


def _state_to_payload(state: BlackjackState) -> dict:
    return {
        "player_cards": state.player,          
        "dealer_cards": state.dealer,          
        "player_total": _hand_value(state.player),
        "dealer_total": _hand_value(state.dealer),
        "status": state.status,
        "game_over": state.game_over,
        "dealer_revealed": state.game_over,
    }


#ENDPOINTS 
@router.post("/deal")
def blackjack_deal():
#Start a new blackjack hand.
    global _current_blackjack
    _current_blackjack = _start_new_game()
    return _state_to_payload(_current_blackjack)


@router.post("/hit")
def blackjack_hit():
#Player hits.
    global _current_blackjack
    if _current_blackjack is None or _current_blackjack.game_over:
        _current_blackjack = _start_new_game()
        return _state_to_payload(_current_blackjack)

    state = _current_blackjack
    _deal_card(state, state.player)
    p = _hand_value(state.player)

    if p > 21:
        state.status = "You bust – dealer wins"
        state.game_over = True
    else:
        state.status = "Your turn"

    return _state_to_payload(state)


@router.post("/stand")
def blackjack_stand():
#Player stands, dealer plays.
    global _current_blackjack
    if _current_blackjack is None:
        _current_blackjack = _start_new_game()
        return _state_to_payload(_current_blackjack)

    state = _current_blackjack
    _finish_round(state)
    return _state_to_payload(state)

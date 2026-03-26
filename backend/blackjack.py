import random
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from fastapi import APIRouter

RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
SUITS = ["H", "D", "C", "S"]


def new_deck() -> List[str]:
    return [f"{rank}{suit}" for suit in SUITS for rank in RANKS]


def card_value(card_id: str) -> int:
    rank = card_id[:-1]
    if rank == "A":
        return 11
    if rank in ["J", "Q", "K"]:
        return 10
    return int(rank)


router = APIRouter(prefix="/blackjack", tags=["blackjack"])


@dataclass
class BlackjackState:
    deck: List[str]
    player: List[str]
    dealer: List[str]
    status: str
    game_over: bool


_current_blackjack: Optional[BlackjackState] = None


def _new_deck() -> List[str]:
    deck = new_deck()
    random.shuffle(deck)
    return deck


def _hand_value(cards: List[str]) -> int:
    total = sum(card_value(c) for c in cards)
    aces = sum(1 for c in cards if c[:-1] == "A")
    while total > 21 and aces > 0:
        total -= 10
        aces -= 1
    return total


def _deal_card_from_deck(deck: List[str], target: List[str]) -> None:
    if not deck:
        deck.extend(_new_deck())
    target.append(deck.pop())


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


def _result_from_state(state: BlackjackState) -> str | None:
    if not state.game_over:
        return None

    p = _hand_value(state.player)
    d = _hand_value(state.dealer)

    if p > 21:
        return "Loss"
    if d > 21:
        return "Win"
    if p > d:
        return "Win"
    if p < d:
        return "Loss"
    return "Push"


def _state_to_payload(state: BlackjackState) -> dict:
    return {
        "player_cards": state.player,
        "dealer_cards": state.dealer,
        "player_total": _hand_value(state.player),
        "dealer_total": _hand_value(state.dealer),
        "status": state.status,
        "game_over": state.game_over,
        "dealer_revealed": state.game_over,
        "result": _result_from_state(state),
    }


@router.post("/deal")
def blackjack_deal():
    global _current_blackjack
    _current_blackjack = _start_new_game()
    return _state_to_payload(_current_blackjack)


@router.post("/hit")
def blackjack_hit():
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
    global _current_blackjack
    if _current_blackjack is None:
        _current_blackjack = _start_new_game()
        return _state_to_payload(_current_blackjack)

    state = _current_blackjack
    _finish_round(state)
    return _state_to_payload(state)


def deal() -> dict:
    return blackjack_deal()


def hit(game_id: str | None = None) -> dict:
    return blackjack_hit()


def stand(game_id: str | None = None) -> dict:
    return blackjack_stand()


@dataclass
class TablePlayerState:
    id: str
    name: str
    cards: List[str] = field(default_factory=list)
    stood: bool = False
    busted: bool = False
    blackjack: bool = False
    finished: bool = False
    result: Optional[str] = None
    bet: int = 0
    joined_mid_round: bool = False


@dataclass
class RoomBlackjackState:
    room_id: str
    deck: List[str] = field(default_factory=list)
    dealer: List[str] = field(default_factory=list)
    players: Dict[str, TablePlayerState] = field(default_factory=dict)
    player_order: List[str] = field(default_factory=list)
    host_player_id: Optional[str] = None
    turn_player_id: Optional[str] = None
    status: str = "Waiting for players..."
    game_started: bool = False
    game_over: bool = False
    dealer_revealed: bool = False
    betting_open: bool = False


_room_blackjack_games: Dict[str, RoomBlackjackState] = {}


def get_room_game(room_id: str) -> RoomBlackjackState:
    if room_id not in _room_blackjack_games:
        _room_blackjack_games[room_id] = RoomBlackjackState(room_id=room_id)
    return _room_blackjack_games[room_id]


def _reset_player_for_round(player: TablePlayerState) -> None:
    player.cards = []
    player.stood = False
    player.busted = False
    player.blackjack = False
    player.finished = False
    player.result = None
    player.bet = 0
    player.joined_mid_round = False


def _active_player_ids(state: RoomBlackjackState) -> List[str]:
    ids: List[str] = []
    for pid in state.player_order:
        player = state.players.get(pid)
        if player and not player.joined_mid_round:
            ids.append(pid)
    return ids


def _first_active_player(state: RoomBlackjackState) -> Optional[str]:
    for pid in state.player_order:
        player = state.players.get(pid)
        if player and not player.finished and not player.joined_mid_round:
            return pid
    return None


def _next_active_player_after(state: RoomBlackjackState, current_player_id: str) -> Optional[str]:
    if current_player_id not in state.player_order:
        return _first_active_player(state)

    start_index = state.player_order.index(current_player_id) + 1
    for pid in state.player_order[start_index:]:
        player = state.players.get(pid)
        if player and not player.finished and not player.joined_mid_round:
            return pid
    return None


def _all_players_finished(state: RoomBlackjackState) -> bool:
    active_ids = _active_player_ids(state)
    if not active_ids:
        return True
    return all(state.players[pid].finished for pid in active_ids)


def _resolve_player_result(player_total: int, dealer_total: int) -> str:
    if player_total > 21:
        return "Loss"
    if dealer_total > 21:
        return "Win"
    if player_total > dealer_total:
        return "Win"
    if player_total < dealer_total:
        return "Loss"
    return "Push"


def add_room_player(room_id: str, player_id: str, player_name: str) -> RoomBlackjackState:
    state = get_room_game(room_id)

    if player_id in state.players:
        state.players[player_id].name = player_name or state.players[player_id].name
        return state

    player = TablePlayerState(id=player_id, name=player_name)

    if state.game_started and not state.game_over:
        player.joined_mid_round = True
        player.finished = True
        player.result = "Waiting next round"

    state.players[player_id] = player
    state.player_order.append(player_id)

    if not state.host_player_id:
        state.host_player_id = player_id

    if state.game_started and not state.game_over:
        state.status = f"{player_name} joined. They will enter next round."
    else:
        state.status = f"{player_name} joined the table."

    return state


def remove_room_player(room_id: str, player_id: str) -> RoomBlackjackState:
    state = get_room_game(room_id)

    leaving_player = state.players.pop(player_id, None)
    if player_id in state.player_order:
        state.player_order.remove(player_id)

    if state.host_player_id == player_id:
        state.host_player_id = state.player_order[0] if state.player_order else None

    if leaving_player:
        state.status = f"{leaving_player.name} left the table."

    if not state.players:
        _room_blackjack_games.pop(room_id, None)
        return RoomBlackjackState(room_id=room_id)

    if state.turn_player_id == player_id:
        next_pid = _first_active_player(state)
        state.turn_player_id = next_pid

    if state.game_started and not state.game_over and not state.betting_open:
        if _all_players_finished(state):
            _finish_room_round(state)
        elif state.turn_player_id:
            current_player = state.players.get(state.turn_player_id)
            if current_player:
                state.status = f"{current_player.name}'s turn"

    if state.betting_open and _all_players_have_bets(state):
        _begin_play_after_bets(state)

    return state


def set_room_bet(room_id: str, player_id: str, amount: int) -> RoomBlackjackState:
    state = get_room_game(room_id)

    if player_id not in state.players:
        raise ValueError("Player not found.")

    if not state.game_started:
        raise ValueError("Round has not started.")

    if state.game_over:
        raise ValueError("Round already finished.")

    if not state.betting_open:
        raise ValueError("Betting is closed.")

    if amount <= 0:
        raise ValueError("Bet must be greater than 0.")

    if amount not in {10, 25, 50, 100}:
        raise ValueError("Invalid bet amount.")

    player = state.players[player_id]

    if player.joined_mid_round:
        raise ValueError("You joined during this round. Wait for the next round.")

    player.bet = amount
    state.status = f"{player.name} set a bet of {amount}."

    if _all_players_have_bets(state):
        _begin_play_after_bets(state)

    return state


def _all_players_have_bets(state: RoomBlackjackState) -> bool:
    active_ids = _active_player_ids(state)
    if len(active_ids) < 2:
        return False
    return all(state.players[pid].bet > 0 for pid in active_ids)


def _begin_play_after_bets(state: RoomBlackjackState) -> None:
    state.betting_open = False

    first_pid = _first_active_player(state)
    if first_pid is None:
        _finish_room_round(state)
        return

    state.turn_player_id = first_pid
    state.status = f"{state.players[first_pid].name}'s turn"


def start_room_game(room_id: str) -> RoomBlackjackState:
    state = get_room_game(room_id)

    active_ids = [pid for pid in state.player_order if pid in state.players]
    if len(active_ids) < 2:
        raise ValueError("At least 2 players are required to start.")

    state.deck = _new_deck()
    state.dealer = []
    state.game_started = True
    state.game_over = False
    state.dealer_revealed = False
    state.betting_open = True
    state.turn_player_id = None

    for pid in active_ids:
        _reset_player_for_round(state.players[pid])

    for pid in active_ids:
        _deal_card_from_deck(state.deck, state.players[pid].cards)

    _deal_card_from_deck(state.deck, state.dealer)

    for pid in active_ids:
        _deal_card_from_deck(state.deck, state.players[pid].cards)

    _deal_card_from_deck(state.deck, state.dealer)

    for pid in active_ids:
        player = state.players[pid]
        total = _hand_value(player.cards)
        if total == 21:
            player.blackjack = True
            player.finished = True

    state.status = "Cards dealt. Place your bets."

    if _all_players_have_bets(state):
        _begin_play_after_bets(state)

    return state


def room_hit(room_id: str, player_id: str) -> RoomBlackjackState:
    state = get_room_game(room_id)

    if not state.game_started:
        raise ValueError("Game has not started.")
    if state.game_over:
        raise ValueError("Round already finished.")
    if state.betting_open:
        raise ValueError("All players must bet before play can begin.")
    if state.turn_player_id != player_id:
        raise ValueError("It is not your turn.")
    if player_id not in state.players:
        raise ValueError("Player not found.")

    player = state.players[player_id]
    _deal_card_from_deck(state.deck, player.cards)

    total = _hand_value(player.cards)
    if total > 21:
        player.busted = True
        player.finished = True
        state.status = f"{player.name} busts."
    elif total == 21:
        player.finished = True
        state.status = f"{player.name} has 21."
    else:
        state.status = f"{player.name} hits."

    if player.finished:
        next_pid = _next_active_player_after(state, player_id)
        if next_pid is None:
            _finish_room_round(state)
        else:
            state.turn_player_id = next_pid
            state.status = f"{state.players[next_pid].name}'s turn"

    return state


def room_stand(room_id: str, player_id: str) -> RoomBlackjackState:
    state = get_room_game(room_id)

    if not state.game_started:
        raise ValueError("Game has not started.")
    if state.game_over:
        raise ValueError("Round already finished.")
    if state.betting_open:
        raise ValueError("All players must bet before play can begin.")
    if state.turn_player_id != player_id:
        raise ValueError("It is not your turn.")
    if player_id not in state.players:
        raise ValueError("Player not found.")

    player = state.players[player_id]
    player.stood = True
    player.finished = True
    state.status = f"{player.name} stands."

    next_pid = _next_active_player_after(state, player_id)
    if next_pid is None:
        _finish_room_round(state)
    else:
        state.turn_player_id = next_pid
        state.status = f"{state.players[next_pid].name}'s turn"

    return state


def _finish_room_round(state: RoomBlackjackState) -> None:
    state.turn_player_id = None
    state.dealer_revealed = True
    state.betting_open = False

    while _hand_value(state.dealer) < 16:
        _deal_card_from_deck(state.deck, state.dealer)

    dealer_total = _hand_value(state.dealer)

    for pid in state.player_order:
        player = state.players.get(pid)
        if not player or player.joined_mid_round:
            continue

        player_total = _hand_value(player.cards)
        player.result = _resolve_player_result(player_total, dealer_total)
        player.finished = True

    state.game_over = True
    state.status = "Round complete."


def _room_phase(state: RoomBlackjackState) -> str:
    if not state.game_started:
        return "waiting"
    if state.game_over:
        return "finished"
    if state.betting_open:
        return "betting"
    if state.turn_player_id is None:
        return "dealer"
    return "playing"


def room_state_to_payload(room_id: str, you_id: Optional[str] = None) -> dict:
    state = get_room_game(room_id)

    players_payload = []
    for pid in state.player_order:
        player = state.players.get(pid)
        if not player:
            continue

        players_payload.append({
            "id": player.id,
            "name": player.name,
            "cards": player.cards,
            "total": _hand_value(player.cards),
            "stood": player.stood,
            "busted": player.busted,
            "blackjack": player.blackjack,
            "finished": player.finished,
            "result": player.result,
            "bet": player.bet,
            "joined_mid_round": player.joined_mid_round,
        })

    you = None
    if you_id and you_id in state.players:
        p = state.players[you_id]
        you = {
            "id": p.id,
            "name": p.name,
        }

    return {
        "type": "table_state",
        "room_id": state.room_id,
        "you_id": you_id,
        "you": you,
        "status": state.status,
        "phase": _room_phase(state),
        "game_started": state.game_started,
        "game_over": state.game_over,
        "dealer_revealed": state.dealer_revealed,
        "betting_open": state.betting_open,
        "dealer_cards": state.dealer,
        "dealer_total": _hand_value(state.dealer) if state.dealer_revealed else None,
        "host_player_id": state.host_player_id,
        "turn_player_id": state.turn_player_id,
        "players": players_payload,
    }
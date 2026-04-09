from dataclasses import dataclass, field
from typing import Dict, List, Optional
import random

RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
SUITS = ["H", "D", "C", "S"]


def _new_deck() -> List[str]:
    deck = [f"{rank}{suit}" for suit in SUITS for rank in RANKS]
    random.shuffle(deck)
    return deck


@dataclass
class PokerPlayerState:
    id: str
    name: str
    cards: List[str] = field(default_factory=list)
    folded: bool = False


@dataclass
class RoomPokerState:
    room_id: str
    players: Dict[str, PokerPlayerState] = field(default_factory=dict)
    player_order: List[str] = field(default_factory=list)
    host_player_id: Optional[str] = None
    status: str = "Waiting for players"
    game_started: bool = False
    phase: str = "waiting"
    deck: List[str] = field(default_factory=list)


_room_poker_games: Dict[str, RoomPokerState] = {}


def get_room_poker_game(room_id: str) -> RoomPokerState:
    if room_id not in _room_poker_games:
        _room_poker_games[room_id] = RoomPokerState(room_id=room_id)
    return _room_poker_games[room_id]


def add_room_player(room_id: str, player_id: str, player_name: str) -> RoomPokerState:
    state = get_room_poker_game(room_id)

    if player_id in state.players:
        state.players[player_id].name = player_name or state.players[player_id].name
        return state

    player = PokerPlayerState(id=player_id, name=player_name)

    state.players[player_id] = player
    state.player_order.append(player_id)

    if not state.host_player_id:
        state.host_player_id = player_id

    state.status = f"{player_name} joined the table."

    return state


def remove_room_player(room_id: str, player_id: str) -> RoomPokerState:
    state = get_room_poker_game(room_id)

    leaving = state.players.pop(player_id, None)
    if player_id in state.player_order:
        state.player_order.remove(player_id)

    if state.host_player_id == player_id:
        state.host_player_id = state.player_order[0] if state.player_order else None

    if leaving:
        state.status = f"{leaving.name} left the table."

    if not state.players:
        _room_poker_games.pop(room_id, None)
        return RoomPokerState(room_id=room_id)

    if len(state.player_order) < 2:
        state.game_started = False
        state.phase = "waiting"
        state.deck = []
        for player in state.players.values():
            player.cards = []
            player.folded = False
        state.status = "Waiting for players"

    return state


def start_room_game(room_id: str) -> RoomPokerState:
    state = get_room_poker_game(room_id)

    if len(state.player_order) < 2:
        raise ValueError("At least 2 players are required to start.")

    state.deck = _new_deck()
    state.game_started = True
    state.phase = "preflop"
    state.status = "Round started. Hole cards dealt."

    for pid in state.player_order:
        player = state.players[pid]
        player.cards = []
        player.folded = False

    for _ in range(2):
        for pid in state.player_order:
            player = state.players.get(pid)
            if not player:
                continue
            if not state.deck:
                state.deck = _new_deck()
            player.cards.append(state.deck.pop())

    return state


def room_state_to_payload(room_id: str, you_id: str) -> dict:
    state = get_room_poker_game(room_id)

    return {
        "type": "table_state",
        "room_id": room_id,
        "players": [
            {
                "id": p.id,
                "name": p.name,
                "cards": p.cards if p.id == you_id else [],
                "card_count": len(p.cards),
                "folded": p.folded,
                "is_you": p.id == you_id,
            }
            for p in state.players.values()
        ],
        "host_player_id": state.host_player_id,
        "status": state.status,
        "game_started": state.game_started,
        "phase": state.phase,
    }
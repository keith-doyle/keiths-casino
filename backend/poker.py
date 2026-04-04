from dataclasses import dataclass, field
from typing import Dict, List, Optional


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


_room_poker_games: Dict[str, RoomPokerState] = {}


def get_room_poker_game(room_id: str) -> RoomPokerState:
    if room_id not in _room_poker_games:
        _room_poker_games[room_id] = RoomPokerState(room_id=room_id)
    return _room_poker_games[room_id]


def add_room_player(room_id: str, player_id: str, player_name: str) -> RoomPokerState:
    state = get_room_poker_game(room_id)

    if player_id in state.players:
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
                "card_count": len(p.cards),
                "folded": p.folded,
                "is_you": p.id == you_id,
            }
            for p in state.players.values()
        ],
        "host_player_id": state.host_player_id,
        "status": state.status,
    }
from dataclasses import dataclass, field
from typing import Dict, List, Optional
import random
from itertools import combinations

RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
SUITS = ["H", "D", "C", "S"]

RANK_ORDER = {
    "2": 2,
    "3": 3,
    "4": 4,
    "5": 5,
    "6": 6,
    "7": 7,
    "8": 8,
    "9": 9,
    "10": 10,
    "J": 11,
    "Q": 12,
    "K": 13,
    "A": 14,
}

HAND_RANK_NAMES = [
    "High Card",
    "Pair",
    "Two Pair",
    "Three of a Kind",
    "Straight",
    "Flush",
    "Full House",
    "Four of a Kind",
    "Straight Flush",
]


def _new_deck() -> List[str]:
    deck = [f"{rank}{suit}" for suit in SUITS for rank in RANKS]
    random.shuffle(deck)
    return deck


def _parse_card(card: str):
    rank = card[:-1]
    suit = card[-1]
    return RANK_ORDER[rank], suit


def _get_rank_counts(cards):
    counts = {}
    for rank, _ in cards:
        counts[rank] = counts.get(rank, 0) + 1
    return counts


def _is_flush(cards):
    suits = [suit for _, suit in cards]
    return len(set(suits)) == 1


def _is_straight(ranks):
    unique = sorted(set(ranks))
    if len(unique) != 5:
        return False, 0

    if unique == [2, 3, 4, 5, 14]:
        return True, 5

    if unique[-1] - unique[0] == 4:
        return True, unique[-1]

    return False, 0


def _evaluate_5(cards):
    ranks = sorted([rank for rank, _ in cards], reverse=True)
    counts = _get_rank_counts(cards)
    count_values = sorted(counts.values(), reverse=True)

    is_flush = _is_flush(cards)
    is_straight, high_straight = _is_straight(ranks)

    if is_straight and is_flush:
        return 8, [high_straight]

    if count_values == [4, 1]:
        four = max(rank for rank, count in counts.items() if count == 4)
        kicker = max(rank for rank, count in counts.items() if count == 1)
        return 7, [four, kicker]

    if count_values == [3, 2]:
        three = max(rank for rank, count in counts.items() if count == 3)
        pair = max(rank for rank, count in counts.items() if count == 2)
        return 6, [three, pair]

    if is_flush:
        return 5, ranks

    if is_straight:
        return 4, [high_straight]

    if count_values == [3, 1, 1]:
        three = max(rank for rank, count in counts.items() if count == 3)
        kickers = sorted(
            [rank for rank, count in counts.items() if count == 1],
            reverse=True,
        )
        return 3, [three] + kickers

    if count_values == [2, 2, 1]:
        pairs = sorted(
            [rank for rank, count in counts.items() if count == 2],
            reverse=True,
        )
        kicker = max(rank for rank, count in counts.items() if count == 1)
        return 2, pairs + [kicker]

    if count_values == [2, 1, 1, 1]:
        pair = max(rank for rank, count in counts.items() if count == 2)
        kickers = sorted(
            [rank for rank, count in counts.items() if count == 1],
            reverse=True,
        )
        return 1, [pair] + kickers

    return 0, ranks


def _best_hand(cards7):
    best = None
    for combo in combinations(cards7, 5):
        score = _evaluate_5(combo)
        if best is None or score > best:
            best = score
    return best


@dataclass
class PokerPlayerState:
    id: str
    name: str
    cards: List[str] = field(default_factory=list)
    folded: bool = False
    has_acted_this_round: bool = False
    chips: int = 1000
    current_bet: int = 0
    hand_name: Optional[str] = None


@dataclass
class RoomPokerState:
    room_id: str
    players: Dict[str, PokerPlayerState] = field(default_factory=dict)
    player_order: List[str] = field(default_factory=list)
    host_player_id: Optional[str] = None
    status: str = "Waiting for players"
    game_started: bool = False
    round_over: bool = False
    phase: str = "waiting"
    deck: List[str] = field(default_factory=list)
    community_cards: List[str] = field(default_factory=list)
    turn_index: int = 0
    current_turn_player_id: Optional[str] = None
    pot: int = 0
    current_bet: int = 0
    winner_player_id: Optional[str] = None
    winning_hand_name: Optional[str] = None


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
        _reset_round_state(state)
        state.status = "Waiting for players"
        return state

    active_ids = _active_player_ids(state)

    if state.game_started and len(active_ids) <= 1:
        _finish_round(state)
        return state

    if state.current_turn_player_id == player_id:
        _advance_turn(state)
        if state.current_turn_player_id:
            current = state.players.get(state.current_turn_player_id)
            if current:
                state.status = f"{current.name}'s turn"

    return state


def start_room_game(room_id: str) -> RoomPokerState:
    state = get_room_poker_game(room_id)

    if len(state.player_order) < 2:
        raise ValueError("At least 2 players are required to start.")

    state.deck = _new_deck()
    state.game_started = True
    state.round_over = False
    state.phase = "preflop"
    state.community_cards = []
    state.turn_index = 0
    state.current_turn_player_id = None
    state.pot = 0
    state.current_bet = 0
    state.winner_player_id = None
    state.winning_hand_name = None

    for pid in state.player_order:
        player = state.players[pid]
        player.cards = []
        player.folded = False
        player.has_acted_this_round = False
        player.current_bet = 0
        player.hand_name = None

    for _ in range(2):
        for pid in state.player_order:
            player = state.players.get(pid)
            if not player:
                continue
            if not state.deck:
                state.deck = _new_deck()
            player.cards.append(state.deck.pop())

    first_turn = _first_active_player_id(state)
    state.current_turn_player_id = first_turn
    state.turn_index = state.player_order.index(first_turn) if first_turn in state.player_order else 0

    if first_turn:
        current = state.players.get(first_turn)
        if current:
            state.status = f"{current.name}'s turn"

    return state


def _deal_community_cards(state: RoomPokerState, count: int) -> None:
    for _ in range(count):
        if not state.deck:
            state.deck = _new_deck()
        state.community_cards.append(state.deck.pop())


def _first_active_player_id(state: RoomPokerState) -> Optional[str]:
    for pid in state.player_order:
        player = state.players.get(pid)
        if player and not player.folded:
            return pid
    return None


def _active_player_ids(state: RoomPokerState) -> List[str]:
    ids: List[str] = []
    for pid in state.player_order:
        player = state.players.get(pid)
        if player and not player.folded:
            ids.append(pid)
    return ids


def _advance_turn(state: RoomPokerState) -> None:
    active_ids = _active_player_ids(state)
    if not active_ids:
        state.current_turn_player_id = None
        return

    if state.current_turn_player_id not in active_ids:
        state.current_turn_player_id = active_ids[0]
        state.turn_index = state.player_order.index(active_ids[0])
        return

    current_pos = active_ids.index(state.current_turn_player_id)
    next_pos = (current_pos + 1) % len(active_ids)
    next_pid = active_ids[next_pos]
    state.current_turn_player_id = next_pid
    state.turn_index = state.player_order.index(next_pid)


def _all_active_players_have_acted(state: RoomPokerState) -> bool:
    active_ids = _active_player_ids(state)
    if len(active_ids) < 2:
        return True

    for pid in active_ids:
        player = state.players.get(pid)
        if not player or not player.has_acted_this_round:
            return False
    return True


def _reset_action_flags(state: RoomPokerState) -> None:
    state.current_bet = 0
    for player in state.players.values():
        if not player.folded:
            player.has_acted_this_round = False
        player.current_bet = 0


def _move_to_next_phase(state: RoomPokerState) -> None:
    if state.phase == "preflop":
        _deal_community_cards(state, 3)
        state.phase = "flop"
        _reset_action_flags(state)
        state.current_turn_player_id = _first_active_player_id(state)
        state.status = "Flop dealt."
        return

    if state.phase == "flop":
        _deal_community_cards(state, 1)
        state.phase = "turn"
        _reset_action_flags(state)
        state.current_turn_player_id = _first_active_player_id(state)
        state.status = "Turn dealt."
        return

    if state.phase == "turn":
        _deal_community_cards(state, 1)
        state.phase = "river"
        _reset_action_flags(state)
        state.current_turn_player_id = _first_active_player_id(state)
        state.status = "River dealt."
        return

    if state.phase == "river":
        _finish_round(state)
        return


def _reset_round_state(state: RoomPokerState) -> None:
    state.game_started = False
    state.round_over = False
    state.phase = "waiting"
    state.deck = []
    state.community_cards = []
    state.turn_index = 0
    state.current_turn_player_id = None
    state.pot = 0
    state.current_bet = 0
    state.winner_player_id = None
    state.winning_hand_name = None

    for player in state.players.values():
        player.cards = []
        player.folded = False
        player.has_acted_this_round = False
        player.current_bet = 0
        player.hand_name = None


def _finish_round(state: RoomPokerState) -> None:
    active = _active_player_ids(state)
    final_status = "Round complete."

    state.game_started = False
    state.round_over = True
    state.phase = "showdown"
    state.current_turn_player_id = None
    state.current_bet = 0

    for player in state.players.values():
        player.has_acted_this_round = False
        player.current_bet = 0

    if active:
        results = []

        for pid in active:
            player = state.players[pid]
            parsed_cards = [_parse_card(card) for card in (player.cards + state.community_cards)]
            best_hand = _best_hand(parsed_cards)
            results.append((pid, best_hand))

        results.sort(key=lambda item: item[1], reverse=True)

        winner_id, best_hand = results[0]
        winner = state.players[winner_id]
        winnings = state.pot
        winner.chips += winnings

        state.winner_player_id = winner_id
        state.winning_hand_name = HAND_RANK_NAMES[best_hand[0]]

        for pid, hand in results:
            state.players[pid].hand_name = HAND_RANK_NAMES[hand[0]]

        final_status = f"{winner.name} wins {winnings} chips with {state.winning_hand_name}!"

    state.pot = 0
    state.status = final_status


def handle_player_action(room_id: str, player_id: str, action: str, amount: int = 0) -> RoomPokerState:
    state = get_room_poker_game(room_id)

    if not state.game_started:
        raise ValueError("Round has not started.")

    if state.round_over or state.phase == "waiting":
        raise ValueError("No player actions are allowed right now.")

    if player_id != state.current_turn_player_id:
        raise ValueError("It is not your turn.")

    player = state.players.get(player_id)
    if not player:
        raise ValueError("Player not found.")

    if player.folded:
        raise ValueError("Folded players cannot act.")

    if action == "fold":
        player.folded = True
        player.has_acted_this_round = True
        state.status = f"{player.name} folded"

    elif action == "check":
        if state.current_bet > player.current_bet:
            raise ValueError("Cannot check, must call or fold.")
        player.has_acted_this_round = True
        state.status = f"{player.name} checked"

    elif action == "call":
        diff = state.current_bet - player.current_bet
        if diff < 0:
            diff = 0
        if diff > player.chips:
            raise ValueError("Not enough chips to call.")

        player.chips -= diff
        player.current_bet += diff
        state.pot += diff
        player.has_acted_this_round = True
        state.status = f"{player.name} called"

    elif action == "raise":
        if amount <= state.current_bet:
            raise ValueError("Raise must be higher than the current bet.")

        diff = amount - player.current_bet
        if diff > player.chips:
            raise ValueError("Not enough chips to raise.")

        player.chips -= diff
        player.current_bet = amount
        state.current_bet = amount
        state.pot += diff

        for p in state.players.values():
            if not p.folded:
                p.has_acted_this_round = False

        player.has_acted_this_round = True
        state.status = f"{player.name} raised to {amount}"

    else:
        raise ValueError("Invalid action.")

    active_ids = _active_player_ids(state)

    if len(active_ids) <= 1:
        _finish_round(state)
        return state

    if _all_active_players_have_acted(state):
        _move_to_next_phase(state)
        if state.game_started and state.current_turn_player_id:
            current = state.players.get(state.current_turn_player_id)
            if current:
                state.status = f"{state.status} {current.name}'s turn"
        return state

    _advance_turn(state)

    if state.current_turn_player_id:
        current = state.players.get(state.current_turn_player_id)
        if current:
            state.status = f"{current.name}'s turn"

    return state


def room_state_to_payload(room_id: str, you_id: str) -> dict:
    state = get_room_poker_game(room_id)

    return {
        "type": "table_state",
        "room_id": state.room_id,
        "players": [
            {
                "id": p.id,
                "name": p.name,
                "cards": p.cards if (p.id == you_id or state.round_over) else [],
                "card_count": len(p.cards),
                "folded": p.folded,
                "has_acted_this_round": p.has_acted_this_round,
                "chips": p.chips,
                "current_bet": p.current_bet,
                "hand_name": p.hand_name if state.round_over else None,
                "is_you": p.id == you_id,
            }
            for p in state.players.values()
        ],
        "host_player_id": state.host_player_id,
        "turn_player_id": state.current_turn_player_id,
        "status": state.status,
        "game_started": state.game_started,
        "round_over": state.round_over,
        "phase": state.phase,
        "community_cards": state.community_cards,
        "pot": state.pot,
        "current_bet": state.current_bet,
        "winner_player_id": state.winner_player_id,
        "winning_hand_name": state.winning_hand_name,
    }
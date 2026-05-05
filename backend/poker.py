from dataclasses import dataclass, field
from typing import Dict, List, Optional
import random
from itertools import combinations
#Defines poker card ranking
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
#Blind constants 
SMALL_BLIND_AMOUNT = 10
BIG_BLIND_AMOUNT = 20

#Creates shuffled poker deck
def _new_deck() -> List[str]:
    deck = [f"{rank}{suit}" for suit in SUITS for rank in RANKS]
    random.shuffle(deck)
    return deck

#Turns card string into rank/suit value for scoring
def _parse_card(card: str):
    rank = card[:-1]
    suit = card[-1]
    return RANK_ORDER[rank], suit

#Counts rank duplicates in a hand
def _get_rank_counts(cards):
    counts = {}
    for rank, _ in cards:
        counts[rank] = counts.get(rank, 0) + 1
    return counts

#Returns true if all cards share same suit
def _is_flush(cards):
    suits = [suit for _, suit in cards]
    return len(set(suits)) == 1

#Detects straight returns its high card 
def _is_straight(ranks):
    unique = sorted(set(ranks))
    if len(unique) != 5:
        return False, 0

    if unique == [2, 3, 4, 5, 14]:
        return True, 5

    if unique[-1] - unique[0] == 4:
        return True, unique[-1]

    return False, 0

#Ranks one 5 card poker hand from high card to straight flush
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

#Finds best 5 card from 7 cards in play 
def _best_hand(cards7):
    best = None
    for combo in combinations(cards7, 5):
        score = _evaluate_5(combo)
        if best is None or score > best:
            best = score
    return best

#Player state, cards chips hand name bet
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

#Multiplayer room state, stores phase community cards pot current bet winner blinds
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
    last_pot: int = 0
    current_bet: int = 0
    winner_player_id: Optional[str] = None
    winning_hand_name: Optional[str] = None
    dealer_index: int = -1
    dealer_player_id: Optional[str] = None
    small_blind_player_id: Optional[str] = None
    big_blind_player_id: Optional[str] = None
    small_blind_amount: int = SMALL_BLIND_AMOUNT
    big_blind_amount: int = BIG_BLIND_AMOUNT

#Multiplayer game state storage
_room_poker_games: Dict[str, RoomPokerState] = {}

#Fetches or creates poker room state 
def get_room_poker_game(room_id: str) -> RoomPokerState:
    if room_id not in _room_poker_games:
        _room_poker_games[room_id] = RoomPokerState(room_id=room_id)
    return _room_poker_games[room_id]

#Keeps table host aligned with lobby host
def set_room_host_player_id(room_id: str, host_player_id: Optional[str]) -> RoomPokerState:
    state = get_room_poker_game(room_id)

    if host_player_id and host_player_id in state.players:
        state.host_player_id = host_player_id
    elif not state.host_player_id and state.player_order:
        state.host_player_id = state.player_order[0]
    elif state.host_player_id and state.host_player_id not in state.players:
        state.host_player_id = state.player_order[0] if state.player_order else None

    return state

#Seat order of players 
def _active_seated_ids(state: RoomPokerState) -> List[str]:
    return [pid for pid in state.player_order if pid in state.players]

#Finds next connceted seat
def _next_seated_player_id(state: RoomPokerState, start_index: int) -> Optional[str]:
    seated_ids = _active_seated_ids(state)
    if not seated_ids:
        return None

    n = len(state.player_order)
    for offset in range(1, n + 1):
        idx = (start_index + offset) % n
        pid = state.player_order[idx]
        if pid in state.players:
            return pid

    return None

#Logic for rotating blinds and dealer
def _rotate_dealer_and_blinds(state: RoomPokerState) -> None:
    seated_ids = _active_seated_ids(state)
    if len(seated_ids) < 2:
        state.dealer_player_id = None
        state.small_blind_player_id = None
        state.big_blind_player_id = None
        return

    if state.dealer_index < 0 or state.dealer_index >= len(state.player_order):
        first_pid = seated_ids[0]
        state.dealer_index = state.player_order.index(first_pid)
    else:
        next_dealer_pid = _next_seated_player_id(state, state.dealer_index)
        if next_dealer_pid is None:
            next_dealer_pid = seated_ids[0]
        state.dealer_index = state.player_order.index(next_dealer_pid)

    state.dealer_player_id = state.player_order[state.dealer_index]

    small_blind_pid = _next_seated_player_id(state, state.dealer_index)
    if small_blind_pid is None:
        small_blind_pid = state.dealer_player_id

    big_blind_pid = _next_seated_player_id(
        state,
        state.player_order.index(small_blind_pid),
    )
    if big_blind_pid is None:
        big_blind_pid = small_blind_pid

    state.small_blind_player_id = small_blind_pid
    state.big_blind_player_id = big_blind_pid

#Takes blind chips from a player 
def _post_blind(player: PokerPlayerState, amount: int) -> int:
    posted = min(player.chips, amount)
    player.chips -= posted
    player.current_bet += posted
    return posted

#Apply the blinds cost for players 
def _apply_blinds(state: RoomPokerState) -> None:
    state.pot = 0
    state.current_bet = 0

    if state.small_blind_player_id and state.small_blind_player_id in state.players:
        sb_player = state.players[state.small_blind_player_id]
        sb_posted = _post_blind(sb_player, state.small_blind_amount)
        state.pot += sb_posted

    if state.big_blind_player_id and state.big_blind_player_id in state.players:
        bb_player = state.players[state.big_blind_player_id]
        bb_posted = _post_blind(bb_player, state.big_blind_amount)
        state.pot += bb_posted
        state.current_bet = bb_posted

#Chooses first player to act preflop
def _set_first_turn_preflop(state: RoomPokerState) -> None:
    if not state.big_blind_player_id or state.big_blind_player_id not in state.player_order:
        state.current_turn_player_id = _first_active_player_id(state)
        if state.current_turn_player_id in state.player_order:
            state.turn_index = state.player_order.index(state.current_turn_player_id)
        return

    start_index = state.player_order.index(state.big_blind_player_id)
    next_pid = _next_active_player_after_index(state, start_index)
    state.current_turn_player_id = next_pid

    if next_pid and next_pid in state.player_order:
        state.turn_index = state.player_order.index(next_pid)

#Finds next non folded player 
def _next_active_player_after_index(state: RoomPokerState, start_index: int) -> Optional[str]:
    active_ids = _active_player_ids(state)
    if not active_ids:
        return None

    n = len(state.player_order)
    for offset in range(1, n + 1):
        idx = (start_index + offset) % n
        pid = state.player_order[idx]
        if pid in active_ids:
            return pid

    return None

#Chooses the first player to act preflop
def _first_active_after_dealer(state: RoomPokerState) -> Optional[str]:
    if state.dealer_player_id and state.dealer_player_id in state.player_order:
        dealer_index = state.player_order.index(state.dealer_player_id)
        return _next_active_player_after_index(state, dealer_index)

    return _first_active_player_id(state)

#Adds/ updates poker seat 
def add_room_player(
    room_id: str,
    player_id: str,
    player_name: str,
    chips: int = 1000,
) -> RoomPokerState:
    state = get_room_poker_game(room_id)

    if player_id in state.players:
        state.players[player_id].name = player_name or state.players[player_id].name

        if chips >= 0:
            state.players[player_id].chips = chips

        return state

    player = PokerPlayerState(
        id=player_id,
        name=player_name,
        chips=chips,
    )

    state.players[player_id] = player
    state.player_order.append(player_id)

    if not state.host_player_id:
        state.host_player_id = player_id

    state.status = f"{player_name} joined the table."
    return state

#Handles disconnect cleanup 
def remove_room_player(room_id: str, player_id: str) -> RoomPokerState:
    state = get_room_poker_game(room_id)

    leaving = state.players.pop(player_id, None)

    if player_id in state.player_order:
        state.player_order.remove(player_id)

    if state.host_player_id == player_id:
        state.host_player_id = state.player_order[0] if state.player_order else None

    if state.dealer_player_id == player_id:
        state.dealer_player_id = None
        state.dealer_index = -1

    if state.small_blind_player_id == player_id:
        state.small_blind_player_id = None

    if state.big_blind_player_id == player_id:
        state.big_blind_player_id = None

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

#Starts new multiplayer round
def start_room_game(room_id: str) -> RoomPokerState:
    state = get_room_poker_game(room_id)

    if len(state.player_order) < 2:
        raise ValueError("At least 2 players are required to start.")

    for pid in state.player_order:
        player = state.players[pid]
        if player.chips <= 0:
            raise ValueError(f"{player.name} has no chips and cannot start.")

    _rotate_dealer_and_blinds(state)

    state.deck = _new_deck()
    state.game_started = True
    state.round_over = False
    state.phase = "preflop"
    state.community_cards = []
    state.turn_index = 0
    state.current_turn_player_id = None
    state.pot = 0
    state.last_pot = 0
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

    _apply_blinds(state)

    for _ in range(2):
        for pid in state.player_order:
            player = state.players.get(pid)

            if not player:
                continue

            if not state.deck:
                state.deck = _new_deck()

            player.cards.append(state.deck.pop())

    _set_first_turn_preflop(state)

    if state.current_turn_player_id:
        current = state.players.get(state.current_turn_player_id)

        if current:
            state.status = (
                f"Dealer: {state.players[state.dealer_player_id].name}. "
                f"{state.players[state.small_blind_player_id].name} posted small blind "
                f"{state.small_blind_amount}. "
                f"{state.players[state.big_blind_player_id].name} posted big blind "
                f"{state.big_blind_amount}. "
                f"{current.name}'s turn"
            )

    return state

#Adds card to shared table
def _deal_community_cards(state: RoomPokerState, count: int) -> None:
    for _ in range(count):
        if not state.deck:
            state.deck = _new_deck()

        state.community_cards.append(state.deck.pop())

#Finds first active non folded player 
def _first_active_player_id(state: RoomPokerState) -> Optional[str]:
    for pid in state.player_order:
        player = state.players.get(pid)

        if player and not player.folded:
            return pid

    return None

#Returns players still live in the hand
def _active_player_ids(state: RoomPokerState) -> List[str]:
    ids: List[str] = []

    for pid in state.player_order:
        player = state.players.get(pid)

        if player and not player.folded:
            ids.append(pid)

    return ids

#Moves action to the next active poker player
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

#Detects when betting completes 
def _all_active_players_have_matched_bet(state: RoomPokerState) -> bool:
    active_ids = _active_player_ids(state)

    if len(active_ids) < 2:
        return True

    for pid in active_ids:
        player = state.players.get(pid)

        if not player:
            return False

        if not player.has_acted_this_round and player.chips > 0:
            return False

        if player.current_bet != state.current_bet and player.chips > 0:
            return False

    return True

#Resets current bet to 0 for new hand
def _reset_action_flags(state: RoomPokerState) -> None:
    state.current_bet = 0

    for player in state.players.values():
        if not player.folded:
            player.has_acted_this_round = False

        player.current_bet = 0

#Progresses games phases preflop flop turn river showdown
def _move_to_next_phase(state: RoomPokerState) -> None:
    if state.phase == "preflop":
        _deal_community_cards(state, 3)
        state.phase = "flop"
        _reset_action_flags(state)
        state.current_turn_player_id = _first_active_after_dealer(state)
        state.status = "Flop dealt."
        return

    if state.phase == "flop":
        _deal_community_cards(state, 1)
        state.phase = "turn"
        _reset_action_flags(state)
        state.current_turn_player_id = _first_active_after_dealer(state)
        state.status = "Turn dealt."
        return

    if state.phase == "turn":
        _deal_community_cards(state, 1)
        state.phase = "river"
        _reset_action_flags(state)
        state.current_turn_player_id = _first_active_after_dealer(state)
        state.status = "River dealt."
        return

    if state.phase == "river":
        _finish_round(state)
        return

#Resets poker room without deleting players 
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

#Finish round logic handling, handles folds wins best hand
def _finish_round(state: RoomPokerState) -> None:
    active = _active_player_ids(state)
    final_status = "Round complete."

    state.last_pot = state.pot
    state.game_started = False
    state.round_over = True
    state.current_turn_player_id = None
    state.current_bet = 0

    for player in state.players.values():
        player.has_acted_this_round = False
        player.current_bet = 0

    if len(active) == 1:
        winner_id = active[0]
        winner = state.players[winner_id]

        winner.chips += state.pot
        state.winner_player_id = winner_id
        state.winning_hand_name = "Fold Win"
        winner.hand_name = "Fold Win"

        state.phase = "showdown"
        final_status = f"{winner.name} wins {state.pot} chips because everyone else folded."
        state.pot = 0
        state.status = final_status
        return

    if active:
        results = []

        for pid in active:
            player = state.players[pid]
            combined_cards = player.cards + state.community_cards

            if len(combined_cards) < 5:
                continue

            parsed_cards = [_parse_card(card) for card in combined_cards]
            best_hand = _best_hand(parsed_cards)

            if best_hand is not None:
                results.append((pid, best_hand))

        if not results:
            state.status = "Round ended before showdown."
            state.pot = 0
            return

        results.sort(key=lambda item: item[1], reverse=True)

        best_score = results[0][1]
        winners = [pid for pid, score in results if score == best_score]
        split_amount = state.pot // len(winners)

        for pid in winners:
            state.players[pid].chips += split_amount

        remainder = state.pot % len(winners)

        if remainder > 0:
            state.players[winners[0]].chips += remainder

        state.winner_player_id = winners[0]
        state.winning_hand_name = HAND_RANK_NAMES[best_score[0]]

        for pid, hand in results:
            state.players[pid].hand_name = HAND_RANK_NAMES[hand[0]]

        if len(winners) == 1:
            winner = state.players[winners[0]]
            final_status = f"{winner.name} wins {state.pot} chips with {state.winning_hand_name}!"
        else:
            winner_names = ", ".join(state.players[pid].name for pid in winners)
            final_status = f"Tie between {winner_names}. Pot split ({split_amount} each) with {state.winning_hand_name}."

    state.phase = "showdown"
    state.pot = 0
    state.status = final_status

#Player action handling
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
        if state.current_bet != player.current_bet:
            raise ValueError("Cannot check, must call or fold.")

        player.has_acted_this_round = True
        state.status = f"{player.name} checked"

    elif action == "call":
        diff = state.current_bet - player.current_bet

        if diff <= 0:
            raise ValueError("Nothing to call.")

        if diff >= player.chips:
            diff = player.chips

        player.chips -= diff
        player.current_bet += diff
        state.pot += diff
        player.has_acted_this_round = True
        state.status = f"{player.name} called"

    elif action == "raise":
        if amount <= state.current_bet:
            raise ValueError("Raise must be higher than current bet.")

        diff = amount - player.current_bet

        if diff > player.chips:
            raise ValueError("Not enough chips to raise.")

        player.chips -= diff
        player.current_bet = amount
        state.current_bet = amount
        state.pot += diff

        for p in state.players.values():
            if not p.folded and p.id != player.id:
                p.has_acted_this_round = False

        player.has_acted_this_round = True
        state.status = f"{player.name} raised to {amount}"

    else:
        raise ValueError("Invalid action.")

    active_ids = _active_player_ids(state)

    if len(active_ids) <= 1:
        _finish_round(state)
        return state

    if _all_active_players_have_matched_bet(state):
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

#Builds table_state json received by flutter ui for one player
def room_state_to_payload(room_id: str, you_id: str) -> dict:
    state = get_room_poker_game(room_id)
    display_pot = state.last_pot if state.round_over else state.pot

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
        "pot": display_pot,
        "current_bet": state.current_bet,
        "winner_player_id": state.winner_player_id,
        "winning_hand_name": state.winning_hand_name,
        "dealer_player_id": state.dealer_player_id,
        "small_blind_player_id": state.small_blind_player_id,
        "big_blind_player_id": state.big_blind_player_id,
        "small_blind_amount": state.small_blind_amount,
        "big_blind_amount": state.big_blind_amount,
    }
import json
import uuid
from typing import Dict

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

import blackjack

router = APIRouter()

_table_room_sockets: Dict[str, Dict[WebSocket, str]] = {}


def _get_table_room(room_id: str) -> Dict[WebSocket, str]:
    if room_id not in _table_room_sockets:
        _table_room_sockets[room_id] = {}
    return _table_room_sockets[room_id]


async def _send_error(ws: WebSocket, status: str, extra: dict | None = None):
    payload = {"type": "error", "status": status}
    if extra:
        payload.update(extra)
    await ws.send_text(json.dumps(payload))


async def _broadcast_table_state(room_id: str):
    room = _get_table_room(room_id)

    for ws, pid in list(room.items()):
        try:
            payload = blackjack.room_state_to_payload(room_id, you_id=pid)
            await ws.send_text(json.dumps(payload))
        except Exception:
            room.pop(ws, None)

    if not room:
        _table_room_sockets.pop(room_id, None)

@router.websocket("/ws/blackjack/{room_id}")
async def blackjack_ws(websocket: WebSocket, room_id: str):
    print("WS endpoint hit for room:", room_id)
    await websocket.accept()
    print("Client accepted in room", room_id)

    session_game_id = uuid.uuid4().hex

    await websocket.send_text(
        json.dumps({"type": "system", "status": f"Connected to room {room_id}"})
    )

    try:
        while True:
            raw = await websocket.receive_text()
            print(f"Received from {room_id}: {raw}")

            try:
                msg = json.loads(raw)
                if not isinstance(msg, dict):
                    await _send_error(websocket, "Invalid JSON payload (expected object).")
                    continue
            except Exception:
                await _send_error(websocket, "Invalid JSON.", {"raw": raw})
                continue

            if msg.get("type") != "action":
                await _send_error(websocket, "Unknown message type.", {"received": msg})
                continue

            action = msg.get("action")

            if action not in {"deal", "hit", "stand"}:
                await _send_error(websocket, "Unknown action.", {"action": action})
                continue

            try:
                if action == "deal":
                    payload = blackjack.deal()
                elif action == "hit":
                    payload = blackjack.hit(session_game_id)
                else:
                    payload = blackjack.stand(session_game_id)

                payload["type"] = "state"
                payload["game_id"] = session_game_id

                await websocket.send_text(json.dumps(payload))

            except Exception as e:
                await _send_error(websocket, "Server error.", {"detail": str(e)})

    except WebSocketDisconnect:
        print(f"Client disconnected from room {room_id}")


@router.websocket("/ws/blackjack_table/{room_id}")
async def blackjack_table_ws(websocket: WebSocket, room_id: str):
    await websocket.accept()

    room = _get_table_room(room_id)
    room[websocket] = ""

    await websocket.send_text(
        json.dumps({
            "type": "system",
            "status": f"Connected to blackjack table {room_id}. Send join."
        })
    )

    try:
        while True:
            raw = await websocket.receive_text()

            try:
                msg = json.loads(raw)
                if not isinstance(msg, dict):
                    await _send_error(websocket, "Invalid JSON payload (expected object).")
                    continue
            except Exception:
                await _send_error(websocket, "Invalid JSON.", {"raw": raw})
                continue

            mtype = msg.get("type")

            if mtype == "join":
                player_id = (msg.get("player_id") or "").strip()
                player_name = (msg.get("player_name") or "").strip()

                if not player_id:
                    await _send_error(websocket, "Missing player_id.")
                    continue

                if not player_name:
                    player_name = player_id[:6]

                blackjack.add_room_player(room_id, player_id, player_name)
                room[websocket] = player_id

                await _broadcast_table_state(room_id)
                continue

            player_id = room.get(websocket, "")
            if not player_id:
                await _send_error(websocket, "Expected join message first.", {"received": msg})
                continue

            if mtype == "start":
                try:
                    state = blackjack.get_room_game(room_id)
                    if state.host_player_id != player_id:
                        await _send_error(websocket, "Only the host can start the game.")
                        continue

                    blackjack.start_room_game(room_id)
                    await _broadcast_table_state(room_id)
                except Exception as e:
                    await _send_error(websocket, str(e))
                continue

            if mtype == "action":
                action = msg.get("action")

                try:
                    if action == "hit":
                        blackjack.room_hit(room_id, player_id)
                    elif action == "stand":
                        blackjack.room_stand(room_id, player_id)
                    else:
                        await _send_error(websocket, "Unknown action.", {"action": action})
                        continue

                    await _broadcast_table_state(room_id)
                except Exception as e:
                    await _send_error(websocket, str(e))
                continue

            await _send_error(websocket, "Unknown message type.", {"received": msg})

    except WebSocketDisconnect:
        player_id = room.pop(websocket, "")

        if player_id:
            blackjack.remove_room_player(room_id, player_id)

        await _broadcast_table_state(room_id)

        if not room:
            _table_room_sockets.pop(room_id, None)
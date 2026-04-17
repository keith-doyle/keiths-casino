import json
from typing import Dict

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

import poker

router = APIRouter()

_table_room_sockets: Dict[str, Dict[WebSocket, str]] = {}


def _get_room(room_id: str) -> Dict[WebSocket, str]:
    if room_id not in _table_room_sockets:
        _table_room_sockets[room_id] = {}
    return _table_room_sockets[room_id]


async def _send_error(ws: WebSocket, status: str, extra: dict | None = None):
    payload = {"type": "error", "status": status}
    if extra:
        payload.update(extra)
    await ws.send_text(json.dumps(payload))


async def _broadcast(room_id: str):
    room = _get_room(room_id)

    for ws, pid in list(room.items()):
        try:
            payload = poker.room_state_to_payload(room_id, pid)
            await ws.send_text(json.dumps(payload))
        except Exception:
            room.pop(ws, None)

    if not room:
        _table_room_sockets.pop(room_id, None)


@router.websocket("/ws/poker_table/{room_id}")
async def poker_table_ws(websocket: WebSocket, room_id: str):
    await websocket.accept()

    room = _get_room(room_id)
    room[websocket] = ""

    await websocket.send_text(
        json.dumps({
            "type": "system",
            "status": f"Connected to poker table {room_id}. Send join."
        })
    )

    try:
        while True:
            raw = await websocket.receive_text()

            try:
                msg = json.loads(raw)
                if not isinstance(msg, dict):
                    await _send_error(websocket, "Invalid JSON payload.")
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

                try:
                    coins = int(msg.get("coins", 1000) or 1000)
                except Exception:
                    coins = 1000

                poker.add_room_player(
                    room_id=room_id,
                    player_id=player_id,
                    player_name=player_name,
                    chips=coins,
                )
                room[websocket] = player_id

                await _broadcast(room_id)
                continue

            player_id = room.get(websocket, "")
            if not player_id:
                await _send_error(websocket, "Expected join message first.", {"received": msg})
                continue

            if mtype == "start":
                try:
                    state = poker.get_room_poker_game(room_id)
                    if state.host_player_id != player_id:
                        await _send_error(websocket, "Only the host can start the game.")
                        continue

                    poker.start_room_game(room_id)
                    await _broadcast(room_id)
                except Exception as e:
                    await _send_error(websocket, str(e))
                continue

            if mtype == "action":
                action = (msg.get("action") or "").strip()
                amount = int(msg.get("amount", 0) or 0)

                try:
                    poker.handle_player_action(room_id, player_id, action, amount)
                    await _broadcast(room_id)
                except Exception as e:
                    await _send_error(websocket, str(e))
                continue

            await _send_error(websocket, "Unknown message type.", {"received": msg})

    except WebSocketDisconnect:
        player_id = room.pop(websocket, "")

        if player_id:
            poker.remove_room_player(room_id, player_id)

        await _broadcast(room_id)

        if not room:
            _table_room_sockets.pop(room_id, None)
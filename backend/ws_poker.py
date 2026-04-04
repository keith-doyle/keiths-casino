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
            except Exception:
                continue

            mtype = msg.get("type")

            if mtype == "join":
                player_id = msg.get("player_id")
                player_name = msg.get("player_name") or player_id

                poker.add_room_player(room_id, player_id, player_name)
                room[websocket] = player_id

                await _broadcast(room_id)
                continue

    except WebSocketDisconnect:
        player_id = room.pop(websocket, "")

        if player_id:
            poker.remove_room_player(room_id, player_id)

        await _broadcast(room_id)

        if not room:
            _table_room_sockets.pop(room_id, None)
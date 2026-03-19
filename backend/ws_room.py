# ws_room.py
import json
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, HTTPException
from pydantic import BaseModel

router = APIRouter()


@dataclass
class Player:
    id: str
    name: str


@dataclass
class Room:
    id: str
    sockets: Dict[WebSocket, str] = field(default_factory=dict)
    players: Dict[str, Player] = field(default_factory=dict)


_rooms: Dict[str, Room] = {}

def room_exists(room_id: str) -> bool:
    return room_id in _rooms

def _room(room_id: str) -> Optional[Room]:
    return _rooms.get(room_id)

def create_room(room_id: str) -> Room:
    room_id = room_id.strip().upper()

    if not room_id:
        raise ValueError("Room id is required.")

    if room_id in _rooms:
        raise ValueError("Room already exists.")

    room = Room(id=room_id)
    _rooms[room_id] = room
    return room

class CreateRoomRequest(BaseModel):
    room_id: str

@router.post("/rooms/create")
def create_room_http(body: CreateRoomRequest):
    room_id = body.room_id.strip().upper()

    if not room_id:
        raise HTTPException(status_code=400, detail="Room id is required.")

    if room_id in _rooms:
        raise HTTPException(status_code=409, detail="Room already exists.")

    create_room(room_id)

    return {"ok": True, "room_id": room_id}

@router.get("/rooms/{room_id}/exists")
def room_exists_http(room_id: str):
    room_id = room_id.strip().upper()
    return {
        "room_id": room_id,
        "exists": room_exists(room_id),
    }


def _payload_table_state(room: Room, you_id: Optional[str]) -> dict:
    you = None
    if you_id and you_id in room.players:
        p = room.players[you_id]
        you = {"id": p.id, "name": p.name}

    players_list = [{"id": p.id, "name": p.name} for p in room.players.values()]

    return {
        "type": "table_state",
        "room_id": room.id,
        "you": you,
        "players": players_list,
    }


async def _broadcast(room: Room):
    for ws, pid in list(room.sockets.items()):
        try:
            await ws.send_text(json.dumps(_payload_table_state(room, pid)))
        except Exception:
            room.sockets.pop(ws, None)


async def _send_error(ws: WebSocket, status: str, extra: dict | None = None):
    payload = {"type": "error", "status": status}
    if extra:
        payload.update(extra)
    await ws.send_text(json.dumps(payload))


@router.websocket("/ws/room/{room_id}")
async def room_ws(ws: WebSocket, room_id: str):
    room_id = room_id.strip().upper()
    await ws.accept()
    room = _room(room_id)
    if room is None:
        await _send_error(ws, "Room does not exist.")
        await ws.close()
        return

    room.sockets[ws] = ""

    await ws.send_text(json.dumps({
        "type": "system",
        "status": f"Connected to room {room_id}. Send join."
    }))

    try:
        while True:
            raw = await ws.receive_text()

            try:
                msg = json.loads(raw)
                if not isinstance(msg, dict):
                    await _send_error(ws, "Invalid JSON payload (expected object).")
                    continue
            except Exception:
                await _send_error(ws, "Invalid JSON.", {"raw": raw})
                continue

            mtype = msg.get("type")

            if mtype != "join":
                await _send_error(ws, "Expected join message first.", {"received": msg})
                continue

            player_id = (msg.get("player_id") or "").strip()
            player_name = (msg.get("player_name") or "").strip()

            if not player_id:
                await _send_error(ws, "Missing player_id.")
                continue

            if not player_name:
                player_name = player_id[:6]

            room.players[player_id] = Player(id=player_id, name=player_name)
            room.sockets[ws] = player_id

            await _broadcast(room)

    except WebSocketDisconnect:
        pid = room.sockets.pop(ws, "")
        if pid and pid in room.players:
            room.players.pop(pid, None)

        await _broadcast(room)

        if not room.sockets:
            _rooms.pop(room_id, None)
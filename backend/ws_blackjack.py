import json
import uuid
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

import blackjack

router = APIRouter()

async def _send_error(ws: WebSocket, status: str, extra: dict | None = None):
    payload = {"type": "error", "status": status}
    if extra:
        payload.update(extra)
    await ws.send_text(json.dumps(payload))

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

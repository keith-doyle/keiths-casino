from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from ws_room import router as ws_room_router
from blackjack import router as blackjack_router
from ws_blackjack import router as ws_blackjack_router
from ws_poker import router as ws_poker_router

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


app.include_router(ws_room_router)


app.include_router(blackjack_router)
app.include_router(ws_blackjack_router)
app.include_router(ws_poker_router)
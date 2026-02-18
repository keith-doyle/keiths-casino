from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from blackjack import router as blackjack_router
from ws_blackjack import router as ws_router

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,   
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(blackjack_router)
app.include_router(ws_router)

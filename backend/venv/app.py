from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from blackjack import router as blackjack_router

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(blackjack_router)

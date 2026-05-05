import os
from dotenv import load_dotenv
import firebase_admin
from firebase_admin import credentials, firestore

load_dotenv()

firebase_app = None
db = None

#Loads Firebase service account path from .env, initializes Firebase Admin, and creates Firestore db client.
def init_firebase():
    global firebase_app, db

    if firebase_app:
        return db

    cred_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")

    if not cred_path:
        raise ValueError("FIREBASE_SERVICE_ACCOUNT_PATH is missing")

    if not os.path.exists(cred_path):
        raise ValueError(f"Firebase service account file not found: {cred_path}")

    cred = credentials.Certificate(cred_path)
    firebase_app = firebase_admin.initialize_app(cred)
    db = firestore.client()

    return db

#Other backend services call get_db instead of re-initializing Firebase.
def get_db():
    global db

    if db is None:
        return init_firebase()

    return db
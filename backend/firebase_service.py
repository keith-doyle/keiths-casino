import firebase_admin
from firebase_admin import credentials, firestore
import os

firebase_app = None
db = None


def init_firebase():
    global firebase_app, db

    if firebase_app:
        return db

    cred_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")

    cred = credentials.Certificate(cred_path)
    firebase_app = firebase_admin.initialize_app(cred)
    db = firestore.client()

    return db


def get_db():
    if not db:
        return init_firebase()
    return db
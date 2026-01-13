"""
Kiosk Routes Blueprint - Status, Scan, Queue Management
PLACEHOLDER - To be implemented in future session
"""
from flask import Blueprint

kiosk_bp = Blueprint('kiosk', __name__)

# Routes to migrate from app.py:
# - /api/kiosk/<token>/status (GET) - main status endpoint  
# - /api/kiosk/<token>/scan (POST) - scan student ID
# - /api/queue/join (POST) - join queue
# - /api/queue/leave (POST) - leave queue
# - /api/queue/delete (POST) - remove from queue
# - /api/queue/reorder (POST) - reorder queue
# - Plus static routes: /, /kiosk, /k/<token>, /display, /d/<token>

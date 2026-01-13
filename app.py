import csv
import io
import sys
import os
import json
import time
import hashlib
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo
from typing import Dict, Optional, List, Any
from functools import wraps

from flask import Flask, jsonify, render_template, request, redirect, url_for, send_file, Response, stream_with_context, session, send_from_directory
from werkzeug.middleware.proxy_fix import ProxyFix
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import text

import config
import threading
import requests
from urllib.parse import urljoin
from cryptography.fernet import Fernet
import base64

# Import services
from services.roster import RosterService
from services.ban import BanService
from services.session import SessionService

# Import models
from models.user import create_user_model

app = Flask(__name__)
# Enable CORS for all domains for now (development mode)
from flask_cors import CORS
CORS(app)

# Fix for Render/Heroku: Trust X-Forwarded-Proto header for HTTPS
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_prefix=1)

# Prefer DATABASE_URL from env (Render), else config.py
app.config["SQLALCHEMY_DATABASE_URI"] = os.getenv("DATABASE_URL", config.DATABASE_URL)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
app.config["SECRET_KEY"] = config.SECRET_KEY
app.config["PERMANENT_SESSION_LIFETIME"] = timedelta(hours=8)  # Admin sessions last 8 hours

# Google OAuth config (2.0 multi-user support)
app.config["GOOGLE_CLIENT_ID"] = getattr(config, 'GOOGLE_CLIENT_ID', '')
app.config["GOOGLE_CLIENT_SECRET"] = getattr(config, 'GOOGLE_CLIENT_SECRET', '')

db = SQLAlchemy(app)
TZ = ZoneInfo(config.TIMEZONE)

# Encryption Key Setup
# We derive a Fernet key from the SECRET_KEY to ensure it's deterministic but secure
# If SECRET_KEY is changed, the database will need to be cleared/re-uploaded
def _get_encryption_key():
    # Pad or truncate SECRET_KEY to 32 bytes for base64 encoding
    key_material = app.config["SECRET_KEY"].encode()
    # Use SHA256 to get 32 bytes
    key_32 = hashlib.sha256(key_material).digest()
    return base64.urlsafe_b64encode(key_32)

cipher_suite = Fernet(_get_encryption_key())


# ---------- Models ----------

# Create User model for multi-tenancy (2.0)
User = create_user_model(db)

class Student(db.Model):
    id = db.Column(db.String, primary_key=True)          # barcode value or student id
    name = db.Column(db.String, nullable=False)
    # 2.0: Add user_id FK (nullable for migration compatibility)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=True, index=True)

class Session(db.Model):
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    student_id = db.Column(db.String, db.ForeignKey("student.id"), nullable=False, index=True)
    start_ts = db.Column(db.DateTime(timezone=True), nullable=False, index=True)
    end_ts = db.Column(db.DateTime(timezone=True), nullable=True, index=True)
    ended_by = db.Column(db.String, nullable=True)       # "kiosk_scan", "override", "auto"
    room = db.Column(db.String, nullable=True)
    # 2.0: Add user_id FK (nullable for migration compatibility)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=True, index=True)

    student = db.relationship("Student")
    user = db.relationship('User', backref='sessions')

    @property
    def duration_seconds(self):
        end = self.end_ts or datetime.now(timezone.utc)
        return int((end - self.start_ts).total_seconds())


class Queue(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    student_id = db.Column(db.String(50), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    joined_ts = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))


class Settings(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    room_name = db.Column(db.String, nullable=False, default=config.ROOM_NAME)
    capacity = db.Column(db.Integer, nullable=False, default=config.CAPACITY)
    overdue_minutes = db.Column(db.Integer, nullable=False, default=10)
    kiosk_suspended = db.Column(db.Boolean, nullable=False, default=False)

    auto_ban_overdue = db.Column(db.Boolean, nullable=False, default=False)
    auto_promote_queue = db.Column(db.Boolean, nullable=False, default=False)
    enable_queue = db.Column(db.Boolean, nullable=False, default=False)
    # 2.0: Add user_id FK (nullable for migration compatibility, ID=1 is legacy global)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=True, index=True)
    
    user = db.relationship('User', backref='settings')

class StudentName(db.Model):
    """FERPA-compliant storage of student names only (no ID association)"""
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name_hash = db.Column(db.String, nullable=False)  # Hash of student_id for lookup (removed unique, see constraint below)
    encrypted_id = db.Column(db.String, nullable=True)   # Encrypted ID for admin retrieval
    display_name = db.Column(db.String, nullable=False)  # Actual name to display
    created_at = db.Column(db.DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
    banned = db.Column(db.Boolean, nullable=False, default=False)  # Restroom ban flag
    # 2.0: Add user_id FK (nullable for migration compatibility)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=True, index=True)
    
    user = db.relationship('User', backref='student_names')
    
    # 2.0: Composite unique constraint - same student can exist for different users
    __table_args__ = (
        db.UniqueConstraint('user_id', 'name_hash', name='uq_user_name_hash'),
    )

# ---------- Service Initialization ----------
# Initialize services after models are defined
roster_service: Optional[RosterService] = None
ban_service: Optional[BanService] = None
session_service: Optional[SessionService] = None

def initialize_services():
    """Initialize service layer after app context is available"""
    global roster_service, ban_service, session_service
    roster_service = RosterService(db, cipher_suite, StudentName)
    ban_service = BanService(db, StudentName, roster_service)
    session_service = SessionService(db, Session)
    print("Services initialized successfully")

# Create tables after models are defined (works under Gunicorn too)
STATIC_VERSION = os.getenv("STATIC_VERSION", str(int(time.time())))

# Automatic database initialization - detects empty/new databases
def initialize_database_if_needed():
    """Initialize database tables and settings if they don't exist."""
    print("Starting database initialization check...")
    try:
        with app.app_context():
            print(f"Using database URL: {app.config['SQLALCHEMY_DATABASE_URI'][:50]}...")
            
            # First, try to create all tables (safe if they already exist)
            print("Creating database tables...")
            db.create_all()
            print("Tables created successfully")
            
            # IMPORTANT: Run migrations FIRST to add new columns before querying with them
            print("Running database migrations (adding new columns)...")
            try:
                msgs = run_migrations()
                for msg in msgs:
                    print(f"Migration: {msg}")
            except Exception as e:
                print(f"Migration warning (non-fatal): {e}")
                try:
                    db.session.rollback()
                except Exception:
                    pass
            
            # Initialize services
            initialize_services()
            
            # Check if Settings table exists and has data
            # Use raw SQL to avoid ORM column mapping issues
            settings_exists = False
            try:
                # Use raw SQL to check if settings record exists (avoids user_id column issue)
                result = db.session.execute(text("SELECT id FROM settings WHERE id = 1")).scalar()
                if result:
                    settings_exists = True
                    print("Database appears to be initialized (Settings found)")
                else:
                    print("Settings table exists but is empty - initializing...")
                    settings_exists = False
            except Exception as e:
                # Table doesn't exist or query failed
                print(f"Settings table query failed: {e} - will initialize...")
                try:
                    db.session.rollback()  # Clear failed transaction state
                except Exception:
                    pass
                settings_exists = False
            
            # Initialize settings if needed
            if not settings_exists:
                try:
                    db.session.rollback()  # Ensure clean transaction state
                    print("Creating default settings record...")
                    s = Settings(id=1, room_name=config.ROOM_NAME, capacity=config.CAPACITY,
                               overdue_minutes=getattr(config, "MAX_MINUTES", 10), kiosk_suspended=False, auto_ban_overdue=False)
                    db.session.add(s)
                    db.session.commit()
                    print("Database initialized successfully with default settings")
                except Exception as e:
                    print(f"ERROR: Could not initialize settings: {e}")
                    try:
                        db.session.rollback()
                    except Exception:
                        pass
                    raise  # Re-raise to see the full error
            
            # Test that we can actually query the database
            try:
                test_count = Session.query.count()
                print(f"Database test successful - found {test_count} sessions")
            except Exception as e:
                print(f"ERROR: Database test failed: {e}")
                raise

            
    except Exception as e:
        print(f"CRITICAL: Database initialization failed: {e}")
        import traceback
        print(f"Full traceback: {traceback.format_exc()}")
        # Don't re-raise - let the app try to start anyway



# ---------- Error Handling Utilities ----------

def handle_db_errors(f):
    """Decorator to handle database errors consistently."""
    @wraps(f)
    def wrapper(*args, **kwargs):
        try:
            return f(*args, **kwargs)
        except Exception as e:
            try:
                db.session.rollback()
            except Exception:
                pass
            return jsonify(ok=False, message=str(e)), 500
    return wrapper

# ---------- Utility (Context Resolver) ----------

def get_current_user_id(token: Optional[str] = None) -> Optional[int]:
    """
    Get the effective user_id context.
    1. If token provided (Kiosk/Display), resolve user from token.
    2. If logged in via session['user_id'], return that.
    3. If legacy admin_authenticated (no user_id), return None (global).
    """
    if token:
        user = User.query.filter((User.kiosk_token == token) | (User.kiosk_slug == token)).first()
        if user:
            return user.id
            
    if 'user_id' in session:
        return session['user_id']
        
    # Legacy: admin_authenticated but no user_id implies legacy global mode
    return None


# ---------- Status Payload Utilities ----------

def _build_status_payload(user_id: Optional[int]) -> Dict[str, Any]:
    """
    Single source of truth for Kiosk/Display status payload.
    Keep this aligned with the Flutter `KioskStatus` model.
    """
    settings = get_settings(user_id)

    overdue_minutes = settings["overdue_minutes"]
    kiosk_suspended = settings["kiosk_suspended"]
    auto_ban_overdue = settings.get("auto_ban_overdue", False)
    auto_promote_queue = settings.get("auto_promote_queue", False)

    # Server time in milliseconds for client sync (NTP-lite)
    server_now = datetime.now(timezone.utc)
    server_time_ms = int(server_now.timestamp() * 1000)

    # Current holder (legacy single-pass fields) + multi-pass
    s = get_current_holder(user_id)
    active_sessions = [{
        "id": sess.id,
        "name": get_student_name(sess.student_id, "Student", user_id=user_id),
        "elapsed": sess.duration_seconds,
        "overdue": sess.duration_seconds > overdue_minutes * 60,
        "start": to_local(sess.start_ts).isoformat(),
        # Unix timestamp in ms for precise client-side calculation
        "start_ms": int(sess.start_ts.timestamp() * 1000)
    } for sess in get_open_sessions(user_id)]

    # Queue (names for display + ids for admin actions)
    queue_rows = Queue.query.filter_by(user_id=user_id).order_by(Queue.joined_ts.asc()).all()
    queue_names = [get_student_name(q.student_id, "Unknown", user_id=user_id) for q in queue_rows]
    queue_list = [{
        "name": get_student_name(q.student_id, "Unknown", user_id=user_id),
        "student_id": q.student_id,
    } for q in queue_rows]

    payload: Dict[str, Any] = {
        "server_time_ms": server_time_ms,  # For client clock sync
        "overdue_minutes": overdue_minutes,
        "kiosk_suspended": kiosk_suspended,
        "auto_ban_overdue": auto_ban_overdue,
        "auto_promote_queue": auto_promote_queue,
        "capacity": settings["capacity"],
        "active_sessions": active_sessions,
        "queue": queue_names,
        "queue_list": queue_list,
    }

    if s:
        payload.update({
            "in_use": True,
            "name": get_student_name(s.student_id, "Student", user_id=user_id),
            "start": to_local(s.start_ts).isoformat(),
            "start_ms": int(s.start_ts.timestamp() * 1000),
            "elapsed": s.duration_seconds,
            "overdue": s.duration_seconds > overdue_minutes * 60,
        })
    else:
        payload.update({
            "in_use": False,
            "name": "",
            "elapsed": 0,
            "overdue": False,
        })

    return payload



def _build_status_signature(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    A reduced, stable signature for SSE change detection.
    Excludes fields that change every second (like `elapsed`).
    """
    sig_sessions = [{
        "id": s.get("id"),
        "start": s.get("start"),
        "name": s.get("name"),
        "overdue": s.get("overdue"),
    } for s in (payload.get("active_sessions") or [])]

    return {
        "in_use": payload.get("in_use"),
        "name": payload.get("name"),
        "start": payload.get("start"),
        "overdue": payload.get("overdue"),
        "overdue_minutes": payload.get("overdue_minutes"),
        "kiosk_suspended": payload.get("kiosk_suspended"),
        "auto_ban_overdue": payload.get("auto_ban_overdue"),
        "auto_promote_queue": payload.get("auto_promote_queue"),
        "capacity": payload.get("capacity"),
        "active_sessions": sig_sessions,
        "queue": payload.get("queue") or [],
        # queue_list only needed if UI consumes ids; include it for completeness
        "queue_list": payload.get("queue_list") or [],
    }

# ---------- FERPA-Compliant Roster Utilities ----------

def get_memory_roster(user_id: Optional[int] = None) -> Dict[str, str]:
    """Get student roster from memory cache (scoped to user)."""
    return roster_service.get_memory_roster(user_id) if roster_service else {}

def set_memory_roster(roster_dict: Dict[str, str], user_id: Optional[int] = None) -> None:
    """Set student roster in memory cache (scoped to user)."""
    if roster_service:
        roster_service.set_memory_roster(user_id, roster_dict)

def clear_memory_roster(user_id: Optional[int] = None) -> None:
    """Clear student roster from memory cache (scoped to user)."""
    if roster_service:
        roster_service.clear_memory_roster(user_id)

def refresh_roster_cache(user_id: Optional[int] = None) -> None:
    """Refresh the memory cache from the database (scoped to user)."""
    if not roster_service:
        return
        
    # Get all students for this user with non-encrypted names (or handle decryption)
    # Simple case: Just load display_name mapped to name_hash or ID
    # Actually memory cache maps: { id -> Name }
    # So we need to reconstruct that.
    
    # 1. Clear current cache
    clear_memory_roster(user_id)
    
    # 2. Query DB
    students = StudentName.query.filter_by(user_id=user_id).all()
    
    # 3. Build dict
    new_cache = {}
    for s in students:
        # Use encrypted_id if available (decrypted), else fallback to hash
        # If encrypted_id is None, we can't get the original ID easily unless we used a deterministic hash
        # But we stored `name_hash` which is `student_{user_id}_{source_id}` hashed.
        # Wait, the Kiosk lookup hashes the input ID and checks against DB.
        # But memory cache expects { 'real_id': 'Name' } for fast lookup on scan?
        # NO, kiosk.js/UI sends raw ID. 
        # If we hash it in app, we can match.
        
        # Actually RosterService.get_student_name checks cache first.
        # If cache keys are raw IDs, we need raw IDs.
        # If we only have hashes in DB, we can't repopulate cache with raw IDs!
        
        # HOWEVER, the `api_roster_upload` set cache with what?
        # It didn't. It just called this missing function.
        
        # If we can't recover raw IDs, we can't "refresh" the cache fully for ID-based lookup
        # UNLESS we decrypt the encrypted_id.
        
        if s.encrypted_id:
            try:
                raw_id = cipher_suite.decrypt(s.encrypted_id.encode()).decode()
                new_cache[raw_id] = s.display_name
            except Exception:
                pass
                
    # 4. Set to cache
    if new_cache:
        set_memory_roster(new_cache, user_id)

def get_student_name(student_id: str, fallback: str = "Student", user_id: Optional[int] = None) -> str:
    """Get student name from memory or database (scoped to user)."""
    return roster_service.get_student_name(user_id, student_id, fallback) if roster_service else fallback

def is_student_banned(student_id: str, user_id: Optional[int] = None) -> bool:
    """Check if a student is banned from using the restroom (scoped to user)."""
    return ban_service.is_student_banned(user_id, student_id) if ban_service else False

def set_student_banned(student_id: str, banned_status: bool, user_id: Optional[int] = None) -> bool:
    """Ban or unban a student from using the restroom (scoped to user)."""
    return ban_service.set_student_banned(user_id, student_id, banned_status) if ban_service else False

def get_overdue_students(user_id: Optional[int] = None) -> List[Dict[str, Any]]:
    """Get list of students who are currently overdue (scoped to user)."""
    if not ban_service or not session_service:
        return []
    try:
        settings = get_settings(user_id)
        open_sessions = session_service.get_open_sessions(user_id)
        return ban_service.get_overdue_students(user_id, open_sessions, settings["overdue_minutes"])
    except Exception:
        return []

def auto_ban_overdue_students(user_id: Optional[int] = None) -> Dict[str, Any]:
    """Automatically ban students who are currently overdue (scoped to user)."""
    if not ban_service or not session_service:
        return {'count': 0, 'students': []}
    try:
        settings = get_settings(user_id)
        open_sessions = session_service.get_open_sessions(user_id)
        return ban_service.auto_ban_overdue_students(user_id, open_sessions, settings["overdue_minutes"])
    except Exception:
        return {'count': 0, 'students': []}

# ---------- Utility ----------

def now_utc():
    return datetime.now(timezone.utc)

def to_local(dt_utc):
    return dt_utc.astimezone(TZ)

def get_open_sessions(user_id: Optional[int] = None):
    """Get all currently open sessions (scoped to user)."""
    return session_service.get_open_sessions(user_id) if session_service else []

def get_current_holder(user_id: Optional[int] = None):
    """Get the first student currently holding the pass (scoped to user)."""
    return session_service.get_current_holder(user_id) if session_service else None

def get_settings(user_id: Optional[int] = None):
    """Get settings for a specific user. Creates default settings if user doesn't have any."""
    try:
        if user_id is not None:
            s = Settings.query.filter_by(user_id=user_id).first()
            if not s:
                # Create default settings for this user (isolated from all others)
                s = Settings(
                    user_id=user_id,
                    room_name="Hall Pass",
                    capacity=1,
                    overdue_minutes=10,
                    kiosk_suspended=False,
                    auto_ban_overdue=False
                )
                db.session.add(s)
                db.session.commit()
        else:
            # Legacy/anonymous: return defaults only (don't create or use global)
            return {
                "room_name": config.ROOM_NAME, 
                "capacity": config.CAPACITY, 
                "overdue_minutes": getattr(config, "MAX_MINUTES", 10), 
                "kiosk_suspended": False, 
                "auto_ban_overdue": False
            }
        
        # Handle case where columns might not exist yet (during migration)
        try:
            kiosk_suspended = s.kiosk_suspended
        except AttributeError:
            kiosk_suspended = False
        
        try:
            auto_ban_overdue = s.auto_ban_overdue
        except AttributeError:
            auto_ban_overdue = False
        
        return {
            "room_name": s.room_name, 
            "capacity": s.capacity, 
            "overdue_minutes": s.overdue_minutes, 
            "kiosk_suspended": kiosk_suspended, 
            "auto_ban_overdue": auto_ban_overdue,
            "enable_queue": getattr(s, 'enable_queue', False),
            "auto_promote_queue": getattr(s, 'auto_promote_queue', False)
        }
    except Exception:
        # If query fails, return defaults
        return {
            "room_name": config.ROOM_NAME, 
            "capacity": config.CAPACITY, 
            "overdue_minutes": getattr(config, "MAX_MINUTES", 10), 
            "kiosk_suspended": False, 
            "auto_ban_overdue": False,
            "enable_queue": False,
            "auto_promote_queue": False
        }

@app.context_processor
def inject_room_name():
    # Try to resolve user context to show correct room name
    token = request.args.get('token')
    user_id = get_current_user_id(token)
    return {"room": get_settings(user_id)["room_name"], "static_version": STATIC_VERSION}

# ---------- Admin Authentication ----------

def is_admin_authenticated():
    """Check if current session is authenticated as admin (Legacy Passcode OR Google OAuth)."""
    return session.get('admin_authenticated', False) or 'user_id' in session

def require_admin_auth(f):
    """Decorator to require admin authentication for a route."""
    from functools import wraps
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not is_admin_authenticated():
            return redirect(url_for('admin_login'))
        return f(*args, **kwargs)
    return decorated_function

def require_admin_auth_api(f):
    """Decorator to require admin authentication for API routes (returns JSON error)."""
    from functools import wraps
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not is_admin_authenticated():
            return jsonify(ok=False, message="Admin authentication required"), 401
        return f(*args, **kwargs)
    return decorated_function

# ---------- Routes ----------

# Register auth blueprint for Google OAuth (2.0)
from auth import auth_bp, init_oauth
app.register_blueprint(auth_bp)

# Register admin routes blueprint
from routes import register_blueprints
register_blueprints(app)
init_oauth(app)

@app.route("/")
def index():
    if os.path.exists(os.path.join(app.static_folder, 'index.html')):
        return send_from_directory(app.static_folder, 'index.html')
    return "Flutter App Not Built", 404

# Legacy kiosk route (for backward compatibility and logged-in users)
@app.route("/kiosk")
def kiosk():
    user_id = get_current_user_id()
    if user_id:
        # Redirect logged-in users to their personal kiosk
        user = User.query.get(user_id)
        if user and user.kiosk_token:
             return redirect(url_for('public_kiosk', token=user.kiosk_slug or user.kiosk_token))
    # Anonymous users get a landing page, not the functional kiosk
    return render_template("kiosk_landing.html")

# Public kiosk routes (2.0 - no login required, token-based)
# Serve Flutter static files (js, json, png, etc) from root
@app.route('/<path:filename>')
def serve_static(filename):
    """
    Serve static files from the 'static' folder for the root URL path.
    This enables Flutter Web assets (flutter.js, main.dart.js, assets/...) to load correctly.
    """
    return send_from_directory(app.static_folder, filename)

@app.route("/k/<token>")
@app.route("/kiosk/<token>")
def public_kiosk(token):
    """Public kiosk access via unique token or slug"""
    user = User.query.filter(
        (User.kiosk_token == token) | (User.kiosk_slug == token)
    ).first()
    if not user:
        return "Kiosk not found", 404
        
    # Check if Flutter app is built (in static folder)
    flutter_index = os.path.join(app.static_folder, 'index.html')
    if os.path.exists(flutter_index):
        # Serve the Flutter SPA
        return send_file(flutter_index)
        
    # Fallback to legacy template if Flutter not built
    return render_template("kiosk.html", user_id=user.id, user_name=user.name, token=token)

# Legacy display route (for backward compatibility)
@app.route("/display")
def display():
    user_id = get_current_user_id()
    if user_id:
        # Redirect logged-in users to their personal display
        user = User.query.get(user_id)
        if user and user.kiosk_token:
             return redirect(url_for('public_display', token=user.kiosk_slug or user.kiosk_token))
    # Anonymous users get the landing page
    return render_template("kiosk_landing.html")

# Public display routes (2.0 - no login required, token-based)
@app.route("/d/<token>")
@app.route("/display/<token>")
def public_display(token):
    """Public display access via unique token or slug"""
    user = User.query.filter(
        (User.kiosk_token == token) | (User.kiosk_slug == token)
    ).first()
    if not user:
        return "Display not found", 404
        
    # Check if Flutter app is built (in static folder)
    flutter_index = os.path.join(app.static_folder, 'index.html')
    if os.path.exists(flutter_index):
        # Serve the Flutter SPA
        return send_file(flutter_index)

    return render_template("display.html", user_id=user.id, user_name=user.name, token=token)

@app.route("/admin/login", methods=["GET"])
def admin_login():
    """Admin login page - OAuth only (legacy passcode removed)."""
    if is_admin_authenticated():
        return redirect(url_for('admin'))
    return render_template("admin_login.html")

@app.route("/admin/logout")
def admin_logout():
    session.pop('admin_authenticated', None)
    return redirect("/")

@app.route("/logout")
def logout():
    session.clear()
    return redirect("/")

@app.route("/admin")
@require_admin_auth
def admin():
    """Teacher-facing admin dashboard (Served via Flutter)"""
    if os.path.exists(os.path.join(app.static_folder, 'index.html')):
        return send_from_directory(app.static_folder, 'index.html')
    
    # Fallback to Legacy if Flutter not built
    # ... (Legacy logic effectively removed/hidden, but safely handled by check)
    return "Flutter App Not Built. Please run ./deploy.sh"


@app.route("/dev/login", methods=["GET", "POST"])
def dev_login():
    """Legacy Developer login page (Keep for direct access logic or removal?)
       Since Flutter DevScreen handles login, we might not need this if we rely purely on Flutter.
       But existing logic redirects here.
       Let's keep it as is for now, but /dev will bypass it to serve Flutter.
    """
    if session.get('dev_authenticated'):
        return redirect(url_for('dev'))
    
    if request.method == "POST":
        passcode = request.form.get("passcode", "").strip()
        if passcode == config.ADMIN_PASSCODE:
            session['dev_authenticated'] = True
            session.permanent = True
            return redirect(url_for('dev'))
        else:
            return render_template("dev_login.html", error="Invalid passcode")
    return render_template("dev_login.html")

@app.route("/dev")
def dev():
    """Developer-only page (Served via Flutter)"""
    # Note: We do NOT enforce auth here so that Flutter App can load and show its own Login Screen.
    # The API endpoint /api/dev/stats IS protected.
    
    if os.path.exists(os.path.join(app.static_folder, 'index.html')):
        return send_from_directory(app.static_folder, 'index.html')
    
# ============================================================================
# API ENDPOINTS FOR FLUTTER ADMIN/DEV DASHBOARDS
# ============================================================================
# --- Admin routes migrated to routes/admin.py ---
# 14 routes removed: stats, end_session, settings (3), roster (6), logs (2), control (2)

@app.route("/api/admin/roster")
def api_admin_roster():
    """API Endpoint: Get Roster List"""
    if not is_admin_authenticated():
        return jsonify(ok=False, error="Unauthorized", authenticated=False), 401
        
    user_id = get_current_user_id()
    students = StudentName.query
    if user_id is not None:
        students = students.filter_by(user_id=user_id)
    
    students = students.order_by(StudentName.display_name).all()
    
    return jsonify(
        ok=True,
        roster=[{"id": s.id, "name": s.display_name, "banned": s.banned} for s in students]
    )

@app.route("/api/dev/auth", methods=["POST"])
def api_dev_auth():
    """API Endpoint: Developer Login"""
    data = request.get_json()
    passcode = data.get("passcode", "").strip()
    
    if passcode == config.ADMIN_PASSCODE:
        session['dev_authenticated'] = True
        session.permanent = True
        return jsonify(ok=True)
    return jsonify(ok=False, error="Invalid Passcode"), 401

@app.route("/api/dev/stats")
def api_dev_stats():
    """API Endpoint: Get System Stats (Dev Only)"""
    if not session.get('dev_authenticated'):
        return jsonify(ok=False, error="Unauthorized", authenticated=False), 401
    
    # Global Stats
    return jsonify(
        ok=True,
        total_sessions=Session.query.count(),
        active_sessions=Session.query.filter_by(end_ts=None).count(),
        total_students=StudentName.query.count(),
        total_users=User.query.count(),
        settings=get_settings()
    )

# ---------- Keep-alive (Render) ----------
_keepalive_started = False

def _should_ping_now(ts_local: datetime) -> bool:
    # Monday=0 ... Sunday=6; work hours 8:00<=h<17:00
    return ts_local.weekday() < 5 and 8 <= ts_local.hour < 17


def _calculate_sleep_until_work_hours(now_local: datetime) -> int:
    """Calculate seconds to sleep until next work period (Mon-Fri 8am-5pm)"""
    # If currently in work hours, this shouldn't be called, but return short sleep as fallback
    if _should_ping_now(now_local):
        return 600  # 10 minutes
    
    # Calculate next Monday 8am if we're on weekend or after Friday 5pm
    current_weekday = now_local.weekday()  # Monday=0, Sunday=6
    current_hour = now_local.hour
    
    # If it's Friday after 5pm or weekend, sleep until Monday 8am
    if current_weekday == 4 and current_hour >= 17:  # Friday after 5pm
        days_until_monday = 3
        target_hour = 8
    elif current_weekday >= 5:  # Weekend (Saturday=5, Sunday=6)
        days_until_monday = 7 - current_weekday  # Saturday: 2 days, Sunday: 1 day
        target_hour = 8
    else:  # Monday-Thursday after hours or before 8am
        if current_hour >= 17:  # After 5pm, sleep until 8am next day
            days_until_monday = 1 if current_weekday < 4 else 3  # Next day or Monday if Thursday
            target_hour = 8
        else:  # Before 8am, sleep until 8am today
            days_until_monday = 0
            target_hour = 8
    
    # Calculate target datetime
    target_date = now_local.date() + timedelta(days=days_until_monday)
    target_datetime = datetime.combine(target_date, datetime.min.time().replace(hour=target_hour), tzinfo=now_local.tzinfo)
    
    # Calculate seconds until target time
    sleep_seconds = int((target_datetime - now_local).total_seconds())
    
    # Minimum sleep of 1 hour to avoid rapid checking if calculation goes wrong
    return max(sleep_seconds, 3600)


def _keep_alive_loop(base_url: str):
    target = urljoin(base_url, "/api/status")
    while True:
        try:
            now_local = datetime.now(TZ)
            if _should_ping_now(now_local):
                try:
                    requests.get(target, timeout=5)
                except Exception:
                    pass
                # every 10 minutes during work hours
                time.sleep(600)
            else:
                # Calculate time until next work period starts
                sleep_duration = _calculate_sleep_until_work_hours(now_local)
                time.sleep(sleep_duration)
        except Exception:
            time.sleep(600)


@app.before_request
def _redirect_https():
    """Redirect HTTP to HTTPS in production (Render, etc.)"""
    # Only redirect if we're behind a proxy (production) and request is HTTP
    # The X-Forwarded-Proto header is set by Render's load balancer
    if request.headers.get('X-Forwarded-Proto') == 'http':
        # Build HTTPS URL and redirect permanently
        url = request.url.replace('http://', 'https://', 1)
        return redirect(url, code=301)


@app.before_request
def _start_keepalive_thread():
    global _keepalive_started
    if _keepalive_started:
        return
    try:
        base = request.url_root  # e.g., https://yourapp.onrender.com/
    except Exception:
        return
    t = threading.Thread(target=_keep_alive_loop, args=(base,), daemon=True)
    t.start()
    _keepalive_started = True

# ---- API ----

@app.post("/api/scan")
def api_scan():
    payload = request.get_json(silent=True) or {}
    token = payload.get("token")
    user_id = get_current_user_id(token)

    # Check if kiosk is suspended
    settings = get_settings(user_id)
    if settings["kiosk_suspended"]:
        return jsonify(ok=False, message="Kiosk is currently suspended by administrator"), 403
    
    code = (payload.get("code") or "").strip()
    if not code:
        return jsonify(ok=False, message="No code scanned"), 400

    # Look up student name from encrypted database
    student_name = get_student_name(code, user_id=user_id)
    
    if student_name == "Student":  # Default fallback means student not found
        # Check if roster is actually empty
        if len(get_memory_roster(user_id)) == 0:
            return jsonify(ok=False, message="Roster empty. Please upload student list."), 404
        else:
            return jsonify(ok=False, message=f"Incorrect ID: {code}"), 404
    
    # Ensure minimal Student record exists for foreign key constraint
    # (Note: Student table is global in ID, but scoped via user_id FK if we wanted strict separation)
    # Ideally checking existence by ID is enough, but for 2.0 we might want to attach user_id if creating new
    if not Student.query.get(code):
        anonymous_student = Student(id=code, name=f"Anonymous_{code}", user_id=user_id)
        db.session.add(anonymous_student)
        db.session.commit()

    open_sessions = get_open_sessions(user_id)

    # If this student currently holds the pass, end their session
    # Check if auto-ban is enabled and student is overdue BEFORE ending session
    for s in open_sessions:
        if s.student_id == code:
            # Check if student is overdue and auto-ban is enabled
            # Check if student is overdue and auto-ban is enabled
            action = "ended"
            msg = None
            if settings.get("auto_ban_overdue", False):
                overdue_seconds = settings["overdue_minutes"] * 60
                if s.duration_seconds > overdue_seconds:
                    # Auto-ban this student for being overdue
                    if not is_student_banned(code, user_id=user_id):
                        set_student_banned(code, True, user_id=user_id)
                        print(f"AUTO-BAN ON SCAN-BACK: {student_name} ({code}) was overdue {round(s.duration_seconds / 60, 1)} minutes")
                        action = "ended_banned"
                        msg = "PASSED RETURNED LATE - AUTO BANNED"
            
            # End the session
            s.end_ts = now_utc()
            s.ended_by = "kiosk_scan"
            db.session.commit()
            
            # ---------------------------
            # AUTO-PROMOTE LOGIC
            # ---------------------------
            next_student_name = None
            if settings.get("enable_queue") and settings.get("auto_promote_queue"):
                # Check for next student
                next_in_line = Queue.query.filter_by(user_id=user_id).order_by(Queue.joined_ts.asc()).first()
                if next_in_line:
                    # Promote them!
                    next_code = next_in_line.student_id
                    
                    # Start session for ANY capacity (since we just freed one, or config allows)
                    # Actually, we should check if capacity is available, but since we ended 's', we have -1.
                    # Wait, if capacity was 1/1, now 0/1. So we can add.
                    
                    promoted_sess = Session(student_id=next_code, start_ts=now_utc(), room=settings["room_name"], user_id=user_id, ended_by="auto")
                    db.session.add(promoted_sess)
                    db.session.delete(next_in_line) # Remove from queue
                    db.session.commit()
                    
                    next_student_name = get_student_name(next_code, "Student", user_id=user_id)
                    action = "ended_auto_started" # Special action for UI
            
            return jsonify(ok=True, action=action, message=msg, name=student_name, next_student=next_student_name)
    
    # Check if student is banned from starting NEW restroom trips
    # (They can still end existing trips above)
    if is_student_banned(code, user_id=user_id):
        return jsonify(ok=False, action="banned", message="RESTROOM PRIVILEGES SUSPENDED - SEE TEACHER", name=student_name), 403

    # ---------------------------
    # QUEUE LOCK LOGIC
    # ---------------------------
    # If queue exists, scanner MUST be at the top to start.
    queue_count = Queue.query.filter_by(user_id=user_id).count()
    if queue_count > 0:
        top_spot = Queue.query.filter_by(user_id=user_id).order_by(Queue.joined_ts.asc()).first()
        if top_spot.student_id != code:
             # Scanner is NOT the top spot.
             # Check if they are already in queue (somewhere else)
             if Queue.query.filter_by(user_id=user_id, student_id=code).first():
                 return jsonify(ok=False, action="denied_queue_position", message="You are in the waitlist. Please wait for your turn (Queue Lock)."), 409
             else:
                 # New student trying to cut in line
                 # If Queue is enabled, auto-join them to the BACK.
                 if settings.get("enable_queue"):
                     q = Queue(student_id=code, user_id=user_id)
                     db.session.add(q)
                     db.session.commit()
                     return jsonify(ok=True, action="queued", message="Added to Waitlist (Queue is active)")
                 else:
                     return jsonify(ok=False, action="denied", message="Waitlist is active. Cannot start."), 409
        else:
            # Scanner IS the top spot. Allow and REMOVE from queue.
            db.session.delete(top_spot)
            # Proceed to start session...

    # ---------------------------
    # CAPACITY CHECK & START
    # ---------------------------
    if len(open_sessions) >= settings["capacity"]:
         # Queue Prompt / Auto-Join (Fail-safe for non-queue setups or race conditions)
         # Check if already in Queue (already checked above if queue>0, but if queue=0 and now full?)
         existing_q = Queue.query.filter_by(user_id=user_id, student_id=code).first()
         if existing_q:
              return jsonify(ok=False, action="denied_queue_position", message="You are in the waitlist."), 409
         
         if settings.get("enable_queue"):
             # Auto-Join Queue
             q = Queue(student_id=code, user_id=user_id)
             db.session.add(q)
             db.session.commit()
             return jsonify(ok=True, action="queued", message="Added to Waitlist")
         else:
             # Queue Disabled - Deny
             return jsonify(ok=False, action="denied", message="Pass limit reached."), 409

    # Otherwise start a new session
    # (Cleanup: Ensure not in queue if we reached here? logic above handles top_spot delete)
    # Double check just in case (e.g. queue was 0, but race condition?)
    Queue.query.filter_by(user_id=user_id, student_id=code).delete()
    
    sess = Session(student_id=code, start_ts=now_utc(), room=settings["room_name"], user_id=user_id)
    db.session.add(sess)
    db.session.commit()
    return jsonify(ok=True, action="started", name=student_name)

@app.route("/api/queue/reorder", methods=["POST"])
@require_admin_auth_api
def api_queue_reorder():
    """
    Reorder the waitlist.
    Payload: { "student_ids": ["id1", "id2", "id3"] }
    The order of IDs in the list determines their new position.
    We implement this by updating 'joined_ts' to preserve order.
    """
    user_id = get_current_user_id()
    payload = request.get_json(silent=True) or {}
    new_order = payload.get("student_ids", [])
    
    if not new_order:
         return jsonify(ok=False, message="No order provided"), 400

    # Strategy: Respace joined_ts starting from now, with 1 second increments?
    # Or just fetch all queue items, map them, and update joined_ts.
    
    current_queue = Queue.query.filter_by(user_id=user_id).all()
    queue_map = {q.student_id: q for q in current_queue}
    
    base_time = now_utc()
    
    # We want the first item in 'new_order' to be the oldest (first in line).
    # So we assign times such that item[0] < item[1] < item[2]...
    
    for i, student_id in enumerate(new_order):
        if student_id in queue_map:
            # Assign timestamps in increasing order
            # item 0 gets base_time, item 1 gets base_time + 1s, etc.
            queue_map[student_id].joined_ts = base_time + timedelta(seconds=i)
            
    db.session.commit()
    return jsonify(ok=True, message="Queue reordered")

@app.route("/api/queue/join", methods=["POST"])
def api_queue_join():
    payload = request.get_json(silent=True) or {}
    token = payload.get("token")
    code = payload.get("code")
    user_id = get_current_user_id(token)
    
    if not code: return jsonify(ok=False), 400
    
    # Check if already in queue
    if Queue.query.filter_by(user_id=user_id, student_id=code).first():
        return jsonify(ok=True, message="Already in queue")
        
    q = Queue(student_id=code, user_id=user_id)
    db.session.add(q)
    db.session.commit()
    return jsonify(ok=True)

@app.route("/api/queue/leave", methods=["POST"])
def api_queue_leave():
    payload = request.get_json(silent=True) or {}
    token = payload.get("token")
    code = payload.get("code")
    user_id = get_current_user_id(token)

    Queue.query.filter_by(user_id=user_id, student_id=code).delete()
    db.session.commit()
    return jsonify(ok=True)

@app.route("/api/queue/delete", methods=["POST"])
@require_admin_auth_api
def api_queue_delete():
    payload = request.get_json(silent=True) or {}
    student_id = payload.get("student_id") # Decrypted ID
    user_id = get_current_user_id()
    
    if not student_id:
        return jsonify(ok=False, error="Missing student_id"), 400

    Queue.query.filter_by(user_id=user_id, student_id=student_id).delete()
    db.session.commit()
    return jsonify(ok=True)

@app.get("/api/status")
def api_status():
    token = request.args.get('token')
    user_id = get_current_user_id(token)
    return jsonify(_build_status_payload(user_id))

def _sse_status_stream(token: Optional[str]):
    # Capture user_id at start of stream
    user_id = get_current_user_id(token)

    def stream():
        last_sig = None
        last_heartbeat = 0.0

        # Hint to EventSource clients how quickly to retry
        yield "retry: 3000\n\n"

        while True:
            # Reset transaction to see updates from other requests
            try:
                db.session.rollback()
            except Exception:
                pass

            payload = _build_status_payload(user_id)
            sig = _build_status_signature(payload)

            now = time.time()
            if sig != last_sig:
                yield f"data: {json.dumps(payload)}\n\n"
                last_sig = sig
                last_heartbeat = now
            elif now - last_heartbeat > 15:
                # Keep-alive comment so proxies don't buffer/timeout
                yield ": ping\n\n"
                last_heartbeat = now

            time.sleep(0.5)

    resp = Response(stream_with_context(stream()), mimetype="text/event-stream")
    resp.headers["Cache-Control"] = "no-cache"
    resp.headers["X-Accel-Buffering"] = "no"
    return resp


@app.get("/api/stream")
def api_stream():
    token = request.args.get("token")
    return _sse_status_stream(token)


@app.get("/events")
def sse_events():
    # Backwards-compatible alias (older clients / README)
    token = request.args.get("token")
    return _sse_status_stream(token)

@app.get("/api/stats")
def api_stats():
    """Simple stats: today's hourly counts and last 7 days daily counts."""
    user_id = get_current_user_id()
    today_local = datetime.now(TZ).date()
    start_today = datetime.combine(today_local, datetime.min.time(), tzinfo=TZ).astimezone(timezone.utc)
    end_today = datetime.combine(today_local, datetime.max.time(), tzinfo=TZ).astimezone(timezone.utc)
    
    query = Session.query.filter(Session.start_ts >= start_today, Session.start_ts <= end_today)
    if user_id is not None:
        query = query.filter_by(user_id=user_id)
        
    rows_today = query.all()

    hourly = [0]*24
    for r in rows_today:
        h = r.start_ts.astimezone(TZ).hour
        hourly[h] += 1

    # last 7 days including today
    daily_labels = []
    daily_counts = []
    for i in range(6, -1, -1):
        day = today_local - timedelta(days=i)
        ds = datetime.combine(day, datetime.min.time(), tzinfo=TZ).astimezone(timezone.utc)
        de = datetime.combine(day, datetime.max.time(), tzinfo=TZ).astimezone(timezone.utc)
        
        q = Session.query.filter(Session.start_ts >= ds, Session.start_ts <= de)
        if user_id is not None:
            q = q.filter_by(user_id=user_id)
            
        c = q.count()
        daily_labels.append(day.strftime("%a"))
        daily_counts.append(c)

    return jsonify({
        "hourly": hourly,
        "daily_labels": daily_labels,
        "daily_counts": daily_counts,
    })

@app.get("/api/stats/week")
def api_stats_week():
    """Weekly, per-student focus: counts and overdues (last 7 days including today)."""
    user_id = get_current_user_id()
    settings = get_settings(user_id)
    overdue_minutes = settings["overdue_minutes"]
    now = now_utc()
    start_utc = (datetime.now(TZ).date() - timedelta(days=6))
    start_utc = datetime.combine(start_utc, datetime.min.time(), tzinfo=TZ).astimezone(timezone.utc)
    
    query = Session.query.filter(Session.start_ts >= start_utc)
    if user_id is not None:
        query = query.filter_by(user_id=user_id)
        
    rows = query.all()

    per_student = {}
    for r in rows:
        sid = r.student_id
        # Prefer roster name over Student table name (fixes Anonymous entries)
        name = get_student_name(sid, "Unknown", user_id=user_id)
        if name == "Unknown" and r.student and r.student.name != "Student":
            name = r.student.name
        if sid not in per_student:
            per_student[sid] = {"name": name, "count": 0, "overdue": 0}
        per_student[sid]["count"] += 1
        end = r.end_ts or now
        duration = int((end - r.start_ts).total_seconds())
        if duration > overdue_minutes * 60:
            per_student[sid]["overdue"] += 1

    # top by count
    top_usage = sorted(per_student.values(), key=lambda x: x["count"], reverse=True)[:10]
    # top by overdue absolute
    top_overdue = sorted(per_student.values(), key=lambda x: x["overdue"], reverse=True)[:10]
    # top by overdue rate (only if count >= 1)
    for v in per_student.values():
        v["overdue_rate"] = (v["overdue"] / v["count"]) if v["count"] else 0
    top_overdue_rate = sorted(per_student.values(), key=lambda x: x["overdue_rate"], reverse=True)[:10]

    def pack(arr):
        return {"labels": [a["name"] for a in arr], "values": [a["count"] for a in arr], "overdues": [a["overdue"] for a in arr], "rates": [round(a.get("overdue_rate", 0)*100, 1) for a in arr]}

    return jsonify({
        "top_usage": pack(top_usage),
        "top_overdue": pack(top_overdue),
        "top_overdue_rate": {
            "labels": [a["name"] for a in top_overdue_rate],
            "values": [a["overdue"] for a in top_overdue_rate],
            "rates": [round(a["overdue_rate"]*100, 1) for a in top_overdue_rate],
        },
        "overdue_minutes": overdue_minutes,
    })

@app.post("/api/override_end")
@require_admin_auth_api
def api_override_end():
    user_id = get_current_user_id()
    s = get_current_holder(user_id)
    if not s:
        return jsonify(ok=False, message="No one is out."), 400
    s.end_ts = now_utc()
    s.ended_by = "override"
    db.session.commit()
    return jsonify(ok=True)


# Legacy suspend/resume endpoints removed - superseded by /api/settings/suspend


@app.post("/api/toggle_kiosk_suspend_quick")
def api_toggle_kiosk_suspend_quick():
    """Toggle kiosk suspension (for keyboard shortcut Ctrl+Shift+S)."""
    try:
        # Resolve user context from token (sent by frontend) or session
        payload = request.get_json(silent=True) or {}
        token = payload.get("token")
        user_id = get_current_user_id(token)
        
        if not user_id:
            return jsonify(ok=False, message="Invalid token or not authenticated"), 403
        
        # Get or create settings for this user
        s = Settings.query.filter_by(user_id=user_id).first()
        if not s:
            s = Settings(
                user_id=user_id,
                room_name="Hall Pass",
                capacity=1,
                overdue_minutes=10,
                kiosk_suspended=True,
                auto_ban_overdue=False,
                auto_promote_queue=False
            )
            db.session.add(s)
            new_state = True
        else:
            s.kiosk_suspended = not s.kiosk_suspended
            new_state = s.kiosk_suspended
        
        db.session.commit()
        return jsonify(ok=True, suspended=new_state, message=f"Kiosk {'suspended' if new_state else 'resumed'}")
    except Exception as e:
        db.session.rollback()
        return jsonify(ok=False, message=str(e)), 500

@app.get("/api/students")
@require_admin_auth_api
@handle_db_errors
def api_get_students():
    """Get list of all students with their ban status from the database."""
    user_id = get_current_user_id()
    # Get all students from database (scoped to user)
    # RosterService handles scoping via student_names table
    # StudentName query:
    query = StudentName.query
    if user_id is not None:
        query = query.filter_by(user_id=user_id)
        
    student_records = query.all()
    students = []
    
    for record in student_records:
        # Decrypt ID if available
        sid = None
        if record.encrypted_id:
            try:
                sid = cipher_suite.decrypt(record.encrypted_id.encode()).decode()
            except Exception:
                # If decryption fails (e.g. key changed), skip or show placeholder
                sid = f"ERR_{record.id}"
        
        if sid:
            students.append({
                'id': sid,
                'name': record.display_name,
                'banned': record.banned
            })
    
    # Sort alphabetically by name
    students.sort(key=lambda x: x['name'].lower())
    
    return jsonify(ok=True, students=students, count=len(students))

@app.post("/api/ban_student")
@require_admin_auth_api
@handle_db_errors
def api_ban_student():
    """Ban a student from using the restroom."""
    user_id = get_current_user_id()
    payload = request.get_json(silent=True) or {}
    student_id = payload.get('student_id', '').strip()
    
    if not student_id:
        return jsonify(ok=False, message="No student ID provided"), 400
    
    # Get student name to confirm they exist
    student_name = get_student_name(student_id, user_id=user_id)
    if student_name == "Student":
        return jsonify(ok=False, message="Student not found in roster"), 404
    
    # Set ban status
    success = set_student_banned(student_id, True, user_id=user_id)
    
    # Also end any active session
    active_session = Session.query.filter_by(student_id=student_id, end_ts=None, user_id=user_id).first()
    if active_session:
        active_session.end_ts = now_utc()
        active_session.ended_by = "admin_ban"
        db.session.commit()
    
    if success:
        msg = f"{student_name} banned"
        if active_session:
            msg += " and active session ended"
        return jsonify(ok=True, message=msg, student_id=student_id)
    else:
        return jsonify(ok=False, message="Failed to ban student"), 500

@app.post("/api/unban_student")
@require_admin_auth_api
@handle_db_errors
def api_unban_student():
    """Unban a student from using the restroom."""
    user_id = get_current_user_id()
    payload = request.get_json(silent=True) or {}
    student_id = payload.get('student_id', '').strip()
    
    if not student_id:
        return jsonify(ok=False, message="No student ID provided"), 400
    
    # Get student name to confirm they exist
    student_name = get_student_name(student_id, user_id=user_id)
    if student_name == "Student":
        return jsonify(ok=False, message="Student not found in roster"), 404
    
    # Remove ban status
    success = set_student_banned(student_id, False, user_id=user_id)
    
    if success:
        return jsonify(ok=True, message=f"{student_name} unbanned from restroom", student_id=student_id)
    else:
        return jsonify(ok=False, message="Failed to unban student"), 500

@app.get("/api/overdue_students")
@require_admin_auth_api
@handle_db_errors
def api_get_overdue_students():
    """Get list of students who are currently overdue."""
    user_id = get_current_user_id()
    overdue_list = get_overdue_students(user_id)
    settings = get_settings(user_id)
    
    return jsonify(
        ok=True, 
        students=overdue_list, 
        count=len(overdue_list),
        overdue_threshold_minutes=settings["overdue_minutes"]
    )

@app.post("/api/auto_ban_overdue")
@require_admin_auth_api
@handle_db_errors
def api_auto_ban_overdue():
    """Manually trigger auto-ban for all students who are currently overdue."""
    user_id = get_current_user_id()
    result = auto_ban_overdue_students(user_id)
    
    return jsonify(
        ok=True, 
        message=f"Manually banned {result['count']} overdue student(s)",
        banned_count=result['count'],
        students=result['students']
    )



@app.post("/api/upload_session_roster")
@require_admin_auth_api
def api_upload_session_roster():
    """Upload student roster to database (encrypted) for persistent access."""
    try:
        user_id = get_current_user_id()
        if "file" not in request.files:
            return jsonify(ok=False, message="No file uploaded"), 400
        
        f = request.files["file"]
        if not f or f.filename == '':
            return jsonify(ok=False, message="No file selected"), 400
            
        text = f.stream.read().decode("utf-8", errors="ignore")
        reader = csv.reader(io.StringIO(text))
        
        student_roster = {}
        count = 0
        
        # Clear existing memory roster to force refresh
        clear_memory_roster(user_id)
        
        # We don't clear the DB first - we upsert/add. 
        # If user wants to clear, they should use the clear endpoint first.
        
        for row in reader:
            if not row or len(row) < 2:
                continue
            sid, name = row[0].strip(), row[1].strip()
            if not sid or not name:
                continue
            student_roster[sid] = name
            count += 1
        
        # Store all students in DB using efficient batch method (single commit)
        db_stored = roster_service.store_student_names_batch(user_id, student_roster)
        
        # Populate memory cache for immediate performance
        set_memory_roster(student_roster, user_id)
        
        # Update any Anonymous students with real names from the roster
        # This global update needs review for multi-tenancy as Student table is mixed
        
        # Retroactively update any "Anonymous_ID" entries in database
        updated_count = roster_service.update_anonymous_students(user_id, Student)
            
        msg = f"Roster uploaded successfully ({count} students)."
        if updated_count > 0:
            msg += f" Updated {updated_count} previously anonymous entries."
        return jsonify(ok=True, imported=count, updated_anonymous=updated_count, message=msg)
        
    except Exception as e:
        return jsonify(ok=False, message=f"Upload failed: {str(e)}"), 500

@app.get("/api/memory_roster_status")
@require_admin_auth_api
def api_get_memory_roster_status():
    """Get memory roster status for admin display"""
    user_id = get_current_user_id()
    memory_roster = get_memory_roster(user_id)
    
    status = {
        'count': len(memory_roster),
        'active': len(memory_roster) > 0,
    }
    
    return jsonify(ok=True, **status)

@app.post("/api/clear_session_roster")
@require_admin_auth_api
def api_clear_session_roster():
    """Clear memory and database roster."""
    user_id = get_current_user_id()
    clear_memory_roster(user_id)
    roster_service.clear_all_student_names(user_id)
    return jsonify(ok=True, message="All rosters cleared")




@app.post("/api/admin/reset")
@require_admin_auth_api
def api_admin_reset():
    """
    Reset user data:
    - clear_sessions: Clear session history (logs/stats)
    - clear_roster: Clear student names/roster
    """
    try:
        user_id = get_current_user_id()
        payload = request.get_json(silent=True) or {}
        
        clear_sessions = payload.get("clear_sessions", False)
        clear_roster = payload.get("clear_roster", False)
        
        messages = []
        
        if clear_sessions:
            if session_service:
                success = session_service.clear_user_history(user_id)
                if success:
                    messages.append("Session history cleared")
                else:
                    return jsonify(ok=False, message="Failed to clear session history"), 500
        
        if clear_roster:
            if roster_service:
                success = roster_service.clear_all_student_names(user_id)
                if success:
                    messages.append("Student roster cleared")
                else:
                    return jsonify(ok=False, message="Failed to clear roster"), 500
                    
        return jsonify(ok=True, message=". ".join(messages) if messages else "No actions taken", cleared=messages)
        
    except Exception as e:
        return jsonify(ok=False, message=str(e)), 500

@app.post("/api/reset_database")
@require_admin_auth_api
def api_reset_database():
    """Legacy Endpoint: Reset: Delete user's sessions from database.
    
    This clears all session history for the current user. Student roster and settings are preserved.
    KEPT FOR BACKWARD COMPATIBILITY but functionality is duplicated in /api/admin/reset
    """
    try:
        user_id = get_current_user_id()
        
        if user_id is not None:
             # Scope delete to user
             total_sessions = Session.query.filter_by(user_id=user_id).delete()
        else:
             # Legacy global wipe
             total_sessions = Session.query.delete()
             
        db.session.commit()

        return jsonify(
            ok=True,
            cleared_sessions=total_sessions,
            message="Database reset complete - sessions removed"
        )
    except Exception as e:
        try:
            db.session.rollback()
        except Exception:
            pass
        return jsonify(ok=False, message=f"Reset failed: {str(e)}"), 500

@app.get("/export.csv")
def export_csv():
    """Export sessions for the current day in local timezone."""
    # Note: export.csv is usually hit by browser so cookie auth works if admin logged in.
    # We should require authentication explicitly if not already (it wasn't fastidiously enforced before?)
    # Adding @require_admin_auth wrapper or just handling it inside
    if not is_admin_authenticated():
        return redirect(url_for('admin_login'))
        
    user_id = get_current_user_id()
    today_local = datetime.now(TZ).date()
    start = datetime.combine(today_local, datetime.min.time(), tzinfo=TZ).astimezone(timezone.utc)
    end = datetime.combine(today_local, datetime.max.time(), tzinfo=TZ).astimezone(timezone.utc)

    query = Session.query.filter(Session.start_ts >= start, Session.start_ts <= end)
    if user_id is not None:
        query = query.filter_by(user_id=user_id)
        
    rows = query.order_by(Session.start_ts.asc()).all()

    out = io.StringIO()
    w = csv.writer(out)
    w.writerow(["student_id", "name", "start_local", "end_local", "duration_seconds", "ended_by", "overdue"])
    
    settings = get_settings(user_id)
    overdue_minutes = settings["overdue_minutes"]
    
    for r in rows:
        start_local = r.start_ts.astimezone(TZ).strftime("%Y-%m-%d %H:%M:%S")
        end_local = r.end_ts.astimezone(TZ).strftime("%Y-%m-%d %H:%M:%S") if r.end_ts else ""
        duration = r.duration_seconds if r.end_ts else int((now_utc() - r.start_ts).total_seconds())
        is_overdue = duration > overdue_minutes * 60
        w.writerow([r.student_id, r.student.name, start_local, end_local, duration if r.end_ts else "", r.ended_by or "", "YES" if is_overdue else "NO"])
    out.seek(0)

    return send_file(
        io.BytesIO(out.getvalue().encode("utf-8")),
        mimetype="text/csv",
        as_attachment=True,
        download_name="hallpass_export.csv",
    )

@app.post("/api/settings/kiosk-slug")
@require_admin_auth_api
def api_set_kiosk_slug():
    """Set a custom slug for the kiosk URL."""
    try:
        user_id = get_current_user_id()
        if not user_id:
            return jsonify(ok=False, message="Feature available for registered users only"), 403
            
        payload = request.get_json(silent=True) or {}
        slug = payload.get("slug", "").strip()
        
        # Validation
        if not slug:
            return jsonify(ok=False, message="Slug cannot be empty"), 400
            
        if len(slug) < 3:
            return jsonify(ok=False, message="Slug must be at least 3 characters"), 400
            
        import re
        if not re.match(r"^[a-zA-Z0-9-_]+$", slug):
            return jsonify(ok=False, message="Slug can only contain letters, numbers, hyphens, and underscores"), 400
            
        # Check uniqueness
        existing_user = User.query.filter(
            (User.kiosk_slug == slug) | (User.kiosk_token == slug)
        ).first()
        
        if existing_user and existing_user.id != user_id:
             return jsonify(ok=False, message="Slug is already taken"), 409
             
        # Update user
        user = User.query.get(user_id)
        user.kiosk_slug = slug
        db.session.commit()
        
        return jsonify(ok=True, slug=slug, message="Kiosk URL updated successfully")
        
    except Exception as e:
        db.session.rollback()
        return jsonify(ok=False, message=str(e)), 500

# ---------- Developer API ----------

@app.get("/api/dev/users")
@require_admin_auth_api
def api_dev_users():
    """Get list of all users (developer only)"""
    try:
        users = User.query.all()
        user_list = []
        for u in users:
            session_count = Session.query.filter_by(user_id=u.id).count()
            roster_count = StudentName.query.filter_by(user_id=u.id).count()
            user_list.append({
                'id': u.id,
                'email': u.email,
                'name': u.name,
                'is_admin': u.is_admin,
                'kiosk_token': u.kiosk_token,
                'kiosk_slug': u.kiosk_slug,
                'session_count': session_count,
                'roster_count': roster_count,
                'created_at': u.created_at.isoformat() if u.created_at else None,
                'last_login': u.last_login.isoformat() if u.last_login else None,
            })
        return jsonify(ok=True, users=user_list, count=len(user_list))
    except Exception as e:
        return jsonify(ok=False, message=str(e)), 500


@app.post("/api/dev/set_admin")
@require_admin_auth_api
def api_dev_set_admin():
    """Set a user's admin flag (developer only)"""
    payload = request.get_json(silent=True) or {}
    target_user_id = payload.get('user_id')
    is_admin = payload.get('is_admin', False)
    
    if not target_user_id:
        return jsonify(ok=False, message="user_id required"), 400
    
    try:
        user = User.query.get(target_user_id)
        if not user:
            return jsonify(ok=False, message="User not found"), 404
        
        user.is_admin = is_admin
        db.session.commit()
        return jsonify(ok=True, message=f"User {user.email} admin status: {is_admin}")
    except Exception as e:
        db.session.rollback()
        return jsonify(ok=False, message=str(e)), 500

# ---------- CLI helpers ----------

@app.cli.command("init-db")
def init_db():
    """Initialize database tables and default settings."""
    db.create_all()
    if not Settings.query.get(1):
        db.session.add(Settings(id=1, room_name=config.ROOM_NAME, capacity=config.CAPACITY, overdue_minutes=getattr(config, "MAX_MINUTES", 10), kiosk_suspended=False, auto_ban_overdue=False, auto_promote_queue=False, enable_queue=False))
        db.session.commit()
    print("Database initialized successfully.")


def run_migrations():
    """Perform schema migrations and return log messages.

    This function is written to be safe on PostgreSQL where a failed statement
    puts the transaction into an error state. We explicitly roll back before
    executing DDL and run DDL inside an engine-level transaction block.
    """
    messages = []

    # Migration 1: ensure Settings.kiosk_suspended exists
    kiosk_suspended_exists = False
    try:
        # Prefer information_schema to avoid raising exceptions
        res = db.session.execute(text(
            """
            SELECT 1
            FROM information_schema.columns
            WHERE table_name = 'settings' AND column_name = 'kiosk_suspended'
            """
        ))
        kiosk_suspended_exists = res.scalar() is not None
    except Exception as e:
        messages.append(f"Warning: column introspection failed: {e}; attempting ALTER TABLE…")

    if not kiosk_suspended_exists:
        messages.append("Adding kiosk_suspended column to settings table")

        # Clear any failed transaction state before running DDL
        try:
            db.session.rollback()
        except Exception:
            pass

        try:
            # Use engine.begin() so DDL is committed independently of the ORM session
            with db.engine.begin() as conn:
                conn.execute(text("ALTER TABLE settings ADD COLUMN IF NOT EXISTS kiosk_suspended BOOLEAN DEFAULT FALSE"))
                conn.execute(text("UPDATE settings SET kiosk_suspended = FALSE WHERE kiosk_suspended IS NULL"))
                conn.execute(text("ALTER TABLE settings ALTER COLUMN kiosk_suspended SET NOT NULL"))
            messages.append("Added kiosk_suspended column successfully")
        except Exception as e:
            # Make sure session is usable afterwards
            try:
                db.session.rollback()
            except Exception:
                pass
            messages.append(f"Failed to add kiosk_suspended column: {e}")
            raise
    else:
        messages.append("kiosk_suspended column already exists")

    # Migration 2: ensure StudentName.banned exists
    banned_exists = False
    try:
        res = db.session.execute(text(
            """
            SELECT 1
            FROM information_schema.columns
            WHERE table_name = 'student_name' AND column_name = 'banned'
            """
        ))
        banned_exists = res.scalar() is not None
    except Exception as e:
        messages.append(f"Warning: banned column introspection failed: {e}; attempting ALTER TABLE…")

    if not banned_exists:
        messages.append("Adding banned column to student_name table")

        # Clear any failed transaction state before running DDL
        try:
            db.session.rollback()
        except Exception:
            pass

        try:
            # Use engine.begin() so DDL is committed independently of the ORM session
            with db.engine.begin() as conn:
                conn.execute(text("ALTER TABLE student_name ADD COLUMN IF NOT EXISTS banned BOOLEAN DEFAULT FALSE"))
                conn.execute(text("UPDATE student_name SET banned = FALSE WHERE banned IS NULL"))
                conn.execute(text("ALTER TABLE student_name ALTER COLUMN banned SET NOT NULL"))
            messages.append("Added banned column successfully")
        except Exception as e:
            # Make sure session is usable afterwards
            try:
                db.session.rollback()
            except Exception:
                pass
            messages.append(f"Failed to add banned column: {e}")
            raise
    else:
        messages.append("banned column already exists")

    # Migration 3: ensure Settings.auto_ban_overdue exists
    auto_ban_overdue_exists = False
    try:
        res = db.session.execute(text(
            """
            SELECT 1
            FROM information_schema.columns
            WHERE table_name = 'settings' AND column_name = 'auto_ban_overdue'
            """
        ))
        auto_ban_overdue_exists = res.scalar() is not None
    except Exception as e:
        messages.append(f"Warning: auto_ban_overdue column introspection failed: {e}; attempting ALTER TABLE…")

    if not auto_ban_overdue_exists:
        messages.append("Adding auto_ban_overdue column to settings table")

        # Clear any failed transaction state before running DDL
        try:
            db.session.rollback()
        except Exception:
            pass

        try:
            # Use engine.begin() so DDL is committed independently of the ORM session
            with db.engine.begin() as conn:
                conn.execute(text("ALTER TABLE settings ADD COLUMN IF NOT EXISTS auto_ban_overdue BOOLEAN DEFAULT FALSE"))
                conn.execute(text("UPDATE settings SET auto_ban_overdue = FALSE WHERE auto_ban_overdue IS NULL"))
                conn.execute(text("ALTER TABLE settings ALTER COLUMN auto_ban_overdue SET NOT NULL"))
            messages.append("Added auto_ban_overdue column successfully")
        except Exception as e:
            # Make sure session is usable afterwards
            try:
                db.session.rollback()
            except Exception:
                pass
            messages.append(f"Failed to add auto_ban_overdue column: {e}")
            raise
    else:
        messages.append("auto_ban_overdue column already exists")

    # Migration 4: ensure Settings.auto_promote_queue exists
    auto_promote_queue_exists = False
    try:
        res = db.session.execute(text(
            """
            SELECT 1
            FROM information_schema.columns
            WHERE table_name = 'settings' AND column_name = 'auto_promote_queue'
            """
        ))
        auto_promote_queue_exists = res.scalar() is not None
    except Exception as e:
         messages.append(f"Warning: auto_promote_queue column introspection failed: {e}; attempting ALTER TABLE...")

    if not auto_promote_queue_exists:
        messages.append("Adding auto_promote_queue column to settings table")
        try:
            db.session.rollback()
        except Exception:
            pass

        try:
            with db.engine.begin() as conn:
                conn.execute(text("ALTER TABLE settings ADD COLUMN IF NOT EXISTS auto_promote_queue BOOLEAN DEFAULT FALSE"))
                conn.execute(text("UPDATE settings SET auto_promote_queue = FALSE WHERE auto_promote_queue IS NULL"))
                conn.execute(text("ALTER TABLE settings ALTER COLUMN auto_promote_queue SET NOT NULL"))
            messages.append("Added auto_promote_queue column successfully")
        except Exception as e:
            try: db.session.rollback() 
            except Exception: pass
            messages.append(f"Failed to add auto_promote_queue column: {e}")
            raise
    else:
        messages.append("auto_promote_queue column already exists")

    # Migration 5: ensure Settings.enable_queue exists
    enable_queue_exists = False
    try:
        res = db.session.execute(text(
            """
            SELECT 1
            FROM information_schema.columns
            WHERE table_name = 'settings' AND column_name = 'enable_queue'
            """
        ))
        enable_queue_exists = res.scalar() is not None
    except Exception as e:
         messages.append(f"Warning: enable_queue column introspection failed: {e}; attempting ALTER TABLE...")

    if not enable_queue_exists:
        messages.append("Adding enable_queue column to settings table")
        try:
            db.session.rollback()
        except Exception:
            pass

        try:
            with db.engine.begin() as conn:
                conn.execute(text("ALTER TABLE settings ADD COLUMN IF NOT EXISTS enable_queue BOOLEAN DEFAULT FALSE"))
                conn.execute(text("UPDATE settings SET enable_queue = FALSE WHERE enable_queue IS NULL"))
                conn.execute(text("ALTER TABLE settings ALTER COLUMN enable_queue SET NOT NULL"))
            messages.append("Added enable_queue column successfully")
        except Exception as e:
            try: db.session.rollback() 
            except Exception: pass
            messages.append(f"Failed to add enable_queue column: {e}")
            raise
    else:
        messages.append("enable_queue column already exists")

    # Migration 6: ensure StudentName.encrypted_id exists
    try:
        with db.engine.connect() as conn:
            res = conn.execute(text(
                "SELECT column_name FROM information_schema.columns WHERE table_name='student_name' AND column_name='encrypted_id'"
            ))
            if res.scalar():
                messages.append("encrypted_id column already exists")
            else:
                conn.execute(text("ALTER TABLE student_name ADD COLUMN IF NOT EXISTS encrypted_id VARCHAR"))
                conn.commit()
                messages.append("Added encrypted_id column successfully")
                
    except Exception as e:
        messages.append(f"Failed to add encrypted_id column: {e}")
        raise e

    # ===== 2.0 MIGRATIONS =====
    
    # Migration 5: Create User table if not exists
    try:
        db.create_all()  # This will create User table if it doesn't exist
        messages.append("User table created/verified")
    except Exception as e:
        messages.append(f"Warning: User table creation: {e}")
    
    # Migration 5b: Ensure all User table columns exist (fixes partial table creation)
    user_columns = [
        ("user", "google_id", "VARCHAR"),
        ("user", "email", "VARCHAR"),
        ("user", "name", "VARCHAR"),
        ("user", "picture_url", "VARCHAR"),
        ("user", "kiosk_token", "VARCHAR"),
        ("user", "kiosk_slug", "VARCHAR"),
        ("user", "created_at", "TIMESTAMP WITH TIME ZONE"),
        ("user", "last_login", "TIMESTAMP WITH TIME ZONE"),
        ("user", "is_admin", "BOOLEAN DEFAULT FALSE"),
    ]
    
    for table_name, column_name, column_type in user_columns:
        try:
            res = db.session.execute(text(f"""
                SELECT 1 FROM information_schema.columns
                WHERE table_name = '{table_name}' AND column_name = '{column_name}'
            """))
            if res.scalar() is None:
                messages.append(f"Adding {column_name} to {table_name}")
                try:
                    db.session.rollback()
                except Exception:
                    pass
                with db.engine.begin() as conn:
                    conn.execute(text(f'ALTER TABLE "{table_name}" ADD COLUMN IF NOT EXISTS {column_name} {column_type}'))
                messages.append(f"Added {column_name} to {table_name}")
        except Exception as e:
            messages.append(f"User column {column_name}: {e}")
            
    # Migration 5c: Cleanup legacy display_name column if it exists (causes NOT NULL errors)
    try:
        res = db.session.execute(text("""
            SELECT 1 FROM information_schema.columns 
            WHERE table_name = 'user' AND column_name = 'display_name'
        """))
        if res.scalar() is not None:
            messages.append("Found legacy display_name column. Cleaning up...")
            try:
                db.session.rollback()
            except Exception:
                pass
            with db.engine.begin() as conn:
                # Copy display_name to name if name is null
                conn.execute(text('UPDATE "user" SET name = display_name WHERE name IS NULL'))
                # Drop the legacy column
                conn.execute(text('ALTER TABLE "user" DROP COLUMN display_name'))
            messages.append("Removed legacy display_name column")
    except Exception as e:
        messages.append(f"Warning: display_name cleanup: {e}")
    
    # Migration 6: Add user_id columns to existing tables
    user_id_migrations = [
        ("settings", "user_id"),
        ("session", "user_id"),
        ("student_name", "user_id"),
        ("student", "user_id"),
    ]
    
    for table_name, column_name in user_id_migrations:
        column_exists = False
        try:
            res = db.session.execute(text(f"""
                SELECT 1 FROM information_schema.columns
                WHERE table_name = '{table_name}' AND column_name = '{column_name}'
            """))
            column_exists = res.scalar() is not None
        except Exception:
            pass
        
        if not column_exists:
            messages.append(f"Adding {column_name} column to {table_name} table")
            try:
                db.session.rollback()
            except Exception:
                pass
            
            try:
                with db.engine.begin() as conn:
                    conn.execute(text(f"ALTER TABLE {table_name} ADD COLUMN IF NOT EXISTS {column_name} INTEGER"))
                messages.append(f"Added {column_name} to {table_name} successfully")
            except Exception as e:
                try:
                    db.session.rollback()
                except Exception:
                    pass
                messages.append(f"Failed to add {column_name} to {table_name}: {e}")
        else:
            messages.append(f"{column_name} column already exists in {table_name}")
    
    # Migration 7: Create default migration user for legacy data if needed
    try:
        # Check if there's any legacy data without user_id
        legacy_settings = Settings.query.filter_by(user_id=None).first()
        if legacy_settings:
            # Check if migration user exists
            migration_user = User.query.filter_by(google_id="LEGACY_MIGRATION").first()
            if not migration_user:
                import secrets
                migration_user = User(
                    google_id="LEGACY_MIGRATION",
                    email="legacy@halllday.local",
                    name="Legacy Data (Pre-2.0)",
                    kiosk_token=secrets.token_urlsafe(16)
                )
                db.session.add(migration_user)
                db.session.commit()
                messages.append(f"Created migration user (ID: {migration_user.id})")
            
            # Backfill user_id on legacy records
            Settings.query.filter_by(user_id=None).update({Settings.user_id: migration_user.id})
            Session.query.filter_by(user_id=None).update({Session.user_id: migration_user.id})
            StudentName.query.filter_by(user_id=None).update({StudentName.user_id: migration_user.id})
            Student.query.filter_by(user_id=None).update({Student.user_id: migration_user.id})
            db.session.commit()
            messages.append("Backfilled user_id on legacy records")
        else:
            messages.append("No legacy data migration needed")
    except Exception as e:
        try:
            db.session.rollback()
        except Exception:
            pass
        messages.append(f"Legacy data migration: {e}")

    # Migration 8: Drop old unique constraint on student_name.name_hash (replaced by composite)
    try:
        # Check if old constraint exists
        res = db.session.execute(text("""
            SELECT 1 FROM information_schema.table_constraints
            WHERE table_name = 'student_name' AND constraint_name = 'student_name_name_hash_key'
        """))
        old_constraint_exists = res.scalar() is not None
        
        if old_constraint_exists:
            messages.append("Dropping legacy student_name_name_hash_key constraint...")
            try:
                db.session.rollback()
            except Exception:
                pass
            
            with db.engine.begin() as conn:
                conn.execute(text("ALTER TABLE student_name DROP CONSTRAINT IF EXISTS student_name_name_hash_key"))
            messages.append("Dropped legacy constraint successfully")
        else:
            messages.append("Legacy name_hash constraint already dropped")
    except Exception as e:
        messages.append(f"Warning: constraint migration: {e}")

    return messages


@app.cli.command("migrate")
def migrate_db():
    """Run database migrations for schema updates."""
    print("Running database migrations...")
    try:
        messages = run_migrations()
        for m in messages:
            print(f"- {m}")
        print("Database migrations completed successfully!")
    except Exception as e:
        print(f"Migration failed: {e}")

# ---- Debug & Migration API ----

@app.get("/api/debug/settings")
def api_debug_settings():
    """Expose raw settings row for debugging purposes."""
    try:
        s = Settings.query.get(1)
        if not s:
            return jsonify(ok=True, settings=None)
        data = {
            "id": s.id,
            "room_name": s.room_name,
            "capacity": s.capacity,
            "overdue_minutes": s.overdue_minutes,
        }
        try:
            data["kiosk_suspended"] = s.kiosk_suspended
        except AttributeError:
            data["kiosk_suspended"] = "<missing>"
        return jsonify(ok=True, settings=data)
    except Exception as e:
        return jsonify(ok=False, message=str(e)), 500

@app.get("/api/debug/database")
def api_debug_database():
    """Debug endpoint to check database status - accessible without auth for troubleshooting."""
    debug_info = {
        "database_url": app.config['SQLALCHEMY_DATABASE_URI'][:50] + "..." if len(app.config['SQLALCHEMY_DATABASE_URI']) > 50 else app.config['SQLALCHEMY_DATABASE_URI'],
        "tables_exist": {},
        "settings_record": None,
        "session_count": None,
        "errors": []
    }
    
    # Check if each table exists and can be queried
    tables_to_check = [
        ("settings", Settings),
        ("session", Session),
        ("student", Student),
        ("student_name", StudentName)
    ]
    
    for table_name, model_class in tables_to_check:
        try:
            count = model_class.query.count()
            debug_info["tables_exist"][table_name] = f"exists ({count} records)"
        except Exception as e:
            debug_info["tables_exist"][table_name] = f"error: {str(e)}"
            debug_info["errors"].append(f"{table_name}: {str(e)}")
    
    # Try to get settings record
    try:
        s = Settings.query.get(1)
        if s:
            debug_info["settings_record"] = {
                "id": s.id,
                "room_name": s.room_name,
                "capacity": s.capacity,
                "overdue_minutes": s.overdue_minutes,
                "kiosk_suspended": getattr(s, 'kiosk_suspended', 'missing_column')
            }
        else:
            debug_info["settings_record"] = "not_found"
    except Exception as e:
        debug_info["settings_record"] = f"error: {str(e)}"
        debug_info["errors"].append(f"settings_query: {str(e)}")
    
    # Try to count sessions
    try:
        debug_info["session_count"] = Session.query.count()
    except Exception as e:
        debug_info["session_count"] = f"error: {str(e)}"
        debug_info["errors"].append(f"session_count: {str(e)}")
    
    return jsonify(ok=True, debug=debug_info)


@app.post("/api/migrate")
@require_admin_auth_api
def migrate_api():
    """Run database migrations via HTTP for platforms without shell access."""
    try:
        messages = run_migrations()
        return jsonify(ok=True, messages=messages)
    except Exception as e:
        # Ensure the session is usable after an error
        try:
            db.session.rollback()
        except Exception:
            pass
        return jsonify(ok=False, message=str(e)), 500

# ---- Settings API ----
@app.get("/api/settings")
@require_admin_auth_api
def get_settings_api():
    return jsonify(get_settings())



@app.route("/api/dev/expanded_stats", methods=["POST"])
def api_dev_expanded_stats():
    """Get expanded stats for Dev Dashboard (God Mode).
    Authenticated via dev passcode only.
    """
    if not session.get('dev_authenticated'):
        data = request.get_json(silent=True) or {}
        passcode = data.get('passcode')
        
        if passcode != os.environ.get("DEV_PASSCODE") and passcode != config.ADMIN_PASSCODE:
            # Security by obscurity - pretend it doesn't exist or just 401
            return jsonify(ok=False, error="Unauthorized"), 401
        
    # --- Global Stats ---
    total_sessions = Session.query.count()
    active_sessions = Session.query.filter(Session.end_ts == None).count()
    total_students = Student.query.count()
    total_users = User.query.count()
    
    # --- Active Teachers List ---
    # We want: email, active_count, total_count, last_active
    # This might be heavy if many users, but fine for now.
    teachers_data = []
    users = User.query.all()
    
    for u in users:
        # Optimization: Could allow raw SQL for performance later
        u_total = Session.query.filter_by(user_id=u.id).count()
        u_active = Session.query.filter_by(user_id=u.id, end_ts=None).count()
        
        teachers_data.append({
            "email": u.email,
            "active_sessions": u_active,
            "total_sessions": u_total,
            "last_login": u.last_login.isoformat() if u.last_login else None
        })
        
    # Sort by active sessions desc, then recent login
    teachers_data.sort(key=lambda x: (x['active_sessions'], x['last_login'] or ""), reverse=True)
    
    # --- Recent System Activity ---
    # Fetch last 20 sessions across ALL users
    recent_sess = Session.query.order_by(Session.start_ts.desc()).limit(20).all()
    activity_log = []
    
    for s in recent_sess:
        teacher_email = s.user.email if s.user else "Unknown"
        # ANONYMIZE STUDENT DATA
        # We do NOT show s.student.name or s.student_id
        # We just show "Student"
        
        action = "Active Pass"
        if s.end_ts:
            action = "Returned Pass"
            
        activity_log.append({
            "timestamp": s.start_ts.isoformat(),
            "teacher": teacher_email,
            "action": f"{action} ({s.room or 'Unknown Room'})",
            # Calculate duration string if ended, else "Ongoing"
            "duration": f"{s.duration_seconds // 60}m" if s.end_ts else "Ongoing"
        })
        
    return jsonify({
        "ok": True,
        "global_stats": {
            "total_sessions": total_sessions,
            "active_sessions": active_sessions,
            "total_students": total_students,
            "total_users": total_users,
        },
        "teachers": teachers_data,
        "activity": activity_log
    })

if __name__ == "__main__":
    with app.app_context():
        db.create_all()
    app.run(host="0.0.0.0", port=5001, debug=True)

# Run automatic initialization (must be after all functions are defined)
# Only run this if we are in the main process (not a reloader or worker)
if os.environ.get("WERKZEUG_RUN_MAIN") == "true" or not os.environ.get("WERKZEUG_RUN_MAIN"):
    try:
        initialize_database_if_needed()
    except Exception as e:
        print(f"Startup initialization failed: {e}")

# CRITICAL FIX for Render/Gunicorn with --preload:
# We must close the database connection pool in the parent process after initialization.
# This forces each forked worker to create its own clean SSL connection.
# Without this, workers inherit a broken SSL state and fail with "decryption failed".
with app.app_context():
    db.engine.dispose()

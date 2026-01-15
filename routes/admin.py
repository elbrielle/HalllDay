"""
Admin Routes Blueprint - Roster, Settings, Logs Management

IMPORTANT: This file contains PARTIAL migration from app.py
Status: 2/14 routes migrated (proof-of-concept complete)
See PLANNING.md for remaining routes to migrate.
"""
from flask import Blueprint, jsonify, request, send_file, current_app, session
from functools import wraps
from datetime import datetime, timezone, timedelta
import csv
import io

# Create blueprint
admin_bp = Blueprint('admin', __name__)

# Note: Import these from app.py context when registering blueprint
# from app import db, User, Settings, Session, StudentName, Queue, Roster
# from services.roster import RosterService
# from services.ban import BanService
# from services.session import SessionService


def require_admin_auth_api(f):
    """Decorator to require admin authentication for API routes"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # Check if authenticated (legacy passcode OR Google OAuth)
        if not (session.get('admin_authenticated', False) or 'user_id' in session):
            return jsonify(ok=False, message="Admin authentication required"), 401
        return f(*args, **kwargs)
    return decorated_function


def get_current_user_id():
    """Get current user ID from session - IMPORTED FROM app.py"""
    # Will need to import from app.py or create shared utils
    from app import User
    if 'user_id' in session:
        return session['user_id']
    user = User.query.first()
    return user.id if user else None


# ============================================================================
# MIGRATED ROUTES (2/14 complete)
# ============================================================================

@admin_bp.route('/api/admin/stats')
def api_admin_stats():
    """API Endpoint: Get Admin Dashboard Stats & Insights"""
    from app import (db, User, Settings, Session as SessionModel, StudentName, Queue,
                     is_admin_authenticated, get_settings, get_student_name, 
                     get_memory_roster, now_utc, handle_db_errors)
    
    if not is_admin_authenticated():
        return jsonify(ok=False, error="Unauthorized", authenticated=False), 401
    
    user_id = get_current_user_id()
    
    # Get User Info
    current_user = None
    if user_id:
        current_user = User.query.get(user_id)
        
    public_urls = {}
    if current_user:
        base_url = request.url_root.rstrip('/')
        public_urls = current_user.get_public_urls(base_url)

    # Scope queries
    query_session = SessionModel.query
    query_open = SessionModel.query.filter_by(end_ts=None)
    query_roster = StudentName.query
    
    if user_id is not None:
        query_session = query_session.filter_by(user_id=user_id)
        query_open = query_open.filter_by(user_id=user_id)
        query_roster = query_roster.filter_by(user_id=user_id)
    
    # Insights Logic (Python-side aggregation)
    start_date = datetime.now(timezone.utc) - timedelta(days=30)
    sessions = query_session.filter(SessionModel.start_ts >= start_date).all()
    
    student_stats = {}
    settings = get_settings(user_id)
    overdue_limit = settings["overdue_minutes"] * 60
    
    for s in sessions:
        sid = s.student_id
        if sid not in student_stats:
            student_stats[sid] = {"count": 0, "overdue": 0}
        
        stat = student_stats[sid]
        stat["count"] += 1
        
        # Check overdue
        end_time = s.end_ts or now_utc()
        duration = (end_time - s.start_ts).total_seconds()
        if duration > overdue_limit:
            stat["overdue"] += 1
            
    # Convert to list and sort
    def resolve_top(stats_dict, sort_key, limit=5):
        sorted_items = sorted(stats_dict.items(), key=lambda x: x[1][sort_key], reverse=True)[:limit]
        result = []
        for sid, data in sorted_items:
            name = get_student_name(sid, "Unknown", user_id=user_id)
            result.append({"name": name if name != "Unknown" else f"ID: {sid}", "count": data[sort_key]})
        return result

    insights = {
        "top_students": resolve_top(student_stats, "count"),
        "most_overdue": resolve_top(student_stats, "overdue")
    }

    try:
        return jsonify(
            ok=True,
            user={
                "name": current_user.name if current_user else "Anonymous",
                "email": current_user.email if current_user else "",
                "slug": current_user.kiosk_slug if current_user else None,
                "urls": public_urls
            },
            total_sessions=query_session.count(),
            active_sessions_count=query_open.count(),
            roster_count=query_roster.count(),
            memory_roster_count=len(get_memory_roster(user_id)),
            settings=get_settings(user_id),
            queue_list=[{
                "name": get_student_name(q.student_id, "Unknown", user_id=user_id),
                "student_id": q.student_id
            } for q in Queue.query.filter_by(user_id=user_id).order_by(Queue.joined_ts.asc()).all()],
            insights=insights,
            active_sessions=[{
                "id": s.id,
                "student_id": s.student_id,
                "name": get_student_name(s.student_id, "Unknown", user_id=user_id),
                "start_ts": s.start_ts.isoformat(),
                "room": s.room
            } for s in query_open.all()]
        )
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify(ok=False, error=str(e)), 500


@admin_bp.route('/api/admin/end_session', methods=['POST'])
@require_admin_auth_api
def api_end_session():
    """Manually end a specific session"""
    from app import db, Session as SessionModel, Queue, get_settings, get_student_name, now_utc, handle_db_errors
    
    user_id = get_current_user_id()
    payload = request.get_json(silent=True) or {}
    session_id = payload.get('session_id')
    
    if not session_id:
        return jsonify(ok=False, message="Missing session ID"), 400
        
    sess = SessionModel.query.filter_by(id=session_id, user_id=user_id).first()
    if not sess:
        return jsonify(ok=False, message="Session not found"), 404
        
    if sess.end_ts:
        return jsonify(ok=False, message="Session already ended"), 400
        
    sess.end_ts = now_utc()
    sess.ended_by = "admin_override"
    
    # Check for auto-promote
    settings = get_settings(user_id)
    promoted_msg = ""
    if settings.get("enable_queue") and settings.get("auto_promote_queue"):
        next_in_line = Queue.query.filter_by(user_id=user_id).order_by(Queue.joined_ts.asc()).first()
        if next_in_line:
            next_code = next_in_line.student_id
            
            promoted_sess = SessionModel(student_id=next_code, start_ts=now_utc(), room=settings["room_name"], user_id=user_id, ended_by="auto")
            db.session.add(promoted_sess)
            db.session.delete(next_in_line)
            
            next_name = get_student_name(next_code, "Student", user_id=user_id)
            promoted_msg = f". Auto-started {next_name} from waitlist."

    db.session.commit()
    
    return jsonify(ok=True, message=f"Ended session for {get_student_name(sess.student_id, 'Student', user_id=user_id)}{promoted_msg}")


@admin_bp.route('/api/settings/update', methods=['POST'])
@require_admin_auth_api
def update_settings_api():
    """Update user settings"""
    from app import db, Settings, get_settings
    
    user_id = get_current_user_id()
    if not user_id:
        return jsonify(ok=False, message="User not authenticated"), 403
    
    data = request.get_json(silent=True) or {}
    
    # Get or create the user's settings
    s = Settings.query.filter_by(user_id=user_id).first()
    if not s:
        s = Settings(
            user_id=user_id,
            room_name="Hall Pass",
            capacity=1,
            overdue_minutes=10,
            kiosk_suspended=False,
            auto_ban_overdue=False
        )
        db.session.add(s)
    
    if "room_name" in data:
        s.room_name = str(data["room_name"]).strip() or s.room_name
    if "capacity" in data:
        try:
            s.capacity = max(1, int(data["capacity"]))
        except Exception:
            pass
    if "overdue_minutes" in data:
        try:
            s.overdue_minutes = max(1, int(data["overdue_minutes"]))
        except Exception:
            pass
    if "kiosk_suspended" in data:
        s.kiosk_suspended = bool(data["kiosk_suspended"])
    if "auto_ban_overdue" in data:
        s.auto_ban_overdue = bool(data["auto_ban_overdue"])
    if "auto_promote_queue" in data:
        s.auto_promote_queue = bool(data["auto_promote_queue"])
    if "enable_queue" in data:
        s.enable_queue = bool(data["enable_queue"])
    
    db.session.commit()
    return jsonify(ok=True, settings=get_settings(user_id))


@admin_bp.route('/api/settings/suspend', methods=['POST'])
def api_suspend_kiosk():
    """Suspend or resume kiosk"""
    from app import db, Settings, is_admin_authenticated
    
    if not is_admin_authenticated():
        return jsonify(ok=False, error="Unauthorized"), 401
        
    data = request.get_json()
    should_suspend = data.get('suspend')
    
    user_id = get_current_user_id()
    settings = Settings.query.filter_by(user_id=user_id).first()
    if settings:
        settings.kiosk_suspended = bool(should_suspend)
        db.session.commit()
        return jsonify(ok=True, suspended=settings.kiosk_suspended)
    return jsonify(ok=False, error="Settings not found"), 404


@admin_bp.route('/api/settings/slug', methods=['POST'])
def api_update_slug():
    """Update kiosk slug (custom URL)"""
    from app import db, User, is_admin_authenticated
    
    if not is_admin_authenticated():
        return jsonify(ok=False, error="Unauthorized"), 401

    user_id = get_current_user_id()
    if not user_id:
        return jsonify(ok=False, error="Not logged in"), 400
        
    current_user = User.query.get(user_id)
    slug = request.get_json().get('slug', '').strip()
    
    if current_user.set_kiosk_slug(slug):
        try:
            db.session.commit()
            return jsonify(ok=True, slug=current_user.kiosk_slug)
        except Exception:
            db.session.rollback()
            return jsonify(ok=False, error="Slug already taken"), 409
    
    return jsonify(ok=False, error="Invalid format"), 400


@admin_bp.route('/api/roster/export')
def api_roster_export():
    """Export current roster to CSV"""
    from app import is_admin_authenticated, cipher_suite, StudentName, roster_service
    
    if not is_admin_authenticated():
        return jsonify(ok=False, error="Unauthorized"), 401
    
    user_id = get_current_user_id()
    roster = roster_service.get_all_students(user_id) if roster_service else []
    
    out = io.StringIO()
    w = csv.writer(out)
    w.writerow(["student_id", "name"])
    
    for s in roster:
        student_id = "UNKNOWN"
        try:
            student_id = cipher_suite.decrypt(s.encrypted_id.encode()).decode()
        except Exception:
            pass
        w.writerow([student_id, s.display_name])
        
    out.seek(0)
    return send_file(
        io.BytesIO(out.getvalue().encode("utf-8")),
        mimetype="text/csv",
        as_attachment=True,
        download_name="roster_export.csv",
    )


@admin_bp.route('/api/roster/template')
def api_roster_template():
    """Download CSV template for roster upload"""
    from app import is_admin_authenticated
    
    if not is_admin_authenticated():
        return jsonify(ok=False, error="Unauthorized"), 401
        
    out = io.StringIO()
    w = csv.writer(out)
    w.writerow(["student_id", "name"])
    w.writerow(["123456", "Jane Doe"])
    w.writerow(["789012", "John Smith"])
    
    out.seek(0)
    return send_file(
        io.BytesIO(out.getvalue().encode("utf-8")),
        mimetype="text/csv",
        as_attachment=True,
        download_name="roster_template.csv",
    )


@admin_bp.route('/api/roster/upload', methods=['POST'])
def api_roster_upload():
    """Upload roster CSV file"""
    from app import (db, is_admin_authenticated, StudentName, cipher_suite, 
                     refresh_roster_cache)
    import hashlib
    
    if not is_admin_authenticated():
        return jsonify(ok=False, error="Unauthorized"), 401
    
    if 'file' not in request.files:
        return jsonify(ok=False, error="No file provided"), 400
        
    file = request.files['file']
    if not file.filename.endswith('.csv'):
        return jsonify(ok=False, error="CSV required"), 400
        
    user_id = get_current_user_id()
    
    try:
        # Replace existing roster
        StudentName.query.filter_by(user_id=user_id).delete()
        
        stream = io.StringIO(file.stream.read().decode("UTF8"), newline=None)
        reader = csv.reader(stream)
        
        count = 0
        for row in reader:
            if not row: continue
            
            col0 = row[0].strip() if len(row) > 0 else ""
            col1 = row[1].strip() if len(row) > 1 else ""
            
            # Auto-detect format (ID, Name) or (Name, ID)
            name = None
            student_id = None
            
            if col0 and all(c.isdigit() for c in col0) and not (col1 and all(c.isdigit() for c in col1)):
                student_id = col0
                name = col1
            elif col1 and all(c.isdigit() for c in col1) and not (col0 and all(c.isdigit() for c in col0)):
                name = col0
                student_id = col1
            else:
                name = col0
                student_id = col1
            
            if not name:
                continue
            
            hash_source = student_id if student_id else f"row_{count}"
            name_hash = hashlib.sha256(f"student_{user_id}_{hash_source}".encode()).hexdigest()[:16]
            
            encrypted_id = None
            if student_id:
                encrypted_id = cipher_suite.encrypt(student_id.encode()).decode()
            
            s = StudentName(
                display_name=name,
                name_hash=name_hash,
                encrypted_id=encrypted_id,
                user_id=user_id,
                banned=False
            )
            db.session.add(s)
            count += 1
            
        db.session.commit()
        refresh_roster_cache(user_id)
        return jsonify(ok=True, count=count)
        
    except Exception as e:
        db.session.rollback()
        return jsonify(ok=False, error=str(e)), 500


@admin_bp.route('/api/roster', methods=['GET'])
def api_roster_get():
    """Get roster list"""
    from app import is_admin_authenticated, StudentName, cipher_suite
    from datetime import datetime, timezone
    
    if not is_admin_authenticated():
        return jsonify(ok=False, error="Unauthorized"), 401
    
    user_id = get_current_user_id()
    try:
        students = StudentName.query.filter_by(user_id=user_id).order_by(StudentName.display_name).limit(500).all()
        
        roster = []
        for s in students:
            readable_id = "Hidden"
            if s.encrypted_id:
                try:
                    readable_id = cipher_suite.decrypt(s.encrypted_id.encode()).decode()
                except:
                    readable_id = "Error"
            
            # Calculate ban duration
            ban_days = None
            if s.banned and s.banned_since:
                delta = datetime.now(timezone.utc) - s.banned_since
                ban_days = delta.days
            
            roster.append({
                "id": s.id,
                "name": s.display_name,
                "student_id": readable_id,
                "banned": s.banned,
                "name_hash": s.name_hash,
                "ban_days": ban_days  # Number of days banned (null if not banned or no timestamp)
            })
            
        return jsonify(ok=True, roster=roster)
    except Exception as e:
        return jsonify(ok=False, error=str(e)), 500


@admin_bp.route('/api/roster/ban', methods=['POST'])
def api_roster_ban():
    """Ban or unban a student"""
    from app import db, is_admin_authenticated, StudentName
    from datetime import datetime, timezone
    
    if not is_admin_authenticated():
        return jsonify(ok=False, error="Unauthorized"), 401
        
    data = request.get_json()
    hash_key = data.get('name_hash')
    should_ban = data.get('banned')
    
    if not hash_key or should_ban is None:
        return jsonify(ok=False, error="Missing parameters"), 400
        
    user_id = get_current_user_id()
    try:
        student = StudentName.query.filter_by(user_id=user_id, name_hash=hash_key).first()
        if student:
            student.banned = bool(should_ban)
            # Set banned_since timestamp when banning, clear when unbanning
            if bool(should_ban):
                student.banned_since = datetime.now(timezone.utc)
            else:
                student.banned_since = None
            db.session.commit()
            return jsonify(ok=True)
        else:
            return jsonify(ok=False, error="Student not found"), 404
    except Exception as e:
        db.session.rollback()
        return jsonify(ok=False, error=str(e)), 500


@admin_bp.route('/api/roster/clear', methods=['POST'])
def api_roster_clear():
    """Clear roster and optionally session history"""
    from app import db, is_admin_authenticated, StudentName, Session as SessionModel, refresh_roster_cache
    
    if not is_admin_authenticated():
        return jsonify(ok=False, error="Unauthorized"), 401
        
    user_id = get_current_user_id()
    data = request.get_json() or {}
    clear_history = data.get('clear_history', False)
    
    try:
        StudentName.query.filter_by(user_id=user_id).delete()
        if clear_history:
            SessionModel.query.filter_by(user_id=user_id).delete()
            
        db.session.commit()
        refresh_roster_cache(user_id)
        return jsonify(ok=True)
    except Exception as e:
        db.session.rollback()
        return jsonify(ok=False, error=str(e)), 500


@admin_bp.route('/api/admin/logs', methods=['GET'])
def api_admin_logs():
    """Get pass logs with pagination"""
    from app import is_admin_authenticated, Session as SessionModel, get_student_name, get_settings, to_local
    
    if not is_admin_authenticated():
        return jsonify(ok=False, error="Unauthorized"), 401
        
    user_id = get_current_user_id()
    try:
        limit = int(request.args.get('limit', 100))
        offset = int(request.args.get('offset', 0))
        
        sessions = SessionModel.query.filter_by(user_id=user_id).order_by(
            SessionModel.start_ts.desc()
        ).limit(limit).offset(offset).all()
        
        settings = get_settings(user_id)
        overdue_seconds = settings["overdue_minutes"] * 60
        
        logs = []
        for s in sessions:
            name = get_student_name(s.student_id, "Unknown", user_id=user_id)
            status = "active"
            if s.end_ts:
                status = "completed"
                if s.duration_seconds > overdue_seconds:
                    status = "overdue"
            
            logs.append({
                "id": s.id,
                "name": name,  # Changed back from "student_name" to "name"
                "student_id": s.student_id,
                "start": to_local(s.start_ts).isoformat(),  # Changed back from "start_ts" to "start"
                "end": to_local(s.end_ts).isoformat() if s.end_ts else None,  # Changed back from "end_ts" to "end"
                "duration_minutes": round(s.duration_seconds / 60, 1),
                "status": status,
                "room": s.room
            })
            
        total_count = SessionModel.query.filter_by(user_id=user_id).count()
        return jsonify(ok=True, logs=logs, total=total_count)
    except Exception as e:
        return jsonify(ok=False, error=str(e)), 500


@admin_bp.route('/api/admin/logs/export', methods=['GET'])
def api_admin_logs_export():
    """Export logs to CSV"""
    from app import is_admin_authenticated, Session as SessionModel, get_student_name, get_settings, to_local
    
    if not is_admin_authenticated():
        return "Unauthorized", 401
    
    user_id = get_current_user_id()
    try:
        sessions = SessionModel.query.filter_by(user_id=user_id).order_by(SessionModel.start_ts.desc()).limit(1000).all()
        
        si = io.StringIO()
        cw = csv.writer(si)
        cw.writerow(["Student Name", "Student ID", "Room", "Start Time", "End Time", "Duration (Minutes)", "Status"])
        
        for s in sessions:
            name = get_student_name(s.student_id, "Unknown", user_id=user_id)
            status = "active"
            if s.end_ts:
                status = "completed"
                if s.duration_seconds > get_settings(user_id)["overdue_minutes"] * 60:
                    status = "overdue"
            
            cw.writerow([
                name,
                s.student_id,
                s.room,
                to_local(s.start_ts).isoformat(),
                to_local(s.end_ts).isoformat() if s.end_ts else "",
                round(s.duration_seconds / 60, 1),
                status
            ])
            
        output = io.BytesIO()
        output.write(si.getvalue().encode('utf-8'))
        output.seek(0)
        
        return send_file(
            output,
            mimetype="text/csv",
            as_attachment=True,
            download_name="pass_logs.csv"
        )
    except Exception as e:
        return str(e), 500


@admin_bp.route('/api/control/ban_overdue', methods=['POST'])
def api_ban_overdue():
    """Ban all students with active overdue sessions"""
    from app import db, is_admin_authenticated, Session as SessionModel, StudentName, get_settings
    import hashlib
    
    if not is_admin_authenticated():
        return jsonify(ok=False, error="Unauthorized"), 401
        
    user_id = get_current_user_id()
    settings = get_settings(user_id)
    overdue_seconds = settings["overdue_minutes"] * 60
    
    try:
        open_sessions = SessionModel.query.filter_by(user_id=user_id, end_ts=None).all()
        count = 0
        for s in open_sessions:
            if s.duration_seconds > overdue_seconds:
                name_hash = hashlib.sha256(f"student_{user_id}_{s.student_id}".encode()).hexdigest()[:16]
                student_name = StudentName.query.filter_by(user_id=user_id, name_hash=name_hash).first()
                if student_name and not student_name.banned:
                    student_name.banned = True
                    count += 1
        db.session.commit()
        return jsonify(ok=True, count=count)
    except Exception as e:
        db.session.rollback()
        return jsonify(ok=False, error=str(e)), 500


@admin_bp.route('/api/control/delete_history', methods=['POST'])
def api_delete_history():
    """Delete all session history for user"""
    from app import db, is_admin_authenticated, Session as SessionModel
    
    if not is_admin_authenticated():
        return jsonify(ok=False, error="Unauthorized"), 401
        
    user_id = get_current_user_id()
    try:
        SessionModel.query.filter_by(user_id=user_id).delete()
        db.session.commit()
        return jsonify(ok=True)
    except Exception as e:
        return jsonify(ok=False, error=str(e)), 500


# ============================================================================
# ALL 14 ADMIN ROUTES MIGRATED! ✅
# ============================================================================
# Next: Register blueprint in app.py and test
# See PLANNING.md for testing checklist

"""
Kiosk Routes Blueprint - Scan, Status, Queue Management

Migrated from app.py as part of P4 backend modularization.
Contains all kiosk-related endpoints for student scanning and queue management.
"""
from flask import Blueprint, jsonify, request, Response, stream_with_context
from datetime import datetime, timezone, timedelta
from typing import Dict, Optional, Any
import json
import time

# Create blueprint
kiosk_bp = Blueprint('kiosk', __name__)


# ============================================================================
# HELPER FUNCTIONS (migrated from app.py)
# ============================================================================

def _build_status_payload(user_id: Optional[int]) -> Dict[str, Any]:
    """
    Single source of truth for Kiosk/Display status payload.
    Keep this aligned with the Flutter `KioskStatus` model.
    """
    from app import (get_settings, get_current_holder, get_student_name, 
                     get_open_sessions, to_local, Queue, is_schedule_available,
                     db, Session, now_utc)
    
    settings = get_settings(user_id)

    # Check schedule availability (already checks manual override)
    available, _ = is_schedule_available(user_id, settings)
    kiosk_suspended = not available
    
    overdue_minutes = settings["overdue_minutes"]
    auto_ban_overdue = settings.get("auto_ban_overdue", False)
    auto_promote_queue = settings.get("auto_promote_queue", False)
    
    # AUTO-PROMOTE FROM QUEUE on schedule resume
    # When kiosk becomes available and there's room, promote queued students
    if available and settings.get("enable_queue") and auto_promote_queue:
        open_sessions = get_open_sessions(user_id)
        slots_available = settings["capacity"] - len(open_sessions)
        
        # Promote students while there are slots and queue entries
        while slots_available > 0:
            next_in_line = Queue.query.filter_by(user_id=user_id).order_by(Queue.joined_ts.asc()).first()
            if not next_in_line:
                break
            
            # Create new session for queued student
            promoted_sess = Session(
                student_id=next_in_line.student_id,
                start_ts=now_utc(),
                room=settings["room_name"],
                user_id=user_id,
                ended_by="auto_promote"
            )
            db.session.add(promoted_sess)
            db.session.delete(next_in_line)
            db.session.commit()
            
            slots_available -= 1

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
        "queue_list": payload.get("queue_list") or [],
    }


def _sse_status_stream(token: Optional[str]):
    """SSE stream generator for real-time status updates"""
    from app import db, get_current_user_id
    
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


# ============================================================================
# KIOSK API ROUTES
# ============================================================================

@kiosk_bp.post("/api/scan")
def api_scan():
    """Main scan endpoint - handles student check-in/check-out"""
    from app import (db, Student, Session, Queue, get_current_user_id, get_settings,
                     get_student_name, get_memory_roster, is_student_banned, 
                     set_student_banned, get_open_sessions, now_utc, is_schedule_available)
    
    payload = request.get_json(silent=True) or {}
    token = payload.get("token")
    user_id = get_current_user_id(token)

    code = (payload.get("code") or "").strip()
    if not code:
        return jsonify(ok=False, message="No code scanned"), 400

    # Look up returning students first (allow return even if suspended)
    open_sessions = get_open_sessions(user_id)
    is_returning = False
    
    # Check if this student currently holds a pass
    for s in open_sessions:
        if s.student_id == code:
             is_returning = True
             break
    
    # If NEW pass (not returning), apply suspension/schedule rules
    if not is_returning:
        # Check if kiosk is available (manual suspend + schedule)
        settings = get_settings(user_id)
        available, reason = is_schedule_available(user_id, settings)
        
        if not available:
            # Allow queue while suspended if enabled
            if settings.get('allow_queue_while_suspended') and settings.get('enable_queue'):
                # Will handle queue join below, but block immediate pass
                pass
            else:
                if reason == "Manually suspended":
                    return jsonify(ok=False, message="Kiosk is currently suspended by administrator"), 403
                else:
                    return jsonify(ok=False, message=f"Passes not available: {reason}"), 403

    # Look up student name from encrypted database
    student_name = get_student_name(code, user_id=user_id)
    
    if student_name == "Student":  # Default fallback means student not found
        # Check if roster is actually empty
        if len(get_memory_roster(user_id)) == 0:
            return jsonify(ok=False, message="Roster empty. Please upload student list."), 404
        else:
            return jsonify(ok=False, message=f"Incorrect ID: {code}"), 404
    
    # Ensure minimal Student record exists
    if not Student.query.get(code):
        anonymous_student = Student(id=code, name=f"Anonymous_{code}", user_id=user_id)
        db.session.add(anonymous_student)
        db.session.commit()
    
    # Reload settings for subsequent logic (capacity checks etc)
    if is_returning:
        settings = get_settings(user_id)

    # ... logic continues (return check is repeated but that's fine/safe)

    # If this student currently holds the pass, end their session
    for s in open_sessions:
        if s.student_id == code:
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
            
            # AUTO-PROMOTE LOGIC
            next_student_name = None
            if settings.get("enable_queue") and settings.get("auto_promote_queue"):
                # Check for next student
                next_in_line = Queue.query.filter_by(user_id=user_id).order_by(Queue.joined_ts.asc()).first()
                if next_in_line:
                    # Promote them!
                    next_code = next_in_line.student_id
                    
                    promoted_sess = Session(student_id=next_code, start_ts=now_utc(), room=settings["room_name"], user_id=user_id, ended_by="auto")
                    db.session.add(promoted_sess)
                    db.session.delete(next_in_line)
                    db.session.commit()
                    
                    next_student_name = get_student_name(next_code, "Student", user_id=user_id)
                    action = "ended_auto_started"
            
            return jsonify(ok=True, action=action, message=msg, name=student_name, next_student=next_student_name)
    
    # Check if student is banned from starting NEW restroom trips
    if is_student_banned(code, user_id=user_id):
        return jsonify(ok=False, action="banned", message="RESTROOM PRIVILEGES SUSPENDED - SEE TEACHER", name=student_name), 403

    # QUEUE SELF-REMOVAL LOGIC (NEW FEATURE)
    # Allow students to remove themselves from queue by scanning again
    existing_queue_entry = Queue.query.filter_by(user_id=user_id, student_id=code).first()
    if existing_queue_entry:
        db.session.delete(existing_queue_entry)
        db.session.commit()
        return jsonify(ok=True, action="left_queue", message="Removed from waitlist", name=student_name)

    # QUEUE LOCK LOGIC
    queue_count = Queue.query.filter_by(user_id=user_id).count()
    if queue_count > 0:
        top_spot = Queue.query.filter_by(user_id=user_id).order_by(Queue.joined_ts.asc()).first()
        if top_spot.student_id != code:
             # Scanner is NOT the top spot - new student trying to join
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


    # CAPACITY CHECK & START
    if len(open_sessions) >= settings["capacity"] or (not available):
         # Queue Prompt / Auto-Join
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
    Queue.query.filter_by(user_id=user_id, student_id=code).delete()
    
    sess = Session(student_id=code, start_ts=now_utc(), room=settings["room_name"], user_id=user_id)
    db.session.add(sess)
    db.session.commit()
    return jsonify(ok=True, action="started", name=student_name)


@kiosk_bp.get("/api/status")
def api_status():
    """Get current kiosk status"""
    from app import get_current_user_id
    
    token = request.args.get('token')
    user_id = get_current_user_id(token)
    return jsonify(_build_status_payload(user_id))


@kiosk_bp.get("/api/stream")
def api_stream():
    """SSE stream for real-time status updates"""
    token = request.args.get("token")
    return _sse_status_stream(token)


@kiosk_bp.get("/events")
def sse_events():
    """Backwards-compatible alias for SSE stream"""
    token = request.args.get("token")
    return _sse_status_stream(token)


# ============================================================================
# QUEUE MANAGEMENT ROUTES
# ============================================================================

@kiosk_bp.route("/api/queue/join", methods=["POST"])
def api_queue_join():
    """Student joins queue"""
    from app import db, Queue, get_current_user_id
    
    payload = request.get_json(silent=True) or {}
    token = payload.get("token")
    code = payload.get("code")
    user_id = get_current_user_id(token)
    
    if not code: 
        return jsonify(ok=False), 400
    
    # Check if already in queue
    if Queue.query.filter_by(user_id=user_id, student_id=code).first():
        return jsonify(ok=True, message="Already in queue")
        
    q = Queue(student_id=code, user_id=user_id)
    db.session.add(q)
    db.session.commit()
    return jsonify(ok=True)


@kiosk_bp.route("/api/queue/leave", methods=["POST"])
def api_queue_leave():
    """Student leaves queue"""
    from app import db, Queue, get_current_user_id
    
    payload = request.get_json(silent=True) or {}
    token = payload.get("token")
    code = payload.get("code")
    user_id = get_current_user_id(token)

    Queue.query.filter_by(user_id=user_id, student_id=code).delete()
    db.session.commit()
    return jsonify(ok=True)


@kiosk_bp.route("/api/queue/delete", methods=["POST"])
def api_queue_delete():
    """Admin removes student from queue"""
    from app import db, Queue, get_current_user_id
    from functools import wraps
    from flask import session
    
    # Require admin auth
    def require_admin_auth_api(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if not (session.get('admin_authenticated', False) or 'user_id' in session):
                return jsonify(ok=False, message="Admin authentication required"), 401
            return f(*args, **kwargs)
        return decorated_function
    
    @require_admin_auth_api
    def _delete():
        payload = request.get_json(silent=True) or {}
        student_id = payload.get("student_id")
        user_id = get_current_user_id()
        
        if not student_id:
            return jsonify(ok=False, error="Missing student_id"), 400

        Queue.query.filter_by(user_id=user_id, student_id=student_id).delete()
        db.session.commit()
        return jsonify(ok=True)
    
    return _delete()


@kiosk_bp.route("/api/queue/reorder", methods=["POST"])
def api_queue_reorder():
    """Admin reorders the queue"""
    from app import db, Queue, get_current_user_id, now_utc
    from functools import wraps
    from flask import session
    
    # Require admin auth
    def require_admin_auth_api(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if not (session.get('admin_authenticated', False) or 'user_id' in session):
                return jsonify(ok=False, message="Admin authentication required"), 401
            return f(*args, **kwargs)
        return decorated_function
    
    @require_admin_auth_api
    def _reorder():
        user_id = get_current_user_id()
        payload = request.get_json(silent=True) or {}
        new_order = payload.get("student_ids", [])
        
        if not new_order:
             return jsonify(ok=False, message="No order provided"), 400

        current_queue = Queue.query.filter_by(user_id=user_id).all()
        queue_map = {q.student_id: q for q in current_queue}
        
        base_time = now_utc()
        
        for i, student_id in enumerate(new_order):
            if student_id in queue_map:
                # Assign timestamps in increasing order
                queue_map[student_id].joined_ts = base_time + timedelta(seconds=i)
                
        db.session.commit()
        return jsonify(ok=True, message="Queue reordered")
    
    return _reorder()

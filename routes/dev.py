"""
Dev Routes Blueprint - System Administration & Monitoring

Migrated from app.py as part of P4 backend modularization.
Contains dev dashboard endpoints for system-wide stats and user management.
"""
from flask import Blueprint, jsonify, request, session
from datetime import datetime, timezone
import os

# Create blueprint
dev_bp = Blueprint('dev', __name__)


# ============================================================================
# DEV AUTHENTICATION
# ============================================================================

@dev_bp.route("/api/dev/auth", methods=["POST"])
def api_dev_auth():
    """Developer passcode login"""
    import config
    
    data = request.get_json()
    passcode = data.get("passcode", "").strip()
    
    if passcode == config.ADMIN_PASSCODE:
        session['dev_authenticated'] = True
        session.permanent = True
        return jsonify(ok=True)
    return jsonify(ok=False, error="Invalid Passcode"), 401


# ============================================================================
# DEV STATS ROUTES
# ============================================================================

@dev_bp.route("/api/dev/stats")
def api_dev_stats():
    """Basic system stats (requires dev authentication)"""
    from app import Session, StudentName, User, get_settings
    
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


@dev_bp.route("/api/dev/expanded_stats", methods=["POST"])
def api_dev_expanded_stats():
    """
    Advanced dev stats with teacher activity and recent logs.
    Authenticated via dev passcode (can be inline or session-based).
    """
    import config
    from app import Session, Student, User
    
    # Check session auth OR inline passcode
    if not session.get('dev_authenticated'):
        data = request.get_json(silent=True) or {}
        passcode = data.get('passcode')
        
        if passcode != os.environ.get("DEV_PASSCODE") and passcode != config.ADMIN_PASSCODE:
            return jsonify(ok=False, error="Unauthorized"), 401
        
    # --- Global Stats ---
    total_sessions = Session.query.count()
    active_sessions = Session.query.filter(Session.end_ts == None).count()
    total_students = Student.query.count()
    total_users = User.query.count()
    
    # --- Active Teachers List ---
    teachers_data = []
    users = User.query.all()
    
    for u in users:
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
    
    # --- Recent System Activity (FERPA-compliant: ANONYMIZED) ---
    recent_sess = Session.query.order_by(Session.start_ts.desc()).limit(20).all()
    activity_log = []
    
    for s in recent_sess:
        teacher_email = s.user.email if s.user else "Unknown"
        # ANONYMIZE STUDENT DATA - do NOT show student names or IDs
        
        action = "Active Pass"
        if s.end_ts:
            action = "Returned Pass"
            
        activity_log.append({
            "timestamp": s.start_ts.isoformat(),
            "teacher": teacher_email,
            "action": f"{action} ({s.room or 'Unknown Room'})",
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

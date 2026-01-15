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


# ============================================================================
# FERPA COMPLIANCE MIGRATIONS
# ============================================================================

@dev_bp.route("/api/dev/fix_encrypted_ids", methods=["POST"])
def api_fix_encrypted_ids():
    """
    FERPA Compliance Migration: Fix NULL encrypted_id records.
    
    This endpoint finds all StudentName records with NULL encrypted_id
    and generates placeholder IDs for them to ensure FERPA compliance.
    
    Security: Requires dev authentication.
    """
    import config
    from app import db, StudentName, cipher_suite
    
    # Check session auth OR inline passcode
    if not session.get('dev_authenticated'):
        data = request.get_json(silent=True) or {}
        passcode = data.get('passcode')
        
        if passcode != os.environ.get("DEV_PASSCODE") and passcode != config.ADMIN_PASSCODE:
            return jsonify(ok=False, error="Unauthorized"), 401
    
    try:
        # Find all records with NULL encrypted_id
        null_records = StudentName.query.filter(StudentName.encrypted_id == None).all()
        
        if not null_records:
            return jsonify(
                ok=True,
                message="No records require migration",
                fixed_count=0,
                already_compliant=True
            )
        
        # Group by user_id to generate sequential IDs per user
        records_by_user = {}
        for record in null_records:
            user_id = record.user_id
            if user_id not in records_by_user:
                records_by_user[user_id] = []
            records_by_user[user_id].append(record)
        
        fixed_count = 0
        fixed_details = []
        
        for user_id, records in records_by_user.items():
            for idx, record in enumerate(records, start=1):
                # Generate placeholder ID
                placeholder_id = f"MIGRATED_{user_id or 'LEGACY'}_{idx:06d}"
                
                # Encrypt and update
                record.encrypted_id = cipher_suite.encrypt(placeholder_id.encode()).decode()
                fixed_count += 1
                
                # Log first 10 per user for verification
                if idx <= 10:
                    fixed_details.append({
                        "user_id": user_id,
                        "name": record.display_name,
                        "generated_id": placeholder_id
                    })
        
        db.session.commit()
        
        return jsonify(
            ok=True,
            message=f"Successfully migrated {fixed_count} records to FERPA compliance",
            fixed_count=fixed_count,
            users_affected=len(records_by_user),
            sample_fixes=fixed_details[:20]  # Limit response size
        )
        
    except Exception as e:
        db.session.rollback()
        return jsonify(ok=False, error=str(e)), 500


@dev_bp.route("/api/dev/audit_encrypted_ids", methods=["GET"])
def api_audit_encrypted_ids():
    """
    Audit endpoint to check FERPA compliance status.
    
    Returns count of records with and without encrypted_id.
    """
    import config
    from app import StudentName
    
    # Check session auth OR query param passcode
    if not session.get('dev_authenticated'):
        passcode = request.args.get('passcode')
        
        if passcode != os.environ.get("DEV_PASSCODE") and passcode != config.ADMIN_PASSCODE:
            return jsonify(ok=False, error="Unauthorized"), 401
    
    try:
        total_records = StudentName.query.count()
        null_count = StudentName.query.filter(StudentName.encrypted_id == None).count()
        compliant_count = total_records - null_count
        
        compliance_status = "COMPLIANT" if null_count == 0 else "NON-COMPLIANT"
        
        return jsonify(
            ok=True,
            compliance_status=compliance_status,
            total_students=total_records,
            encrypted_count=compliant_count,
            null_encrypted_id_count=null_count,
            compliance_percentage=round((compliant_count / total_records * 100), 2) if total_records > 0 else 100
        )
        
    except Exception as e:
        return jsonify(ok=False, error=str(e)), 500

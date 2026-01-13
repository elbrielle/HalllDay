"""
Ban Service: Handles student ban management
Refactored for 2.0 multi-tenancy with stateless user_id scoping
"""
from typing import Dict, List, Any, Optional


class BanService:
    def __init__(self, db, student_name_model, roster_service):
        """
        Initialize BanService.
        """
        self.db = db
        self.StudentName = student_name_model
        self.roster_service = roster_service
    
    def is_student_banned(self, user_id: Optional[int], student_id: str) -> bool:
        """Check if a student is banned from using the restroom"""
        try:
            name_hash = self.roster_service._hash_student_id(student_id, user_id)
            
            # Build query with optional user_id scoping
            query = self.StudentName.query.filter_by(name_hash=name_hash)
            if user_id is not None:
                query = query.filter_by(user_id=user_id)
            
            student_name = query.first()
            return student_name.banned if student_name else False
        except Exception:
            return False
    
    def set_student_banned(self, user_id: Optional[int], student_id: str, banned_status: bool) -> bool:
        """Ban or unban a student from using the restroom"""
        try:
            # TEMPORARILY DISABLED - needs proper migration
            # from datetime import datetime, timezone
            name_hash = self.roster_service._hash_student_id(student_id, user_id)
            
            # Build query with optional user_id scoping
            query = self.StudentName.query.filter_by(name_hash=name_hash)
            if user_id is not None:
                query = query.filter_by(user_id=user_id)
            
            student_name = query.first()
            if student_name:
                student_name.banned = banned_status
                # TEMPORARILY DISABLED - needs proper migration
                # if banned_status:
                #     student_name.banned_since = datetime.now(timezone.utc)
                # else:
                #     student_name.banned_since = None
                self.db.session.commit()
                return True
            return False
        except Exception:
            try:
                self.db.session.rollback()
            except Exception:
                pass
            return False
    
    def get_overdue_students(self, user_id: Optional[int], open_sessions: list, overdue_minutes: int) -> List[Dict[str, Any]]:
        """Get list of students who are currently overdue"""
        try:
            overdue_seconds = overdue_minutes * 60
            overdue_list = []
            
            for session_obj in open_sessions:
                # Filter by user_id if set
                if user_id is not None and hasattr(session_obj, 'user_id'):
                    if session_obj.user_id != user_id:
                        continue
                
                if session_obj.duration_seconds > overdue_seconds:
                    # Pass user_id to roster service
                    student_name = self.roster_service.get_student_name(
                        user_id, session_obj.student_id, "Student"
                    )
                    is_banned = self.is_student_banned(user_id, session_obj.student_id)
                    
                    overdue_list.append({
                        'student_id': session_obj.student_id,
                        'name': student_name,
                        'duration_seconds': session_obj.duration_seconds,
                        'duration_minutes': round(session_obj.duration_seconds / 60, 1),
                        'start_ts': session_obj.start_ts.isoformat(),
                        'banned': is_banned,
                        'session_id': session_obj.id
                    })
            
            return overdue_list
        except Exception:
            return []
    
    def auto_ban_overdue_students(self, user_id: Optional[int], open_sessions: list, overdue_minutes: int) -> Dict[str, Any]:
        """Automatically ban students who are currently overdue"""
        try:
            overdue_list = self.get_overdue_students(user_id, open_sessions, overdue_minutes)
            banned_count = 0
            banned_students = []
            
            for student in overdue_list:
                if not student['banned']:
                    success = self.set_student_banned(user_id, student['student_id'], True)
                    if success:
                        banned_count += 1
                        banned_students.append(student['name'])
            
            return {'count': banned_count, 'students': banned_students}
        except Exception:
            return {'count': 0, 'students': []}


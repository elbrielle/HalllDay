"""
Session Service: Handles hallpass session management
Refactored for 2.0 multi-tenancy with stateless user_id scoping
"""
from typing import Optional, List
from datetime import datetime, timezone


class SessionService:
    def __init__(self, db, session_model):
        """
        Initialize SessionService.
        
        Args:
            db: SQLAlchemy database instance
            session_model: Session model class
        """
        self.db = db
        self.Session = session_model
    
    def get_open_sessions(self, user_id: Optional[int]) -> List:
        """Get all currently open sessions (scoped to user if set)"""
        try:
            query = self.Session.query.filter_by(end_ts=None)
            if user_id is not None:
                query = query.filter_by(user_id=user_id)
            return query.order_by(self.Session.start_ts.asc()).all()
        except Exception:
            self.db.session.rollback()
            try:
                query = self.Session.query.filter_by(end_ts=None)
                if user_id is not None:
                    query = query.filter_by(user_id=user_id)
                return query.order_by(self.Session.start_ts.asc()).all()
            except Exception:
                return []
    
    def get_current_holder(self, user_id: Optional[int]):
        """Get the first student currently holding the pass"""
        open_sessions = self.get_open_sessions(user_id)
        return open_sessions[0] if open_sessions else None
    
    def get_sessions_in_range(self, user_id: Optional[int], start_utc: datetime, end_utc: datetime) -> List:
        """Get sessions within a date range (scoped to user if set)"""
        try:
            query = self.Session.query.filter(
                self.Session.start_ts >= start_utc,
                self.Session.start_ts <= end_utc
            )
            if user_id is not None:
                query = query.filter_by(user_id=user_id)
            return query.order_by(self.Session.start_ts.asc()).all()
        except Exception:
            return []
    
    def get_session_count(self, user_id: Optional[int]) -> int:
        """Get total session count (scoped to user if set)"""
        try:
            query = self.Session.query
            if user_id is not None:
                query = query.filter_by(user_id=user_id)
            return query.count()
        except Exception:
            return 0
    
    def clear_user_history(self, user_id: Optional[int]) -> bool:
        """Clear session history for a specific user"""
        try:
            if user_id is not None:
                self.Session.query.filter_by(user_id=user_id).delete()
            else:
                self.Session.query.delete()
            self.db.session.commit()
            return True
        except Exception:
            self.db.session.rollback()
            return False


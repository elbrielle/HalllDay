"""
Roster Service: Handles student roster management
Refactored for 2.0 multi-tenancy with stateless user_id scoping
"""
from typing import Dict, Optional, Any
import hashlib


class RosterService:
    def __init__(self, db, cipher_suite, student_name_model):
        """
        Initialize RosterService.
        
        Args:
            db: SQLAlchemy database instance
            cipher_suite: Fernet cipher for encryption
            student_name_model: StudentName model class
        """
        self.db = db
        self.cipher_suite = cipher_suite
        self.StudentName = student_name_model
        # Multi-tenant cache: {user_id: {student_id: name}}
        # None as user_id key is for legacy/global mode
        self._roster_cache: Dict[Optional[int], Dict[str, str]] = {}
    
    def _get_cache_for_user(self, user_id: Optional[int]) -> Dict[str, str]:
        """Get the roster cache for a specific user"""
        if user_id not in self._roster_cache:
            self._roster_cache[user_id] = {}
        return self._roster_cache[user_id]
        
    def _hash_student_id(self, student_id: str, user_id: Optional[int] = None) -> str:
        """
        Create a hash of student ID for FERPA-compliant lookup.
        Includes user_id in hash for multi-tenant isolation (same student ID 
        can exist for different teachers without conflict).
        """
        # Include user_id in hash so same student ID creates different hashes per user
        hash_input = f"student_{user_id}_{student_id}" if user_id else f"student_{student_id}"
        return hashlib.sha256(hash_input.encode()).hexdigest()[:16]
    
    def get_memory_roster(self, user_id: Optional[int]) -> Dict[str, str]:
        """Get student roster from memory cache for specific user"""
        return self._get_cache_for_user(user_id)
    
    def set_memory_roster(self, user_id: Optional[int], roster_dict: Dict[str, str]) -> None:
        """Set student roster in memory cache for specific user"""
        self._roster_cache[user_id] = roster_dict.copy()
    
    def clear_memory_roster(self, user_id: Optional[int]) -> None:
        """Clear student roster from memory cache for specific user"""
        self._roster_cache[user_id] = {}
    
    def store_student_name(self, user_id: Optional[int], student_id: str, name: str) -> None:
        """Store student name in database using hash for lookup and encryption for retrieval"""
        try:
            name_hash = self._hash_student_id(student_id, user_id)
            encrypted_id = self.cipher_suite.encrypt(student_id.encode()).decode()
            
            # Build query with optional user_id scoping
            query = self.StudentName.query.filter_by(name_hash=name_hash)
            if user_id is not None:
                query = query.filter_by(user_id=user_id)
            
            existing = query.first()
            if existing:
                existing.display_name = name
                existing.encrypted_id = encrypted_id
            else:
                student_name = self.StudentName(
                    name_hash=name_hash, 
                    display_name=name, 
                    encrypted_id=encrypted_id,
                    user_id=user_id  # 2.0: Associate with user
                )
                self.db.session.add(student_name)
            self.db.session.commit()
        except Exception:
            try:
                self.db.session.rollback()
            except Exception:
                pass

    def store_student_names_batch(self, user_id: Optional[int], roster: dict) -> int:
        """
        Store multiple student names in database efficiently (single commit).
        Returns the count of successfully stored students.
        Handles legacy data by updating existing records regardless of user_id.
        """
        stored_count = 0
        try:
            for student_id, name in roster.items():
                name_hash = self._hash_student_id(student_id, user_id)
                encrypted_id = self.cipher_suite.encrypt(student_id.encode()).decode()
                
                # First check if any record with this name_hash exists (including legacy)
                existing = self.StudentName.query.filter_by(name_hash=name_hash).first()
                
                if existing:
                    # Update existing record, claim it for this user if needed
                    existing.display_name = name
                    existing.encrypted_id = encrypted_id
                    if user_id is not None:
                        existing.user_id = user_id  # Claim legacy record for this user
                else:
                    # Create new record
                    student_name = self.StudentName(
                        name_hash=name_hash, 
                        display_name=name, 
                        encrypted_id=encrypted_id,
                        user_id=user_id
                    )
                    self.db.session.add(student_name)
                stored_count += 1
            
            # Single commit at the end
            self.db.session.commit()
            return stored_count
            
        except Exception as e:
            try:
                self.db.session.rollback()
            except Exception:
                pass
            raise e  # Re-raise so caller knows it failed
    
    def get_student_name_from_db(self, user_id: Optional[int], student_id: str) -> Optional[str]:
        """Get student name from database using hash lookup"""
        try:
            name_hash = self._hash_student_id(student_id, user_id)
            
            # Build query with optional user_id scoping
            query = self.StudentName.query.filter_by(name_hash=name_hash)
            if user_id is not None:
                query = query.filter_by(user_id=user_id)
            
            student_name = query.first()
            return student_name.display_name if student_name else None
        except Exception:
            return None
    
    def get_student_name(self, user_id: Optional[int], student_id: str, fallback: str = "Student") -> str:
        """Get student name from memory or database"""
        # Try memory roster first (fastest)
        cache = self._get_cache_for_user(user_id)
        name = cache.get(student_id)
        if name:
            return name
        
        # Try database lookup
        name = self.get_student_name_from_db(user_id, student_id)
        if name:
            # Cache it back to memory
            cache[student_id] = name
            return name
        
        return fallback
    
    def clear_all_student_names(self, user_id: Optional[int]) -> bool:
        """Clear all student names from database (scoped to user if set)"""
        try:
            if user_id is not None:
                self.StudentName.query.filter_by(user_id=user_id).delete()
            else:
                self.StudentName.query.delete()
            self.db.session.commit()
            
            # Also clear cache
            self.clear_memory_roster(user_id)
            return True
        except Exception:
            self.db.session.rollback()
            return False
    
    def get_all_students(self, user_id: Optional[int]) -> list:
        """Get all students for the current user (for admin display)"""
        try:
            query = self.StudentName.query
            if user_id is not None:
                query = query.filter_by(user_id=user_id)
            return query.all()
        except Exception:
            return []
    
    def update_anonymous_students(self, user_id: Optional[int], student_model) -> int:
        """
        Update Student.name for any Anonymous_* entries matching the roster.
        Called after roster upload to retroactively fix anonymous entries.
        Returns the count of updated students.
        
        NOTE (v2.0): Scoped to current user if user_id is set.
        """
        updated_count = 0
        try:
            # Build query with optional user_id scoping
            query = student_model.query.filter(
                student_model.name.like('Anonymous_%')
            )
            if user_id is not None:
                query = query.filter_by(user_id=user_id)
            
            anonymous_students = query.all()
            
            for student in anonymous_students:
                # Check if we have a real name in the roster
                real_name = self.get_student_name(user_id, student.id, fallback=None)
                if real_name and real_name != student.name:
                    student.name = real_name
                    updated_count += 1
            
            if updated_count > 0:
                self.db.session.commit()
                
        except Exception:
            try:
                self.db.session.rollback()
            except Exception:
                pass
        
        return updated_count



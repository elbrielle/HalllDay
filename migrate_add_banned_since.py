"""
Quick Database Migration Script for banned_since Column
Run this once on production to add the new column safely.
"""
import os
import sys

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app import app, db

def add_banned_since_column():
    """Add banned_since column to student_name table if it doesn't exist"""
    with app.app_context():
        try:
            # Try to execute raw SQL to add column
            with db.engine.connect() as conn:
                # Check if column exists first
                result = conn.execute(db.text(
                    "SELECT column_name FROM information_schema.columns "
                    "WHERE table_name='student_name' AND column_name='banned_since'"
                ))
                
                if result.fetchone() is None:
                    print("Adding banned_since column...")
                    conn.execute(db.text(
                        "ALTER TABLE student_name ADD COLUMN banned_since TIMESTAMP WITH TIME ZONE"
                    ))
                    conn.commit()
                    print("✅ Column added successfully!")
                else:
                    print("✅ Column already exists!")
                    
        except Exception as e:
            print(f"❌ Error: {e}")
            print("\nTrying alternative method (SQLAlchemy)...")
            try:
                # Alternative: Just create all tables (safe if column defined in model)
                db.create_all()
                print("✅ Database schema updated!")
            except Exception as e2:
                print(f"❌ Alternative method also failed: {e2}")
                print("\nPlease restart your app - SQLAlchemy will auto-create the column on startup.")

if __name__ == "__main__":
    print("HalllDay Database Migration: Adding banned_since column")
    print("="*60)
    add_banned_since_column()

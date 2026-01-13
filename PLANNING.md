# IDK Can You? Development Plan

**Last Updated:** 2025-12-15

---

# 🚨 Current Priorities (Immediate Focus)
[x] Biggest Priority: For some reason the flutter implementation is causing the input to stop registering at times through the day... **FIXED**: Implemented aggressive focus reclamation on app resume and a periodic 2s timer to ensure the hidden input field always has focus on the kiosk screen. 


[x] Admin Charts: Fixed "Most Overdue" and "Top Users" graphs by moving aggregation to Python and ensuring proper name resolution for active/historic sessions.
[x] Active Session Management: added "Live Activity" section to Admin Dashboard with list of active sessions (with End/Ban buttons) and Waitlist (with Remove/Reorder capability). Fixed bugs where section was not visible and added auto-refresh.
[X] Auth page looks kinda ugly Fixed: Took care of with CSS 
[x] Refined/Animated Logo: Fixed transparency (using SVG mask) and added "float" animation. Using `currentColor` for context-aware styling.
[x] Unified Navigation: Implemented `AppNavDrawer` (Hamburger Menu) available on Landing, Admin, and Dev screens. Added "Open Kiosk" and "Open Display" launch buttons to Admin Dash. 
- [] admin page not responsive on mobile 
- [] No "account creation" step. Google Auth seems to work but no account creation step to customize experience and feel like you are establishing a account. If that makes sense. it works...but it just feels so automatic I don't even know if it's a true account Almost makes it feel insecure even if it is secure. If that makes sense. Profile picture, slug option, optional name, etc. I am not sure if this is a good idea and don't want to mess up already made accounts. 
- [] Fleshed out Dev dashboard with ability to see active users (teachers) and details about sessions while not exposing student data (maintain FERPA compliance). See statistics or active passes without being attached to a specific student data so dev can see usage statistics and activity. 
- [ ] Dev Dashboard should not be in menu navigation. That is private. It should only be landing page, kiosk, display, admin to travel between eachother.

## ⚙️ Phase 6: Admin & Dev Tools (Material 3 Port)
*Goal: Unified Material 3 Design for all surfaces.*

- [ ] **Admin Dashboard (`/admin`)**:
    - [x] **Admin Login UI**: Revamped with Material 3 card layout.
    - [x] **Roster Management**: Manual Ban List & View.
    - [x] **Pass Logs**: Ported to Flutter.
    - [x] **Roster Clear**: Implemented backend endpoint and frontend controls for clearing session history and roster data.
    - [ ] **CSV Import/Export**: [PRIORITY] Template instructions (downloadable CSV) and full roster export functionality for Beta readiness.
    - [ ] **Data Tables**: Refine with Material 3 sorting/filtering.
- [ ] **Dev Dashboard (`/dev`)**:
    - [ ] **Port Tools**: Database Maintenance & System Status.
    - [ ] **Security**: PROTECT with PIN/Auth and/or Google Auth to maintain FERPA compliance.
    - [ ] **User Management**: robust ability to manage users/active sessions.

---

# 🔮 Future Roadmap

- [] Dark mode option 


## 📅 Scheduling System

- [ ] Auto-suspend kiosks based on time/timezone.
- [ ] Admin panel for scheduling hours.

---

# ✅ Completed History

### Phase 9 - Real-Time Updates (Polling Strategy)
**Status**: Completed (2025-12-15) - *SSE Attempted & Reverted*
- [x] **Investigation**: Implemented SSE, encountered HTTP/2 protocol errors with Cloudflare/Proxies.
- [x] **Decision**: Reverted to **Polling** (2s interval).
    - **Why?** More reliable, simpler, scales perfectly for kiosk traffic (~15 req/s per school).
- [x] **Implementation**: Cleaned up `status_provider.dart` to use efficient timer-based polling.
- [x] **Backend**: Optimized Gunicorn with threads (`--workers=2 --threads=8`) to handle concurrent polling.
- [x] **Authentication Fix**: Removed `gevent` dependency which caused SSL recursion errors with Google Auth.

### Phase 8 - Landing Page Redesign
**Status**: Completed (2025-12-15)
- [x] **Visual Redesign**:
    - [x] **Hero**: Stronger copy ("Hall passes without the chaos").
    - [x] **Hierarchy**: Primary "Dashboard" vs Secondary "How it works".
    - [x] **Cards**: Sculptural "Enter your room" card with pill shapes.
- [x] **Assets**:
    - [x] **Logo Fix**: Switched to SVG for perfect scaling using `flutter_svg`.
    - [x] **Rendering**: Fixed "black box" SVG issue by inverting fill colors.
- [x] **FAQ**: Renamed to "Before you ask" with icons and refined answers.

### Phase 5 - Flutter Transition (Core & Polish)
**Status**: Core Functional Port Complete (2025-12-10)
- [x] **Kiosk UI**: Physics bubbles, sound synth, scanning engine.
- [x] **Responsiveness**: Adaptive layouts for mobile/desktop.
- [x] **State Management**: Provider-based architecture.
- [x] **API Layer**: Dart services for Flask backend.

### Phase 3 - UI/UX Overhaul (Web Version)
**Status**: Completed (2025-12-08)
- [x] **Motion**: Spring physics & shape morphing.
- [x] **Sound**: Custom soundscapes.
- [x] **Visuals**: Material 3 Expressive design.

### Phase 2 - Backend & Admin
**Status**: Completed (2025-12-07)
- [x] **Multi-Tenancy**: Isolated user settings.
- [x] **Security**: Roster encryption (Fernet).

---

# 🔧 Backend Refactoring (P4) - In Progress

## Current Status: Foundation Laid, Route Migration Remaining

### ✅ Completed This Session (2026-01-13)
- Created `routes/` directory structure
- Created `routes/__init__.py` for blueprint registration
- Created `routes/admin.py` template with auth decorators
- Created `routes/kiosk.py` placeholder
- Verified `auth.py` already exists (OAuth separated)

### 📊 Remaining Work
**app.py**: 2897 lines, 36 total routes
- ✅ Auth (4): Already in `auth.py`
- 🏗️ Admin (14): Template created, needs migration
- ❌ Kiosk (6): Placeholder only
- ❌ Dev (4): Not started
- ❌ Static (11): Not started

---

## 🚀 Next Steps: Phase 1 - Admin Routes Migration

Extract these 14 routes from `app.py` to `routes/admin.py`:

| Route | Line | Function | Dependencies |
|-------|------|----------|--------------|
| `/api/admin/stats` | 730 | `admin_stats_api()` | User, Settings, Session, SessionService |
| `/api/settings/update` | 884 | `update_settings_api()` | Settings |
| `/api/settings/suspend` | 931 | `api_suspend_kiosk()` | Settings |
| `/api/settings/slug` | 949 | `api_update_slug()` | User |
| `/api/roster/export` | 971 | `export_roster()` | RosterService |
| `/api/roster/template` | 1003 | `roster_template()` | CSV |
| `/api/roster/upload` | 1024 | `upload_roster_api()` | RosterService |
| `/api/roster` (GET) | 1115 | `get_roster_api()` | Roster |
| `/api/roster/ban` | 1147 | `ban_student_api()` | BanService |
| `/api/roster/clear` | 1172 | `clear_roster_api()` | RosterService |
| `/api/admin/logs` | 1194 | `get_pass_logs()` | Session |
| `/api/admin/logs/export` | 1230 | `export_logs()` | SessionService |
| `/api/control/ban_overdue` | 1276 | `api_ban_overdue_students()` | SessionService, BanService |
| `/api/control/delete_history` | 1304 | `api_delete_history()` | Session |

### Migration Steps
1. Copy each function from `app.py` → `routes/admin.py`
2. Change decorator: `@app.route` → `@admin_bp.route`
3. Add imports: `from app import db, User, Settings, Roster, Session`
4. Test EACH route after migration
5. Delete from `app.py` once verified
6. Register blueprint in `app.py`

### ⚠️ Critical Warnings
- **Circular Imports**: May need `extensions.py` for shared `db`
- **Helper Functions**: Decide where `get_settings()`, `get_current_user_id()` live
- **Testing Required**: Breaking admin routes = no system access

See artifact `implementation_plan.md` for complete Phase 2-4 details.
# HalllDay - Planning & Architecture Reference

**Last Updated**: 2026-01-13

---

## Application Overview

**HalllDay** is a multi-tenant digital hall pass management system for K-12 schools. Teachers can manage student passes via real-time kiosk and display interfaces while maintaining strict FERPA compliance through data encryption and multi-tenancy isolation.

### Core Purpose
- **Kiosk Screen**: Students scan in/out for hall passes
- **Display Screen**: Real-time visualization of active passes with Material 3 physics animations
- **Admin Dashboard**: Teacher portal for roster management, settings, analytics, and pass logs
- **Dev Dashboard**: System monitoring and multi-tenant user management (passcode-protected)

---

## Architecture

### Frontend (Flutter Web)
- **Technology**: Dart/Flutter compiled to JavaScript (Wasm-capable)
- **Navigation**: Single-page app with programmatic routing (`Navigator.pushNamed`)
- **State Management**: Provider pattern (`ChangeNotifier`)
- **UI Framework**: Material 3 with custom expressive animations
- **Key Screens**:
  - `landing_screen.dart` - Entry point with OAuth login
  - `kiosk_screen.dart` - Student scan interface (token-based access)
  - `display_screen.dart` - Live pass visualization with physics bubbles
  - `admin_screen.dart` - Teacher management dashboard
  - `dev_screen.dart` - System admin tools
- **Widgets**: Modular component library in `lib/widgets/`
  - `admin_widgets.dart` - 7 extracted admin helpers
  - `app_nav_drawer.dart` - Unified navigation drawer
  - `mobile_list_view.dart` - Responsive list components

### Backend (Flask/Python)
- **Framework**: Flask with SQLAlchemy ORM
- **Database**: PostgreSQL (production) / SQLite (dev)
- **Architecture**: **Modular Flask Blueprints** (as of P4 refactoring)
  - `auth.py` - Google OAuth 2.0 authentication
  - `routes/admin.py` - Admin/roster/settings/logs endpoints (14 routes)
  - `app.py` - App factory, kiosk/dev/static routes (reduced from 2902 → 2317 lines)
- **Services Layer** (business logic):
  - `services/roster.py` - Student roster management with encryption
  - `services/ban.py` - Ban list logic
  - `services/session.py` - Pass session tracking
- **Security**:
  - FERPA-compliant encryption (Fernet symmetric)
  - Student IDs encrypted at rest
  - Multi-tenant isolation via `user_id` foreign keys
  - Google OAuth for admin auth + legacy passcode fallback

### Data Models
- **User** - Teachers/admins (Google OAuth profiles)
- **Settings** - Per-user kiosk configuration (room name, capacity, overdue threshold)
- **StudentName** - Encrypted roster (hashed IDs, encrypted student IDs, display names)
- **Session** - Pass logs (student_id, start/end timestamps, room, user_id)
- **Queue** - Waitlist for capacity-limited passes
- **Ban** - (deprecated, integrated into StudentName.banned flag)

### Key Technologies
- **Flutter**: 3.x (Dart SDK)
- **Flask**: 2.x with SQLAlchemy 2.x
- **Database**: PostgreSQL (Render prod), SQLite (local dev)
- **Auth**: Authlib (Google OAuth), Flask sessions
- **Encryption**: `cryptography.fernet` for student ID encryption
- **Deployment**: Render (backend + database), Flutter web static hosting

---

## ✅ Completed Refactoring (2026-01-13)

### P1: Fixed `withOpacity` Deprecation
- **Impact**: Replaced 15 deprecated `withOpacity()` calls with `withValues(alpha: X)`
- **Files**: 5 modified (kiosk_screen, display_screen, landing_screen, etc.)
- **Result**: Zero deprecation warnings ✅

### P2: Extracted Admin Screen Widgets
- **Impact**: Reduced `admin_screen.dart` from 1736 → 1262 lines (-27%)
- **Created**: `admin_widgets.dart` with 7 public widgets:
  - `SectionHeader`, `StatsChip`, `CopyField`
  - `StatsCard`, `InsightCard`
  - `RosterManager`, `PassLogsDialog`
- **Pattern**: Dependency injection (callbacks passed via constructors)

### P3: Migrated `dart:html` to Modern APIs
- **File Upload**: `dart:html.FileUploadInputElement` → `file_picker` package
- **YouTube Iframe**: `dart:html.IFrameElement` → `package:web.HTMLIFrameElement`
- **Result**: Wasm compilation enabled ✅
  - `flutter build web --wasm` succeeds
  - F uture-proof for WebAssembly performance gains

### P4: Backend Modularization (Flask Blueprints)
- **Impact**: Reduced `app.py` from 2902 → 2317 lines (-20%, -585 lines)
- **Created**:
  - `routes/__init__.py` - Blueprint registration
  - `routes/admin.py` - 14 admin routes migrated:
    - Stats, settings (3), roster (6), logs (2), control (2), session management
- **Pattern**: Function-level imports from `app.py`, blueprint decorators
- **Testing**: All 14 endpoints verified ✅
- **Remaining Work**: Kiosk (6), Dev (4), Static (11) routes still in `app.py`

**Total Lines Removed**: 1059 lines (-474 widgets, -585 admin routes)

---

## 🔧 Recommended Future Refactoring

### Priority 1: Complete Backend Modularization
**Remaining routes in `app.py`** (~25 routes):
- **Kiosk Routes** (6): `/api/kiosk/<token>/status`, `/api/kiosk/<token>/scan`, queue endpoints
- **Dev Routes** (4): `/dev/login`, `/api/dev/*`
- **Static Routes** (11): `/`, `/kiosk`, `/display`, etc.

**Recommendation**: ✅ **Complete before adding major features**
- **Why**: Current `app.py` still monolithic for kiosk logic
- **Benefit**: Easier parallel development, clearer separation of concerns
- **Effort**: 2-3 hours (pattern established, copy-paste-test)
- **Risk**: Medium (kiosk routes have shared helpers like `_build_status_payload()`)

**Steps**:
1. Create `routes/kiosk.py` - Extract 6 kiosk/queue routes
2. Create `routes/dev.py` - Extract 4 dev dashboard routes
3. Create `routes/views.py` - Extract 11 static HTML routes
4. Test all routes, delete from `app.py`
5. **Target**: `app.py` < 1500 lines (app factory + helpers only)

---

### Priority 2: Frontend Widget Consolidation (Deferred)
**Observation**: `kiosk_screen.dart` and `display_screen.dart` share similar UI patterns:
- Status overlays
- Physics bubble components
- Color/animation logic

**Recommendation**: ⚠️ **Defer until after kiosk routes refactoring**
- **Why**: Low priority - screens work well independently
- **Benefit**: ~100-200 lines reduction, but marginal value
- **Effort**: 3-4 hours
- **Risk**: Low, but not critical path

---

### Priority 3: Service Layer Expansion (Optional)
**Current State**: 3 service modules (roster, ban, session) exist but not fully utilized

**Opportunity**: Move more business logic from routes to services
- Example: Stats calculation in `/api/admin/stats` could be `StatsService.get_insights()`
- Example: Queue promotion logic could be `QueueService.auto_promote()`

**Recommendation**: ⚠️ **Optional - if adding complex features**
- **Why**: Current routes are manageable; services exist for core CRUD
- **Benefit**: Easier unit testing, reusable logic
- **Effort**: 4-6 hours
- **Risk**: Low, but adds abstraction layers

---

## 🚀 Architecture Stability Assessment

### Ready for New Features? ✅ YES (with caveats)

**Strong Foundation**:
- ✅ Frontend modular (widgets separated)
- ✅ Admin routes modularized
- ✅ Services layer exists
- ✅ Multi-tenancy working
- ✅ Zero deprecation warnings
- ✅ Wasm-ready
- ✅ All tests passing

**Remaining Tech Debt**:
- ⚠️ `app.py` still has 25 routes (kiosk/dev/static)
- ⚠️ Some lint warnings exist (non-blocking)
- ⚠️ No automated test suite (relying on manual testing)

### Recommendation: Finish P4 First

**Before adding major features** (e.g., auto-suspend scheduling, analytics v2):
1. ✅ **Complete kiosk routes extraction** (highest impact, 2-3 hrs)
2. ✅ **Extract dev routes** (low risk, 1 hr)
3. ✅ **Extract static routes** (trivial, 30 min)
4. Test everything end-to-end

**Why**: A clean modular backend makes parallel feature development safer and faster.

**After P4 completion**, architecture will be stable for:
- Auto-suspend kiosk schedules
- Enhanced analytics
- Multi-room support
- SSO integrations
- Mobile app (Flutter supports iOS/Android with same codebase)

---

## Development Workflow

### Local Development
```bash
# Backend
python app.py  # Runs on localhost:5000

# Frontend
cd frontend
flutter run -d chrome  # Hot reload dev server
flutter build web      # Production build
```

### Deployment (Render)
- Backend: Gunicorn with 2 workers, 8 threads
- Database: PostgreSQL managed instance
- Frontend: Static files served from `frontend/build/web/`

### Environment Variables
- `DATABASE_URL` - PostgreSQL connection string
- `GOOGLE_CLIENT_ID` - OAuth client ID
- `GOOGLE_CLIENT_SECRET` - OAuth secret
- `ADMIN_PASSCODE` - Legacy fallback (optional)
- `FERNET_KEY` - Student ID encryption key (auto-generated if missing)

---

## Key Design Decisions

1. **Flutter over React**: Material 3 support, physics animations, potential mobile expansion
2. **PostgreSQL over MongoDB**: Relational data model, ACID compliance
3. **Encryption at rest**: FERPA compliance, student privacy
4. **Multi-tenancy**: User-specific kiosk tokens, isolated data
5. **Polling over SSE**: Simpler, more reliable (SSE had HTTP/2 proxy issues)
6. **Blueprint modularization**: Maintainability, parallel development

---

## Next Session Checklist

For future agents picking up this project:

1. Read this PLANNING.md (architecture overview)
2. Check `task.md` for current work status
3. Review `walkthrough.md` for recent changes
4. **If adding features**: Complete P4 kiosk/dev routes first
5. **If fixing bugs**: Check `implementation_plan.md` for context
6. Run `flutter analyze && flutter build web` to verify frontend
7. Run `python3 -m py_compile app.py routes/*.py` to verify backend

**Core Files to Understand**:
- Frontend: `lib/main.dart`, `lib/screens/*.dart`
- Backend: `app.py`, `routes/admin.py`, `services/*.py`
- Models: Search for `db.Model` classes in `app.py`
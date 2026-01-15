# HalllDay - Planning & Architecture Reference

**Last Updated**: 2026-01-14

---

## ⚠️ Security & Compliance Issues

### CRITICAL: Inconsistent Student ID Encryption

**Priority**: HIGH  
**FERPA Impact**: Potential compliance violation

**Issue**: Some students in the database have `encrypted_id = NULL`, meaning their student IDs are not encrypted at rest. This occurs when:
- CSV uploads contain blank student ID fields
- Legacy data was migrated before encryption was implemented
- Manual student creation without IDs

**Current Risk**:
- Inconsistent FERPA compliance across roster
- Some student IDs stored in plain text (via logs or session history)
- Admin roster displays "Hidden" or "Error" for students without encrypted IDs

**Recommended Fix**:
1. **Immediate**: Audit database for NULL `encrypted_id` values
2. **Short-term**: Add validation to CSV upload - reject rows with blank student IDs OR generate placeholder IDs
3. **Long-term**: Make `encrypted_id` non-nullable in schema with migration
4. **Monitoring**: Add logging/alerts when roster operations encounter NULL encrypted_id

**Verification**:
```sql
SELECT COUNT(*) FROM student_name WHERE encrypted_id IS NULL;
```

**Related Code**:
- `routes/admin.py` - CSV upload validation needed
- `app.py` - StudentName model (`encrypted_id` currently nullable)
- `services/roster.py` - Encryption logic

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

### P4: Backend Modularization (Flask Blueprints) ✅ COMPLETE
- **Impact**: Reduced `app.py` from 2,902 → 1,827 lines (-37%, -1,075 lines total)
- **Session 1 (Previous)**: Admin routes migration (-585 lines)
  - `routes/admin.py` - 14 admin routes migrated
- **Session 2 (2026-01-13)**: Kiosk + Dev routes migration (-490 lines)
  - `routes/kiosk.py` - 8 kiosk routes migrated:
    - POST /api/scan (main scan endpoint)
    - GET /api/status (status payload)
    - GET /api/stream, GET /events (SSE streaming)
    - Queue endpoints: join, leave, delete, reorder
    - Helper functions: `_build_status_payload`, `_build_status_signature`
  - `routes/dev.py` - 3 dev routes migrated:
    - POST /api/dev/auth (dev auth)
    - GET /api/dev/stats (basic stats)
    - POST /api/dev/expanded_stats (advanced stats with teacher activity)
  - `routes/__init__.py` - Updated blueprint registration
- **Pattern**: Function-level imports from `app.py`, blueprint decorators
- **Testing**: Manual verification (see walkthrough.md) ✅
- **Result**: Fully modular backend architecture ✅

**Total Lines Removed Across Both Sessions**: 1,075 lines (-474 widgets in P2, -585 admin routes in P4.1, -490 kiosk+dev routes in P4.2)

---

## 🔧 Recommended Future Refactoring

### Priority 1: Automated Testing Suite
**Current State**: No automated tests exist (all verification is manual)

**Recommendation**: ✅ **High Priority for Production Stability**
- **Why**: Manual testing doesn't scale; regression risks increase with each feature
- **Benefit**: Faster development, confidence in refactoring, easier debugging
- **Effort**: 8-12 hours for basic coverage
- **Risk**: Medium - requires learning test frameworks

**Suggested Approach**:
1. Add `pytest` and `pytest-flask` to requirements
2. Create `tests/` directory with unit tests for:
   - Services (roster, ban, session)
   - API endpoints (use Flask test client)
3. Integration tests for critical flows:
   - Student scan-in/scan-out
   - Queue management
   - Ban/override logic

---

### Priority 2: Frontend Widget Consolidation (Deferred)
**Observation**: `kiosk_screen.dart` and `display_screen.dart` share similar UI patterns:
- Status overlays
- Physics bubble components
- Color/animation logic

**Recommendation**: ⚠️ **Defer - Not critical path**
- **Why**: Low priority - screens work well independently
- **Benefit**: ~100-200 lines reduction, but marginal value
- **Effort**: 3-4 hours
- **Risk**: Low, but not critical

---

### Priority 3: Service Layer Expansion (Optional)
**Current State**: 3 service modules (roster, ban, session) exist and are used for core functionality

**What is it?**: Moving complex business logic from route handlers into dedicated service classes for better organization and reusability.

**Current services** (already implemented):
- `services/roster.py` - Student name lookups, encryption
- `services/ban.py` - Ban checking and auto-ban logic  
- `services/session.py` - Session queries and management

**When to add new services**:
- ✅ **Do create** if logic is complex (>50 lines) or reused across routes
- ✅ **Do create** for new major features (schedules, analytics)
- ⚠️ **Don't create** for simple CRUD operations or one-off queries

**Future candidates from planned features**:
- `services/scheduler.py` - When building Class Period Schedules (Priority 2)
  - Time-based kiosk suspension logic
  - Schedule rule evaluation
  - Template import/export
- `services/analytics.py` - When building Enhanced Analytics (Priority 3)
  - Complex stats calculations
  - Custom date range queries
  - Report generation

**Recommendation**: ⚠️ **Create services as needed, not preemptively**
- Current architecture is fine for simple features
- Add services when building schedules/analytics features
- Don't create services for simple features (queue self-remove, roster add/delete)

---

## 🚀 Architecture Stability Assessment

### Ready for New Features? ✅ YES

**Strong Foundation**:
- ✅ Frontend modular (widgets separated)
- ✅ Backend fully modular (all routes in blueprints)
- ✅ Services layer exists
- ✅ Multi-tenancy working
- ✅ Zero deprecation warnings
- ✅ Wasm-ready
- ✅ All imports verified

**Remaining Tech Debt** (Non-blocking):
- ⚠️ No automated test suite (manual testing only)
- ⚠️ Some lint warnings exist (non-critical)

### Recommendation: Ready for Feature Development

**Architecture is now stable for**:
- Auto-suspend kiosk schedules
- Enhanced analytics v2
- Multi-room support
- Additional SSO integrations
- Mobile app (Flutter supports iOS/Android with same codebase)
- Real-time notifications

**Next Steps**:
1. ✅ P4 Complete - Backend modularization done
2. Consider adding automated tests before major features (recommended but not required)
3. Begin feature development with confidence

---

## 🚀 Planned Features & Roadmap

### Priority 1: User Experience Improvements (Queue & Roster Management)

#### Feature: Self-Service Queue Removal
**Problem**: Students in the waitlist cannot remove themselves  
**Solution**: Allow students to scan badge again while in queue to remove themselves

**Implementation**:
- Modify `POST /api/scan` in `routes/kiosk.py`
- Check if student is in queue before adding
- If already in queue, remove them and return success message
- **Complexity**: Low (1-2 hours)
- **Dependencies**: None

---

#### Feature: Individual Roster Management
**Problem**: Teachers must upload entire CSV to add/remove students  
**Solution**: Add individual student add/remove UI in admin dashboard

**Implementation**:
- Add new routes in `routes/admin.py`:
  - `POST /api/roster/add` - Add single student
  - `DELETE /api/roster/<id>` - Remove single student
- Update Flutter admin UI with "Add Student" dialog
- Update Flutter admin UI with inline delete buttons
- **Complexity**: Medium (3-4 hours)
- **Dependencies**: None

---

#### Feature: Enhanced Ban Management Display
**Problem**: Roster view doesn't show ban duration/history  
**Solution**: Display # of days banned for each student in roster view

**Implementation**:
- Add `banned_since` timestamp to `StudentName` model
- Create migration to add column
- Update `routes/admin.py` roster endpoint to include ban duration
- Update Flutter admin UI to display ban days
- **Complexity**: Low (2-3 hours)
- **Dependencies**: Database migration

---

### Priority 2: Advanced Scheduling & Automation

#### Feature: Class Period Schedules with Auto-Suspend
**Problem**: Teachers need granular control over when restroom is available  
**Solution**: Build time-based schedules for kiosk availability (e.g., 10/10 rules: 10 min into class, 10 min before end)

**Implementation Details**:
- Add new `Schedule` model:
  - `user_id` (FK to User)
  - `day_of_week` (0-6 or "all")
  - `start_time`, `end_time`
  - `allow_restroom` (boolean)
  - `queue_only_mode` (boolean - allow queue even when suspended)
- Add schedule management routes in `routes/admin.py`:
  - `GET /api/schedules` - List schedules
  - `POST /api/schedules` - Create schedule
  - `PATCH /api/schedules/<id>` - Update schedule
  - `DELETE /api/schedules/<id>` - Delete schedule
- Add schedule checker in `routes/kiosk.py`:
  - Check current time against schedules before processing scan
  - Auto-suspend kiosk if outside allowed times
  - Optional: Allow queue-only mode when suspended
- Update Flutter admin UI:
  - Schedule builder with time pickers
  - Visual timeline/calendar view
  - Enable/disable auto-schedule feature
- **Complexity**: High (8-12 hours)
- **Dependencies**: None (standalone feature)

**Phase 2 - Schedule Templates**:
- Add exportable JSON format for schedules
- Import/export schedule templates
- Build community template library (future)
- **Complexity**: Medium (4-6 hours)
- **Dependencies**: Phase 1 complete

---

### Priority 3: Enhanced Analytics & Insights

#### Feature: Robust Insights Dashboard
**Problem**: Current insights are basic (top students, most overdue)  
**Solution**: Add detailed analytics with filtering and customization

**Potential Enhancements**:
- **Time-Based Analysis**:
  - Custom date range selection
  - Week-over-week comparisons
  - Peak usage times heatmap
- **Student-Level Metrics**:
  - Average duration per student
  - Return rate (% of students who go overdue)
  - Frequency patterns (students who go multiple times per day)
- **Capacity Analytics**:
  - Queue wait time averages
  - Times when capacity is most constrained
  - Recommendations for capacity adjustments
- **Export Options**:
  - PDF reports
  - Excel/CSV data exports
  - Scheduled email reports

**Implementation**:
- Add new routes in `routes/admin.py`:
  - `GET /api/analytics/overview` - Dashboard data
  - `POST /api/analytics/custom` - Custom query builder
- Create `services/analytics.py` for complex calculations
- Update Flutter admin UI with new analytics screens
- **Complexity**: High (12-16 hours)
- **Dependencies**: None

---

## Architecture Alignment for Planned Features

The completed P4 modularization positions the codebase well for these features:

**Why modular architecture helps**:
1. ✅ **Schedules**: New routes go cleanly into `routes/admin.py` and `routes/kiosk.py`
2. ✅ **Roster Management**: Individual add/remove routes fit naturally in `routes/admin.py`
3. ✅ **Analytics**: Complex logic can live in new `services/analytics.py`
4. ✅ **Queue Self-Remove**: Simple modification to existing `routes/kiosk.py`

**Recommended development order** (based on dependencies and user value):
1. Self-Service Queue Removal (quickest win, 1-2 hrs)
2. Individual Roster Management (high user value, 3-4 hrs)
3. Ban Duration Display (quick improvement, 2-3 hrs)
4. Class Period Schedules Phase 1 (major feature, 8-12 hrs)
5. Enhanced Analytics (major feature, 12-16 hrs)
6. Schedule Templates & Library (future enhancement)

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
4. **If adding features**: See "Planned Features & Roadmap" section above for prioritized feature list
5. **If fixing bugs**: Check `implementation_plan.md` for context
6. Run `flutter analyze && flutter build web` to verify frontend
7. Run `python3 -m py_compile app.py routes/*.py` to verify backend

**Core Files to Understand**:
- Frontend: `lib/main.dart`, `lib/screens/*.dart`
- Backend: `app.py`, `routes/admin.py`, `routes/kiosk.py`, `routes/dev.py`, `services/*.py`
- Models: Search for `db.Model` classes in `app.py`
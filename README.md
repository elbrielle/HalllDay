# IDK Can You? - Hall Pass Tracker

A modern, FERPA-compliant digital hall pass system designed for high-flow classrooms. Built with Flask and **Material 3 Expressive Design**, it combines privacy, fluid animations, and real-time syncing to create a seamless student experience using physical ID badges.

## Key Features

- **Smart Scanning**: Fast check-in/out via barcode scanner or numpad.
- **Fluid Multi-Pass UI**: Dynamic split-screen and grid layouts support multiple students simultaneously with fluid shape morphing animations.
- **Expressive Design**: Physics-based animations ("Alive" motion), morphing shapes (Bubbles), and specific soundscapes for positive/negative actions.
- **Privacy First (FERPA)**: Student IDs are hashed for lookup and encrypted at rest. No PII is exposed in plain text.
- **Real-time Sync**: Instant status updates across Kiosk and Display screens via Server-Sent Events (SSE).
- **Auto-Ban**: Configurable automatic banning of students who exceed time limits.
- **Dev Dashboard**: Technical admin controls for database management and system monitoring.

## Quick Start (Local)

1.  **Clone and Setup**:
    ```bash
    git clone <your-repo-url>
    cd HalllDay
    python -m venv .venv
    source .venv/bin/activate  # Windows: .venv\Scripts\activate
    pip install -r requirements.txt
    ```

2.  **Initialize Database**:
    ```bash
    flask --app app.py init-db
    ```

3.  **Run Development Server**:
    ```bash
    flask --app app.py run --debug
    ```

4.  **Access the App**:
    -   **Kiosk**: `http://localhost:5000/kiosk` (Student facing - Scanner input)
    -   **Display**: `http://localhost:5000/display` (Classroom facing - Projector)
    -   **Admin**: `http://localhost:5000/admin` (Teacher control)
    -   **Dev Tools**: `http://localhost:5000/dev/login` (Technical admin)

## Configuration

Configure the application using environment variables.

| Variable | Description | Default |
| :--- | :--- | :--- |
| `HALLPASS_SECRET_KEY` | **CRITICAL**: Used for encryption. Change in production. | `change-me-in-production` |
| `HALLPASS_ADMIN_PASSCODE` | Passcode for the `/dev` dashboard. | `admin123` |
| `HALLPASS_ROOM_NAME` | Name displayed on the screen. | `Hall Pass` |
| `HALLPASS_CAPACITY` | Max students allowed out at once. | `1` |
| `HALLPASS_MAX_MINUTES` | Threshold for "Overdue" status (minutes). | `12` |
| `DATABASE_URL` | Database connection string. | `sqlite:///instance/hallpass.db` |

## Appearance & Customization

The application uses **Material 3 Expressive** principles with a custom color palette.
- **Fonts**: Uses `Inter` for clean, readable typography.
- **Icons**: Uses Google Material Symbols.
- **Themes**: Status colors are bold and saturated for high visibility (Green=Available, Yellow=Overdue, Red=Full/Banned).

## Deployment

### Render.com (Recommended)
1.  Fork this repo.
2.  Create a **Web Service** on Render (Python 3).
3.  **Build Command**: `pip install -r requirements.txt`
4.  **Start Command** (SSE-enabled): `gunicorn -k gevent --worker-connections 1000 --timeout 0 app:app`
    - Notes:
      - SSE holds connections open; a gevent worker prevents each client from consuming a full sync worker.
      - If you prefer sync workers, SSE can still work for small deployments, but each connected client consumes a worker.
5.  Set your Environment Variables in the dashboard.
6.  Add a **PostgreSQL** database (optional but recommended for persistence).

### Important: Updating the Flutter UI in production
Render is running the **Flask app** and serving the prebuilt Flutter web assets from `static/`. It does **not** build Flutter for you.

When you change anything under `frontend/lib/`, you must:
- run `./deploy.sh` locally (builds Flutter web + copies `frontend/build/web/*` into `static/`)
- commit the updated `static/` files
- push to your repo so Render redeploys with the new UI bundle

## Admin Manual

### Roster Management
Upload a CSV file (`id, name`) in the Admin Panel. 
-   **Security**: Names are **encrypted** before being stored.
-   **Lookup**: Student IDs are **hashed** to allow private lookups.

### Developer Tools (`/dev`)
Access via `/dev/login` using the `HALLPASS_ADMIN_PASSCODE`.
-   **Database Stats**: View total sessions, active passes, and storage usage.
-   **Maintenance**: Tools to wipe/reset the database or clear active sessions if they get stuck.

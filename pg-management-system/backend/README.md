# PG Management System — Backend Service

Production-oriented FastAPI backend with PostgreSQL and SQLAlchemy 2.x for managing 5–6 PG properties.

---

## 1. Prerequisites

- **Python**: Version 3.12 or newer.
- **PostgreSQL**: Version 16 or newer running on localhost or accessible network host.
- **PowerShell**: Windows PowerShell 5.1+ or PowerShell Core 7+.

---

## 2. Setup & Installation (Windows PowerShell)

Open PowerShell and navigate to the `backend` directory:

```powershell
cd d:\PG_Management\pg-management-system\backend
```

### 2.1 Create & Activate Python Virtual Environment
```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

### 2.2 Install Required Dependencies
```powershell
python -m pip install --upgrade pip
pip install -r requirements.txt
```

### 2.3 Configure Environment Variables
Copy `.env.example` to `.env`:
```powershell
Copy-Item .env.example .env
```
Edit `.env` and set your PostgreSQL credentials:
```env
DATABASE_URL=postgresql+psycopg://postgres:your_password@localhost:5432/pg_management
```

---

## 3. Database Initialization & Migrations

### 3.1 Apply Database Migrations
```powershell
alembic upgrade head
```

### 3.2 Create Initial Super Administrator & Company Profile
```powershell
python scripts/create_initial_admin.py
```

---

## 4. Running the Development Server

Start the FastAPI application with live hot-reload:
```powershell
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

- **Health Probe**: [http://localhost:8000/api/v1/health](http://localhost:8000/api/v1/health)
- **Interactive Swagger UI**: [http://localhost:8000/api/v1/docs](http://localhost:8000/api/v1/docs)
- **ReDoc API Documentation**: [http://localhost:8000/api/v1/redoc](http://localhost:8000/api/v1/redoc)

---

## 5. Running Automated Tests

Run the test suite via pytest:
```powershell
pytest -v
```

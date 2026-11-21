import sys
from pathlib import Path

# Ensure pg-management-system/backend is prioritized on sys.path
root_dir = Path(__file__).resolve().parent.parent
backend_dir = root_dir / "pg-management-system" / "backend"

# Exclude root directory from sys.path to prevent namespace collision with legacy root app/ folder
sys.path = [p for p in sys.path if Path(p).resolve() != root_dir.resolve() and p != ""]
sys.path.insert(0, str(backend_dir))

# Evict any prematurely cached 'app' namespace
for mod in list(sys.modules.keys()):
    if mod == "app" or mod.startswith("app."):
        del sys.modules[mod]

# Import the existing production FastAPI ASGI instance from pg-management-system/backend
from app.main import app

# Export for Vercel Serverless Function runtime
__all__ = ["app"]

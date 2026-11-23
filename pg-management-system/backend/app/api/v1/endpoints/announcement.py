"""
Announcement endpoint compatibility module.
Exposes router and endpoint handlers aliased from announcements.py.
Supports both singular (/announcement) and plural (/announcements) routing.
"""
from app.api.v1.endpoints.announcements import *  # noqa: F401, F403
from app.api.v1.endpoints.announcements import router  # noqa: F401

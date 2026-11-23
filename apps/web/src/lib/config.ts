/** Base URL of the FastAPI backend (no trailing slash, no /api/v1). */
export const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";

/** The web app (residents, owner, kitchen). Same app as the phone app, opened in a browser. */
export const APP_URL = (process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:8081").replace(/\/$/, "");

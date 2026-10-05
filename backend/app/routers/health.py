"""GET /healthz: the app calls it to learn if the server is usable."""

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from app.schemas.phase1 import Health

router = APIRouter(tags=["health"])


@router.get("/healthz", response_model=Health, responses={503: {"model": Health}})
async def healthz(request: Request):
    if await request.app.state.db.healthy():
        return {"ok": True, "api": 1, "auth": request.app.state.settings.providers}
    return JSONResponse({"ok": False, "api": 1, "auth": []}, status_code=503)

"""GET, PATCH, DELETE /v1/me."""

import asyncpg
from fastapi import APIRouter, Request, Response

from app.auth.apple import revoke_or_log
from app.auth.deps import UserDep
from app.common import ensure_profile
from app.db import DbDep
from app.errors import Conflict
from app.schemas.phase1 import Me, MePatch

router = APIRouter(prefix="/v1", tags=["me"])

ME = """
select id, handle, display_name, avatar_color, visibility, share_ratings
from profiles where id = $1
"""

# One fixed statement. Each field has a flag: true means "set it to the value".
PATCH = """
update profiles set
  handle = case when $2::boolean then $3::text else handle end,
  display_name = case when $4::boolean then $5::text else display_name end,
  avatar_color = case when $6::boolean then $7::smallint else avatar_color end,
  visibility = case when $8::boolean then $9::text else visibility end,
  share_ratings = case when $10::boolean then $11::boolean else share_ratings end
where id = $1
returning id, handle, display_name, avatar_color, visibility, share_ratings
"""


@router.get("/me", response_model=Me)
async def get_me(user: UserDep, db: DbDep):
    async with db.tx() as c:
        row = await c.fetchrow(ME, user)
        if row is None:
            await ensure_profile(c, user)
            row = await c.fetchrow(ME, user)
    return dict(row)


@router.patch("/me", response_model=Me)
async def patch_me(body: MePatch, user: UserDep, db: DbDep):
    sent = body.model_fields_set
    async with db.tx() as c:
        await ensure_profile(c, user)
        try:
            row = await c.fetchrow(
                PATCH,
                user,
                "handle" in sent,
                body.handle,
                "display_name" in sent,
                body.display_name,
                "avatar_color" in sent,
                body.avatar_color,
                "visibility" in sent,
                body.visibility,
                "share_ratings" in sent,
                body.share_ratings,
            )
        except asyncpg.UniqueViolationError as exc:
            raise Conflict("handle_taken", "That handle is taken") from exc
    return dict(row)


@router.delete("/me", status_code=204)
async def delete_me(request: Request, user: UserDep, db: DbDep):
    # The auth user goes FIRST. Once GoTrue is gone, every surviving access token
    # dies in ensure_profile with a foreign-key error (401 account_deleted), so a
    # database failure after this point cannot resurrect the account; the next
    # call to DELETE /v1/me finishes the job (a 404 from GoTrue counts as done).
    # delete_account() takes the same advisory lock as a sync push.
    # Read the Apple refresh token before the profile is gone, so the grant can
    # be revoked after deletion (App Store rule 4.8).
    async with db.conn() as c:
        apple_refresh = await c.fetchval(
            "select apple_refresh_token from profiles where id = $1", user
        )
    await request.app.state.gotrue.delete_user(user)
    async with db.tx() as c:
        await c.execute("select delete_account($1)", user)
    # Best effort: a revoke failure is logged and never blocks the deletion.
    await revoke_or_log(request.app.state.apple, apple_refresh)
    return Response(status_code=204)

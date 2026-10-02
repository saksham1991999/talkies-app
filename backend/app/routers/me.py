"""GET, PATCH, DELETE /v1/me."""

import asyncpg
from fastapi import APIRouter, Request, Response

from app.auth.apple import revoke_or_log
from app.auth.deps import DeletingUserDep, UserDep
from app.common import ensure_profile
from app.db import DbDep, lock_user
from app.errors import Conflict, Unauthorized
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
        if row is None:
            # The account was deleted between the profile check and this update.
            # The row cannot come back, so say what happened instead of a 500.
            # The same 401 shape as every other route: a bearer challenge.
            raise Unauthorized("account_deleted", "This account was deleted")
    return dict(row)


@router.delete("/me", status_code=204)
async def delete_me(request: Request, user: DeletingUserDep, db: DbDep):
    # The auth user goes FIRST. Once GoTrue is gone, every surviving access token
    # is refused with 401 account_deleted, so a database failure after this point
    # cannot resurrect the account; the next call to DELETE /v1/me finishes the
    # job (a 404 from GoTrue counts as done). That retry is why this route takes
    # the token-only dependency: after a half-finished delete the account row is
    # already gone, and the retry still has to be let through to clean it up.
    #
    # The user lock is taken in both transactions and never held across the
    # GoTrue call. delete_account() takes the same advisory lock, so a sync push
    # in flight either lands entirely before the deletion or waits and then
    # fails on the missing profile, and can never interleave with the cascade.
    # Releasing the connection for the upstream call matters: it can take eight
    # seconds, and ten of those would pin every connection in the pool.
    async with db.tx() as c:
        await lock_user(c, user)
        # Read the Apple refresh token before the profile is gone, so the grant
        # can be revoked after deletion (App Store rule 4.8).
        apple_refresh = await c.fetchval(
            "select apple_refresh_token from profiles where id = $1", user
        )
    await request.app.state.gotrue.delete_user(user)
    async with db.tx() as c:
        await lock_user(c, user)
        await c.execute("select delete_account($1)", user)
    # Best effort: a revoke failure is logged and never blocks the deletion.
    await revoke_or_log(request.app.state.apple, apple_refresh)
    return Response(status_code=204)

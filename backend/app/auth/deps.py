"""FastAPI dependencies for the signed-in user."""

from typing import Annotated
from uuid import UUID

from fastapi import Depends, Request

from app.db import DbDep
from app.errors import Unauthorized

# A signed token outlives the account it belongs to: Supabase keeps issuing no
# new ones, but an old one stays valid until it expires. Every protected route
# learns here that the account is gone, so deletion answers 401 account_deleted
# on every route, not just the ones that create the profile row.
ACCOUNT_EXISTS = "select 1 from auth.users where id = $1"


def bearer_token(request: Request) -> str:
    scheme, _, token = request.headers.get("authorization", "").partition(" ")
    token = token.strip()
    if scheme.lower() != "bearer" or not token or len(token) > 8192:
        raise Unauthorized()
    return token


async def current_user(
    request: Request, token: Annotated[str, Depends(bearer_token)], db: DbDep
) -> UUID:
    user = await request.app.state.verifier.verify(token)
    if await db.fetchrow(ACCOUNT_EXISTS, user) is None:
        raise Unauthorized("account_deleted", "This account was deleted")
    return user


async def deleting_user(request: Request, token: Annotated[str, Depends(bearer_token)]) -> UUID:
    """The signed-in user without the account check, for DELETE /v1/me only.

    Deletion removes the auth user first, so a delete whose local cleanup failed
    leaves a token that outlives its account. That retry has to be let through:
    the account row it is about to finish removing is already gone.
    """
    return await request.app.state.verifier.verify(token)


Token = Annotated[str, Depends(bearer_token)]
UserDep = Annotated[UUID, Depends(current_user)]
DeletingUserDep = Annotated[UUID, Depends(deleting_user)]

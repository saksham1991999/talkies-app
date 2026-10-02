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


Token = Annotated[str, Depends(bearer_token)]
UserDep = Annotated[UUID, Depends(current_user)]

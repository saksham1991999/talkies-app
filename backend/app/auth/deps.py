"""FastAPI dependencies for the signed-in user."""

from typing import Annotated
from uuid import UUID

from fastapi import Depends, Request

from app.errors import Unauthorized


def bearer_token(request: Request) -> str:
    scheme, _, token = request.headers.get("authorization", "").partition(" ")
    token = token.strip()
    if scheme.lower() != "bearer" or not token or len(token) > 8192:
        raise Unauthorized()
    return token


async def current_user(request: Request, token: Annotated[str, Depends(bearer_token)]) -> UUID:
    return await request.app.state.verifier.verify(token)


Token = Annotated[str, Depends(bearer_token)]
UserDep = Annotated[UUID, Depends(current_user)]

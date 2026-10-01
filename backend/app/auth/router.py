"""POST /v1/auth/*: sign-in through Supabase Auth."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Request, Response

from app.auth.apple import save_refresh_token
from app.auth.deps import Token, UserDep
from app.auth.gotrue import GoTrue
from app.errors import NotFound
from app.ratelimit import LimiterDep, client_ip
from app.schemas.phase1 import (
    IdTokenRequest,
    OtpRequest,
    RefreshRequest,
    Session,
    VerifyRequest,
)

router = APIRouter(prefix="/v1/auth", tags=["auth"])


def get_gotrue(request: Request) -> GoTrue:
    return request.app.state.gotrue


GoTrueDep = Annotated[GoTrue, Depends(get_gotrue)]


@router.post("/otp", status_code=204)
async def send_code(body: OtpRequest, request: Request, limiter: LimiterDep, auth: GoTrueDep):
    limiter.check("otp_ip", client_ip(request))
    limiter.check("otp_email", body.email)
    await auth.send_otp(body.email)
    return Response(status_code=204)


@router.post("/verify", response_model=Session)
async def verify_code(body: VerifyRequest, request: Request, limiter: LimiterDep, auth: GoTrueDep):
    limiter.check("verify_ip", client_ip(request))
    return await auth.verify(body.email, body.code)


@router.post("/refresh", response_model=Session)
async def refresh(body: RefreshRequest, request: Request, limiter: LimiterDep, auth: GoTrueDep):
    limiter.check("refresh_ip", client_ip(request))
    return await auth.refresh(body.refresh_token)


@router.post("/id-token", response_model=Session)
async def id_token(body: IdTokenRequest, request: Request, auth: GoTrueDep):
    if body.provider not in request.app.state.settings.providers:
        raise NotFound("provider_disabled", "This sign-in method is off")
    session = await auth.id_token(body.provider, body.id_token, body.access_token, body.nonce)
    # Apple revocation (App Store rule 4.8): keep the refresh token that the
    # authorization code buys, so DELETE /v1/me can revoke the grant later.
    # Best effort; a failure never blocks the sign-in.
    if body.provider == "apple" and body.authorization_code:
        await save_refresh_token(
            request.app.state.apple,
            request.app.state.db,
            body.authorization_code,
            UUID(session["user"]["id"]),
        )
    return session


@router.post("/logout", status_code=204)
async def logout(_: UserDep, token: Token, auth: GoTrueDep):
    await auth.logout(token)
    return Response(status_code=204)

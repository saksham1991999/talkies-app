"""The error envelope: {"error": {"code", "message", "detail"}}.

Messages are fixed English text for developers. They never echo input.
"""

import logging
from typing import Any

import asyncpg
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

log = logging.getLogger("talkies")


class ApiError(Exception):
    def __init__(
        self,
        status: int,
        code: str,
        message: str,
        detail: Any = None,
        headers: dict[str, str] | None = None,
    ):
        super().__init__(code)
        self.status = status
        self.code = code
        self.message = message
        self.detail = detail
        self.headers = headers or {}


class BadRequest(ApiError):
    def __init__(self, code: str = "invalid_request", message: str = "Bad request", detail=None):
        super().__init__(400, code, message, detail)


class Unauthorized(ApiError):
    def __init__(self, code: str = "unauthorized", message: str = "Sign in required"):
        super().__init__(401, code, message, headers={"WWW-Authenticate": "Bearer"})


class Forbidden(ApiError):
    def __init__(self, message: str = "Not allowed"):
        super().__init__(403, "forbidden", message)


class NotFound(ApiError):
    def __init__(self, code: str = "not_found", message: str = "Not found"):
        super().__init__(404, code, message)


class Conflict(ApiError):
    def __init__(self, code: str, message: str = "Conflict", detail=None):
        super().__init__(409, code, message, detail)


class TooLarge(ApiError):
    def __init__(self, message: str = "Request is too large"):
        super().__init__(413, "too_large", message)


class Invalid(ApiError):
    def __init__(self, message: str = "Invalid request", detail=None):
        super().__init__(422, "invalid_request", message, detail)


class RateLimited(ApiError):
    def __init__(self, retry_after: int):
        super().__init__(
            429,
            "rate_limited",
            "Too many requests",
            headers={"Retry-After": str(max(1, retry_after))},
        )


class Upstream(ApiError):
    def __init__(self, message: str = "The sign-in service is not reachable"):
        super().__init__(502, "upstream_unavailable", message)


class DbUnavailable(ApiError):
    def __init__(self):
        super().__init__(503, "db_unavailable", "The database is not reachable")


def envelope(code: str, message: str, detail: Any = None) -> dict:
    return {"error": {"code": code, "message": message, "detail": detail}}


def reply(status: int, code: str, message: str, detail: Any = None, headers=None) -> JSONResponse:
    return JSONResponse(envelope(code, message, detail), status_code=status, headers=headers)


_STATUS_CODES = {
    401: "unauthorized",
    403: "forbidden",
    404: "not_found",
    405: "method_not_allowed",
    413: "too_large",
    429: "rate_limited",
}

# The database or the link to it is down or busy: the client may retry.
DB_DOWN = (
    OSError,
    asyncpg.PostgresConnectionError,
    asyncpg.InterfaceError,
    asyncpg.exceptions.OperatorInterventionError,
    asyncpg.exceptions.InsufficientResourcesError,
    asyncpg.exceptions.TransactionRollbackError,
    asyncpg.exceptions.InvalidAuthorizationSpecificationError,
)


async def _api_error(_: Request, exc: ApiError) -> JSONResponse:
    return reply(exc.status, exc.code, exc.message, exc.detail, exc.headers)


async def _validation(_: Request, exc: RequestValidationError) -> JSONResponse:
    # Only the place and the kind of each problem. The input is never echoed.
    detail = [{"loc": list(e["loc"]), "type": e["type"]} for e in exc.errors()[:10]]
    return reply(422, "invalid_request", "Invalid request", detail)


async def _http(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    code = _STATUS_CODES.get(exc.status_code, "http_error")
    return reply(exc.status_code, code, "Request failed", headers=exc.headers)


async def _db_down(_: Request, exc: Exception) -> JSONResponse:
    log.warning("database error: %s", type(exc).__name__)
    return reply(503, "db_unavailable", "The database is not reachable")


async def _not_found_row(_: Request, exc: asyncpg.ForeignKeyViolationError) -> JSONResponse:
    # A row that was referenced is gone (for example a deleted account).
    log.warning("foreign key: %s", exc.constraint_name)
    return reply(404, "not_found", "Not found")


async def _conflict_row(_: Request, exc: asyncpg.UniqueViolationError) -> JSONResponse:
    log.warning("unique: %s", exc.constraint_name)
    return reply(409, "conflict", "Conflict")


async def _bad_row(_: Request, exc: Exception) -> JSONResponse:
    # The database refused a value that the app should have checked.
    log.warning("rejected value: %s", type(exc).__name__)
    return reply(422, "invalid_request", "Invalid request")


async def _unhandled(_: Request, exc: Exception) -> JSONResponse:
    log.error("unhandled %s", type(exc).__name__, exc_info=exc)
    return reply(500, "internal", "Internal error")


def install_handlers(app: FastAPI) -> None:
    app.add_exception_handler(ApiError, _api_error)
    app.add_exception_handler(RequestValidationError, _validation)
    app.add_exception_handler(StarletteHTTPException, _http)
    for kind in DB_DOWN:
        app.add_exception_handler(kind, _db_down)
    app.add_exception_handler(asyncpg.ForeignKeyViolationError, _not_found_row)
    app.add_exception_handler(asyncpg.UniqueViolationError, _conflict_row)
    for kind in (asyncpg.CheckViolationError, asyncpg.NotNullViolationError, asyncpg.DataError):
        app.add_exception_handler(kind, _bad_row)
    app.add_exception_handler(Exception, _unhandled)

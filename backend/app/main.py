import sentry_sdk
from fastapi import FastAPI, Request
from fastapi.exceptions import HTTPException
from fastapi.responses import JSONResponse
from fastapi.routing import APIRoute
from starlette.middleware.cors import CORSMiddleware

from app.api.main import api_router
from app.api.routes.ws_chat import ws_router
from app.core.config import settings


def custom_generate_unique_id(route: APIRoute) -> str:
    return f"{route.tags[0]}-{route.name}"


if settings.SENTRY_DSN and settings.ENVIRONMENT != "local":
    sentry_sdk.init(dsn=str(settings.SENTRY_DSN), enable_tracing=True)

app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    generate_unique_id_function=custom_generate_unique_id,
)


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException) -> JSONResponse:
    """Produce flat error responses: {"detail": "...", "code": "..."}.

    Passes dict details through directly; wraps string details in {"detail": "..."}.
    Preserves custom headers (e.g., WWW-Authenticate) set on the exception.
    """
    if isinstance(exc.detail, dict):
        content = exc.detail
    else:
        content = {"detail": str(exc.detail)}

    headers = dict(exc.headers) if exc.headers else {}
    # Ensure 401 responses always carry WWW-Authenticate per RFC 6750 §3
    if exc.status_code == 401 and "WWW-Authenticate" not in headers:
        headers["WWW-Authenticate"] = "Bearer"

    return JSONResponse(
        status_code=exc.status_code,
        content=content,
        headers=headers or None,
    )


# Set all CORS enabled origins
if settings.all_cors_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.all_cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

app.include_router(api_router, prefix=settings.API_V1_STR)
app.include_router(ws_router)  # /ws/chat/{room_id} — not under /api/v1/ prefix

import httpx
from fastapi import HTTPException, status

GOOGLE_TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"

# Module-level client with timeout — reused across requests for connection pooling
_http_client = httpx.AsyncClient(timeout=httpx.Timeout(10.0, connect=5.0))


async def verify_google_id_token(id_token: str, client_id: str) -> dict[str, str]:
    """Verify a Google id_token via Google's tokeninfo endpoint.

    Returns {"sub": "...", "email": "...", "name": "..."} on success.
    Raises HTTP 400 on invalid or unverifiable tokens.
    When client_id is empty (local dev only), audience validation is skipped.
    """
    try:
        resp = await _http_client.get(
            GOOGLE_TOKENINFO_URL, params={"id_token": id_token}
        )
    except httpx.TimeoutException:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"detail": "Google 인증 서버 응답 시간 초과입니다.", "code": "GOOGLE_TIMEOUT"},
        )

    if resp.status_code != 200:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"detail": "유효하지 않은 Google 토큰입니다.", "code": "INVALID_GOOGLE_TOKEN"},
        )

    data = resp.json()

    sub = data.get("sub")
    email = data.get("email")
    if not sub or not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"detail": "유효하지 않은 Google 토큰입니다.", "code": "INVALID_GOOGLE_TOKEN"},
        )

    # Validate audience — must match our server's client_id to prevent token reuse attacks.
    # client_id may be empty in local development; enforce strictly in all other cases.
    if client_id:
        if data.get("aud") != client_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={"detail": "유효하지 않은 Google 토큰입니다.", "code": "INVALID_GOOGLE_TOKEN"},
            )

    return {
        "sub": sub,
        "email": email,
        "name": data.get("name", ""),
    }

import uuid

import httpx

from app.core.config import settings

_CONTENT_TYPES = {
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "png": "image/png",
    "webp": "image/webp",
    "gif": "image/gif",
}


def _get_ext(filename: str) -> str:
    return filename.rsplit(".", 1)[-1].lower() if "." in filename else ""


def _make_key(filename: str) -> str:
    ext = _get_ext(filename) or "jpg"
    return f"products/{uuid.uuid4()}.{ext}"


def _content_type(filename: str) -> str:
    return _CONTENT_TYPES.get(_get_ext(filename), "image/jpeg")


def upload_image(content: bytes, filename: str) -> str:
    """Upload image bytes to Supabase Storage and return the public URL."""
    key = _make_key(filename)
    base = settings.SUPABASE_URL.rstrip("/")
    bucket = settings.SUPABASE_BUCKET_NAME
    upload_url = f"{base}/storage/v1/object/{bucket}/{key}"
    headers = {
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_KEY}",
        "Content-Type": _content_type(filename),
    }
    with httpx.Client(timeout=30) as client:
        response = client.post(upload_url, content=content, headers=headers)
        response.raise_for_status()
    return f"{base}/storage/v1/object/public/{bucket}/{key}"

import functools
import uuid
from typing import Any

import boto3

from app.core.config import settings

_CONTENT_TYPES = {
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "png": "image/png",
    "webp": "image/webp",
    "gif": "image/gif",
}


def _get_ext(filename: str) -> str:
    """Return the lowercased extension without dot, or '' if none."""
    return filename.rsplit(".", 1)[-1].lower() if "." in filename else ""


def _make_key(filename: str) -> str:
    ext = _get_ext(filename) or "jpg"
    return f"products/{uuid.uuid4()}.{ext}"


def _content_type(filename: str) -> str:
    return _CONTENT_TYPES.get(_get_ext(filename), "image/jpeg")


@functools.lru_cache(maxsize=1)
def _get_s3_client() -> Any:
    """Return a reusable boto3 S3 client (created once per process)."""
    return boto3.client(
        "s3",
        endpoint_url=f"https://{settings.R2_ACCOUNT_ID}.r2.cloudflarestorage.com",
        aws_access_key_id=settings.R2_ACCESS_KEY_ID,
        aws_secret_access_key=settings.R2_SECRET_ACCESS_KEY,
        region_name="auto",
    )


def upload_image(content: bytes, filename: str) -> str:
    """Upload image bytes to Cloudflare R2 and return the public URL."""
    key = _make_key(filename)
    _get_s3_client().put_object(
        Bucket=settings.R2_BUCKET_NAME,
        Key=key,
        Body=content,
        ContentType=_content_type(filename),
    )
    return f"{settings.R2_PUBLIC_URL}/{key}"

"""
Photo preparation for moment capture.

Phones hand us whatever they like — an iPhone's default is HEIC, and a modern
camera photo is several megabytes. Both used to break story-from-photo: HEIC was
rejected outright (415) and a 10 MB image became a ~13 MB base64 string on the
way to the vision model, which is slow and times out.

This module normalises anything the phone sends into a small JPEG. Pillow is
optional: if it (or HEIC support) is missing on the host, we degrade to passing
the original bytes through rather than failing the upload.
"""
from __future__ import annotations

import io
import logging

logger = logging.getLogger(__name__)

# Long edge we send to the vision model. Plenty for "what is in this picture",
# and roughly a 10x smaller payload than a raw camera photo.
MAX_EDGE = 1280
JPEG_QUALITY = 82


def sniff_image_format(data: bytes) -> str:
    """Identify the container from magic bytes — the client's content-type is
    not trustworthy (browsers mislabel, pickers re-encode)."""
    if len(data) < 12:
        return "unknown"
    if data[:3] == b"\xff\xd8\xff":
        return "jpeg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    if data[4:8] == b"ftyp":
        brand = data[8:12]
        if brand in (b"heic", b"heix", b"hevc", b"heim", b"heis", b"hevm",
                     b"mif1", b"msf1", b"avif"):
            return "heic"
        return "mp4"
    if data[:2] == b"BM":
        return "bmp"
    if data[:4] in (b"II*\x00", b"MM\x00*"):
        return "tiff"
    return "unknown"


def _heif_ready() -> bool:
    """Register HEIC/HEIF support with Pillow if the plugin is installed."""
    try:
        import pillow_heif  # type: ignore

        pillow_heif.register_heif_opener()
        return True
    except Exception:  # noqa: BLE001 — optional dependency
        return False


def prepare_photo(data: bytes, declared_type: str = "") -> tuple[bytes, str, str]:
    """Return (bytes, mime, note) ready for the vision model.

    Always safe to call: on any failure the original bytes are returned so the
    upload still has a chance rather than erroring out.
    """
    fmt = sniff_image_format(data)
    if fmt == "heic":
        _heif_ready()

    try:
        from PIL import Image, ImageOps
    except Exception:  # noqa: BLE001 — Pillow not installed on this host
        mime = "image/jpeg" if fmt in ("jpeg", "unknown") else f"image/{fmt}"
        return data, mime, f"passthrough:{fmt}"

    try:
        img = Image.open(io.BytesIO(data))
        # Honour the camera's rotation flag, then drop it — otherwise portrait
        # photos reach the model sideways.
        img = ImageOps.exif_transpose(img)
        if img.mode not in ("RGB", "L"):
            img = img.convert("RGB")
        before = img.size
        img.thumbnail((MAX_EDGE, MAX_EDGE), Image.LANCZOS)
        out = io.BytesIO()
        img.save(out, format="JPEG", quality=JPEG_QUALITY, optimize=True)
        small = out.getvalue()
        logger.info(
            "[PhotoPrep] %s %s -> jpeg %s (%.0fKB -> %.0fKB)",
            fmt, before, img.size, len(data) / 1024, len(small) / 1024,
        )
        return small, "image/jpeg", f"converted:{fmt}"
    except Exception as e:  # noqa: BLE001 — never block the upload on this
        logger.warning("[PhotoPrep] could not convert %s (%s) — sending as-is", fmt, e)
        mime = "image/jpeg" if fmt in ("jpeg", "unknown") else f"image/{fmt}"
        return data, mime, f"passthrough:{fmt}"

"""
Server-side audio container sniffing.

Browser MediaRecorder emits webm/opus (or mp4/aac on Safari), never raw WAV —
so trusting a ".wav" filename from the client is wrong and makes ASR fail
silently. We inspect the leading magic bytes and tell each provider the real
format instead.
"""
from __future__ import annotations

# container name → (file extension, mime type)
_MIME = {
    "wav": ("wav", "audio/wav"),
    "webm": ("webm", "audio/webm"),
    "ogg": ("ogg", "audio/ogg"),
    "mp3": ("mp3", "audio/mpeg"),
    "mp4": ("mp4", "audio/mp4"),
    "flac": ("flac", "audio/flac"),
}


def sniff_audio_format(data: bytes) -> str:
    """Best-effort container sniff from magic bytes. Defaults to 'wav'."""
    if not data or len(data) < 12:
        return "wav"
    if data[:4] == b"RIFF" and data[8:12] == b"WAVE":
        return "wav"
    if data[:4] == b"OggS":
        return "ogg"
    if data[:4] == b"\x1aE\xdf\xa3":  # EBML — webm / matroska
        return "webm"
    if data[:4] == b"fLaC":
        return "flac"
    if data[4:8] == b"ftyp":  # ISO base media — mp4 / m4a
        return "mp4"
    if data[:3] == b"ID3" or data[:2] == b"\xff\xfb":
        return "mp3"
    return "wav"


def extension_for(fmt: str) -> str:
    return _MIME.get(fmt, _MIME["wav"])[0]


def mime_for(fmt: str) -> str:
    return _MIME.get(fmt, _MIME["wav"])[1]

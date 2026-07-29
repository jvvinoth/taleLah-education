"""Resend transactional email — signup verification & password reset codes.

Degradation ladder (house pattern): without RESEND_API_KEY the code is
logged at INFO and the flow continues, so local dev and CI never depend
on a live email provider.
"""
from __future__ import annotations

import logging

import httpx

from ..core.config import settings

logger = logging.getLogger(__name__)

RESEND_API_URL = "https://api.resend.com/emails"

# Brand palette (matches app/theme + marketing site)
_CREAM = "#FBF6EC"
_INK = "#2E2A25"
_INK_SOFT = "#6B6257"
_CORAL = "#FF6B5E"


def _brand_email(*, heading: str, intro: str, code: str, note: str) -> str:
    """Email-client-safe branded template — tables + inline CSS only."""
    return f"""\
<!DOCTYPE html>
<html lang="en">
<body style="margin:0;padding:0;background-color:{_CREAM};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
         style="background-color:{_CREAM};padding:32px 0;">
    <tr><td align="center">
      <table role="presentation" width="440" cellpadding="0" cellspacing="0"
             style="background:#FFFFFF;border-radius:24px;overflow:hidden;
                    font-family:Georgia,'Times New Roman',serif;">
        <tr>
          <td style="background:{_CORAL};padding:28px 40px;text-align:center;">
            <div style="font-size:40px;line-height:1;">&#128038;</div>
            <div style="color:#FFFFFF;font-size:26px;font-weight:bold;
                        letter-spacing:0.5px;padding-top:8px;">TaleLah</div>
            <div style="color:#FFE9E6;font-size:13px;padding-top:4px;
                        font-family:Helvetica,Arial,sans-serif;">
              Everyday moments. Mother-tongue magic.</div>
          </td>
        </tr>
        <tr>
          <td style="padding:36px 40px 12px;">
            <div style="color:{_INK};font-size:21px;font-weight:bold;">{heading}</div>
            <div style="color:{_INK_SOFT};font-size:15px;line-height:1.6;
                        padding-top:12px;font-family:Helvetica,Arial,sans-serif;">
              {intro}</div>
          </td>
        </tr>
        <tr>
          <td style="padding:20px 40px;" align="center">
            <div style="background:{_CREAM};border-radius:16px;padding:22px 0;
                        font-family:Courier,'Courier New',monospace;
                        font-size:36px;font-weight:bold;letter-spacing:12px;
                        color:{_INK};text-indent:12px;">{code}</div>
          </td>
        </tr>
        <tr>
          <td style="padding:0 40px 32px;">
            <div style="color:{_INK_SOFT};font-size:13px;line-height:1.6;
                        font-family:Helvetica,Arial,sans-serif;">{note}</div>
          </td>
        </tr>
        <tr>
          <td style="background:{_CREAM};padding:20px 40px;text-align:center;">
            <div style="color:{_INK_SOFT};font-size:12px;
                        font-family:Helvetica,Arial,sans-serif;">
              Made with &#10084;&#65039; in Singapore &middot; TaleLah &#128038;<br>
              You received this because someone used this address on TaleLah.
              If it wasn't you, you can safely ignore this email.</div>
          </td>
        </tr>
      </table>
    </td></tr>
  </table>
</body>
</html>"""


async def _send(to: str, subject: str, html: str, code: str) -> bool:
    """POST to Resend; log-only fallback when no API key. Returns delivered?"""
    if not settings.resend_api_key:
        logger.info(f"📧 [email off] To {to} — '{subject}' — code: {code}")
        return False
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(
                RESEND_API_URL,
                headers={"Authorization": f"Bearer {settings.resend_api_key}"},
                json={
                    "from": settings.resend_from_email,
                    "to": [to],
                    "subject": subject,
                    "html": html,
                },
            )
        if resp.status_code in (200, 201):
            logger.info(f"📧 Sent '{subject}' to {to}")
            return True
        logger.warning(f"📧 Resend {resp.status_code}: {resp.text[:200]}")
    except Exception as e:  # noqa: BLE001 — email must never crash a request
        logger.warning(f"📧 Resend send failed: {e}")
    return False


async def send_verification_email(to: str, name: str, code: str) -> bool:
    html = _brand_email(
        heading=f"Welcome, {name}! 🎉",
        intro=(
            "You're one step from turning everyday family moments into "
            "mother-tongue stories. Enter this code in the app to verify "
            "your email:"
        ),
        code=code,
        note="This code expires in 15 minutes. Mina is waiting for you! 🐦",
    )
    return await _send(to, "Your TaleLah verification code", html, code)


async def send_reset_email(to: str, name: str, code: str) -> bool:
    html = _brand_email(
        heading=f"Reset your password, {name}",
        intro=(
            "We received a request to reset your TaleLah password. "
            "Enter this code in the app to choose a new one:"
        ),
        code=code,
        note=(
            "This code expires in 15 minutes. If you didn't ask for a reset, "
            "your account is safe — just ignore this email."
        ),
    )
    return await _send(to, "Your TaleLah password reset code", html, code)

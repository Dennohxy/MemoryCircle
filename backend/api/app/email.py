"""Transactional email via Resend.

Configured with two environment variables:

- ``RESEND_API_KEY`` — the Resend API key.
- ``EMAIL_FROM``     — the verified sender, e.g. ``Omoide no Wa <no-reply@omoidenowa.com>``.

When the key is missing (local development, tests) sending is a no-op so the
rest of the app keeps working; callers can check the return value.
"""

from __future__ import annotations

import logging
import os

import httpx

logger = logging.getLogger("omoide.email")

RESEND_API_KEY = os.getenv("RESEND_API_KEY", "")
EMAIL_FROM = os.getenv("EMAIL_FROM", "Omoide no Wa <onboarding@resend.dev>")
APP_BASE_URL = os.getenv("APP_BASE_URL", "https://omoidenowa.com").rstrip("/")


def email_enabled() -> bool:
    return bool(RESEND_API_KEY)


def send_email(to: str, subject: str, html_body: str) -> bool:
    """Sends an email. Returns True if it was handed to Resend, False if email
    is not configured or the send failed (never raises, so a failed email can't
    break a request)."""
    if not RESEND_API_KEY:
        logger.info("Email skipped (RESEND_API_KEY unset): to=%s subject=%s", to, subject)
        return False
    try:
        response = httpx.post(
            "https://api.resend.com/emails",
            headers={"Authorization": f"Bearer {RESEND_API_KEY}"},
            json={"from": EMAIL_FROM, "to": [to], "subject": subject, "html": html_body},
            timeout=15.0,
        )
        if response.status_code >= 400:
            logger.warning("Resend error %s: %s", response.status_code, response.text[:300])
            return False
        return True
    except httpx.HTTPError as exc:  # network hiccup, DNS, timeout
        logger.warning("Resend request failed: %s", exc)
        return False


def _shell(title: str, body_html: str) -> str:
    return (
        '<div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;'
        'max-width:480px;margin:0 auto;padding:24px;color:#0F1B3D">'
        f'<h1 style="font-size:20px;margin:0 0 16px">{title}</h1>'
        f'{body_html}'
        '<p style="color:#6B7280;font-size:12px;margin-top:28px">Omoide no Wa — '
        "shared memories, beautifully kept.</p></div>"
    )


def send_password_reset(to: str, reset_url: str) -> bool:
    body = (
        "<p>We received a request to reset your Omoide no Wa password. "
        "Tap the button below to choose a new one. This link expires in 1 hour.</p>"
        f'<p style="margin:20px 0"><a href="{reset_url}" '
        'style="background:#FF8A3D;color:#fff;text-decoration:none;'
        'padding:11px 20px;border-radius:999px;font-weight:600">Reset password</a></p>'
        "<p style=\"color:#6B7280;font-size:13px\">If you didn't ask for this, you can ignore this email.</p>"
    )
    return send_email(to, "Reset your Omoide no Wa password", _shell("Reset your password", body))


def send_guest_verify_code(to: str, campaign_title: str, code: str) -> bool:
    body = (
        f'<p>Enter this code to add your photos to "{campaign_title}":</p>'
        f'<p style="font-size:30px;font-weight:700;letter-spacing:6px;margin:16px 0">{code}</p>'
        '<p style="color:#6B7280;font-size:13px">The code expires in 15 minutes.</p>'
    )
    return send_email(to, f"Your code for {campaign_title}", _shell("Confirm your email", body))

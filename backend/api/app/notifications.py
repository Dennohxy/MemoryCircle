from __future__ import annotations

import os
from functools import lru_cache
from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from .models import Notification, NotificationSubscription


@lru_cache(maxsize=1)
def firebase_ready() -> bool:
    """Initializes Firebase Admin if credentials are configured."""
    credentials_path = os.getenv("FIREBASE_CREDENTIALS")
    credentials_json = os.getenv("FIREBASE_CREDENTIALS_JSON")
    if not credentials_path and not credentials_json:
        return False
    try:
        import firebase_admin
        from firebase_admin import credentials

        if firebase_admin._apps:
            return True
        if credentials_json:
            import json

            cert = credentials.Certificate(json.loads(credentials_json))
        else:
            cert = credentials.Certificate(credentials_path)
        firebase_admin.initialize_app(cert)
        return True
    except Exception:
        return False


def send_fcm(
    *,
    token: str,
    title: str,
    body: str,
    data: dict[str, str],
) -> Optional[str]:
    if not firebase_ready():
        return None
    from firebase_admin import messaging

    return messaging.send(
        messaging.Message(
            token=token,
            notification=messaging.Notification(title=title, body=body),
            data=data,
        )
    )


def deliver_notification(db: Session, notification: Notification) -> int:
    """Attempts provider delivery for one queued notification.

    Returns the number of successful provider sends. If Firebase is not
    configured, the notification remains queued and visible in-app.
    """
    subscriptions = db.scalars(
        select(NotificationSubscription).where(
            NotificationSubscription.user_id == notification.user_id,
            NotificationSubscription.enabled == True,  # noqa: E712
        )
    ).all()
    delivered = 0
    for subscription in subscriptions:
        if subscription.provider != "fcm":
            continue
        try:
            message_id = send_fcm(
                token=subscription.endpoint,
                title=notification.title,
                body=notification.body,
                data={
                    "type": notification.type,
                    "circle_id": str(notification.circle_id),
                    "target_type": notification.target_type,
                    "target_id": str(notification.target_id or ""),
                },
            )
            if message_id:
                delivered += 1
        except Exception:
            subscription.enabled = False
    if delivered:
        notification.delivery_status = "sent"
    elif firebase_ready():
        notification.delivery_status = "no_active_subscription"
    else:
        notification.delivery_status = "queued"
    return delivered

from __future__ import annotations

import hashlib
import json
import os
import secrets
import shutil
from datetime import datetime, timedelta
from io import BytesIO
from pathlib import Path
from typing import Optional

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, Response, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse
from PIL import Image
from pydantic import BaseModel, EmailStr
from sqlalchemy import and_, delete, inspect as sa_inspect, or_, select, text
from sqlalchemy.orm import Session

from .auth import create_access_token, current_user, hash_password, verify_password
from .database import Base, engine, get_db
from .models import (
    ActivityLog,
    Album,
    AlbumPage,
    CircleMember,
    MemoryCircle,
    MemoryItem,
    Notification,
    NotificationSubscription,
    PhotoAsset,
    PhotoSource,
    SharePackage,
    User,
)
from .notifications import deliver_notification


STORAGE_ROOT = Path(os.getenv("STORAGE_ROOT", "storage")).resolve()
# "disk" keeps image files under STORAGE_ROOT (local development).
# "db" stores image bytes in the database, which survives restarts on
# free-tier hosts whose local disks are ephemeral.
ASSET_STORAGE = os.getenv("ASSET_STORAGE", "disk").lower()
ALLOWED_IMAGE_TYPES = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}
ROLE_ORDER = {"viewer": 0, "contributor": 1, "approver": 2, "owner": 3}
WRITE_ROLES = {"owner", "approver", "contributor"}
APPROVE_ROLES = {"owner", "approver"}
FIRST_VIEW_ASSET_GRACE = timedelta(minutes=30)

app = FastAPI(title="Memory Circle API", version="0.1.0")

# The Flutter web client is served from a different local port, so browsers
# send CORS preflight requests that must be answered here.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
# Compress JSON responses so lists of memories/albums travel smaller.
app.add_middleware(GZipMiddleware, minimum_size=600)


def ensure_asset_blob_columns():
    """Adds the blob columns to databases created before they existed."""
    inspector = sa_inspect(engine)
    if "photo_assets" not in inspector.get_table_names():
        return
    existing = {column["name"] for column in inspector.get_columns("photo_assets")}
    blob_type = "BYTEA" if engine.dialect.name.startswith("postgres") else "BLOB"
    with engine.begin() as connection:
        for column_name in ("thumbnail_blob", "display_blob"):
            if column_name not in existing:
                connection.execute(text(f"ALTER TABLE photo_assets ADD COLUMN {column_name} {blob_type}"))


def ensure_album_removal_columns():
    """Adds album workflow columns to databases created before them."""
    inspector = sa_inspect(engine)
    if "albums" not in inspector.get_table_names():
        return
    existing = {column["name"] for column in inspector.get_columns("albums")}
    additions = {
        "status": "VARCHAR(40) DEFAULT 'active'",
        "removal_requested_by": "INTEGER",
        "removal_votes_json": "TEXT DEFAULT '[]'",
        "target_photo_count": "INTEGER DEFAULT 24",
        "cover_memory_id": "INTEGER",
        "memory_sequence_json": "TEXT DEFAULT '[]'",
    }
    with engine.begin() as connection:
        for column_name, definition in additions.items():
            if column_name not in existing:
                connection.execute(text(f"ALTER TABLE albums ADD COLUMN {column_name} {definition}"))


def ensure_memory_approval_columns():
    """Adds consensus approval columns to databases created before them."""
    inspector = sa_inspect(engine)
    if "memory_items" not in inspector.get_table_names():
        return
    existing = {column["name"] for column in inspector.get_columns("memory_items")}
    with engine.begin() as connection:
        if "approval_votes_json" not in existing:
            connection.execute(text("ALTER TABLE memory_items ADD COLUMN approval_votes_json TEXT DEFAULT '[]'"))


def ensure_notification_tables():
    """Creates notification tables for databases created before them."""
    Base.metadata.tables["notification_subscriptions"].create(bind=engine, checkfirst=True)
    Base.metadata.tables["notifications"].create(bind=engine, checkfirst=True)


@app.on_event("startup")
def startup():
    Base.metadata.create_all(bind=engine)
    ensure_asset_blob_columns()
    ensure_album_removal_columns()
    ensure_memory_approval_columns()
    ensure_notification_tables()
    STORAGE_ROOT.mkdir(parents=True, exist_ok=True)


class UserIn(BaseModel):
    display_name: str
    email: EmailStr
    password: str


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class CircleIn(BaseModel):
    name: str
    description: str = ""
    default_approval_required: bool = True


class CirclePatch(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    default_approval_required: Optional[bool] = None


class InviteIn(BaseModel):
    email: EmailStr
    display_name: str = ""
    role: str = "contributor"


class MemberPatch(BaseModel):
    role: Optional[str] = None
    status: Optional[str] = None


class MemoryIn(BaseModel):
    asset_id: int
    caption: str
    story: str = ""
    event_name: str = ""
    memory_date: Optional[datetime] = None
    location_text: str = ""
    people_json: list[str] = []
    approval_status: str = "draft"


class MemoryPatch(BaseModel):
    caption: Optional[str] = None
    story: Optional[str] = None
    event_name: Optional[str] = None
    memory_date: Optional[datetime] = None
    location_text: Optional[str] = None
    people_json: Optional[list[str]] = None


class AlbumIn(BaseModel):
    title: str
    description: str = ""
    template_key: str = "classic"
    target_photo_count: int = 24
    cover_memory_id: Optional[int] = None
    memory_sequence: list[int] = []


class SharePackageIn(BaseModel):
    title: Optional[str] = None
    note: str = ""
    access_type: str = "expires_at"
    expires_at: Optional[datetime] = None
    allow_downloads: bool = False
    include_captions: bool = True
    page_ids: list[int] = []


class AssetMatchIn(BaseModel):
    hashes: list[str]


class AlbumPatch(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    target_photo_count: Optional[int] = None
    cover_memory_id: Optional[int] = None
    memory_sequence: Optional[list[int]] = None


class PagePatch(BaseModel):
    layout_json: dict
    approval_status: str = "approved"


class NotificationSubscriptionIn(BaseModel):
    provider: str = "local"
    endpoint: str
    device_label: str = ""


def user_public(user: User):
    return {"id": user.id, "display_name": user.display_name, "email": user.email}


def member_for(db: Session, circle_id: int, user_id: int) -> Optional[CircleMember]:
    return db.scalar(
        select(CircleMember).where(
            CircleMember.circle_id == circle_id,
            CircleMember.user_id == user_id,
            CircleMember.status == "active",
        )
    )


def require_member(db: Session, circle_id: int, user: User, allowed: Optional[set[str]] = None) -> CircleMember:
    member = member_for(db, circle_id, user.id)
    if not member:
        raise HTTPException(status_code=403, detail="You are not a member of this circle")
    if allowed and member.role not in allowed:
        raise HTTPException(status_code=403, detail="Your role cannot perform this action")
    return member


def require_min_role(db: Session, circle_id: int, user: User, minimum: str) -> CircleMember:
    member = require_member(db, circle_id, user)
    if ROLE_ORDER[member.role] < ROLE_ORDER[minimum]:
        raise HTTPException(status_code=403, detail="Your role cannot perform this action")
    return member


def log_activity(db: Session, circle_id: int, actor_id: int, action: str, target_type: str, target_id: int, details=None):
    db.add(
        ActivityLog(
            circle_id=circle_id,
            actor_user_id=actor_id,
            action_type=action,
            target_type=target_type,
            target_id=target_id,
            details_json=json.dumps(details or {}),
        )
    )


def serialize_circle(circle: MemoryCircle):
    return {
        "id": circle.id,
        "name": circle.name,
        "description": circle.description,
        "owner_user_id": circle.owner_user_id,
        "default_approval_required": circle.default_approval_required,
        "created_at": circle.created_at,
        "updated_at": circle.updated_at,
    }


def serialize_member(member: CircleMember):
    return {
        "id": member.id,
        "circle_id": member.circle_id,
        "user_id": member.user_id,
        "role": member.role,
        "status": member.status,
        "invited_by": member.invited_by,
        "user": user_public(member.user) if member.user else None,
    }


def serialize_asset(asset: PhotoAsset):
    return {
        "id": asset.id,
        "circle_id": asset.circle_id,
        "source_id": asset.source_id,
        "source_type": asset.source_type,
        "source_reference": asset.source_reference,
        "content_hash": asset.content_hash,
        "original_filename": asset.original_filename,
        "mime_type": asset.mime_type,
        "file_size": asset.file_size,
        "width": asset.width,
        "height": asset.height,
        "capture_date": asset.capture_date,
        "thumbnail_url": f"/circles/{asset.circle_id}/assets/{asset.id}/thumbnail",
        "display_url": f"/circles/{asset.circle_id}/assets/{asset.id}/display",
        "cache_status": asset.cache_status,
        "availability_status": asset.availability_status,
    }


def serialize_uploaded_photo(asset: PhotoAsset, memory: Optional[MemoryItem] = None, approvals_needed: Optional[int] = None):
    return {
        "asset": serialize_asset(asset),
        "memory": serialize_memory(memory, approvals_needed=approvals_needed) if memory else None,
    }


def serialize_memory(memory: MemoryItem, approvals_needed: Optional[int] = None):
    votes = json.loads(getattr(memory, "approval_votes_json", None) or "[]")
    needed = approvals_needed if approvals_needed is not None else len(votes)
    return {
        "id": memory.id,
        "circle_id": memory.circle_id,
        "asset_id": memory.asset_id,
        "caption": memory.caption,
        "story": memory.story,
        "event_name": memory.event_name,
        "memory_date": memory.memory_date,
        "location_text": memory.location_text,
        "people_json": json.loads(memory.people_json or "[]"),
        "submitted_by": memory.submitted_by,
        "approval_status": memory.approval_status,
        "approval_votes": votes,
        "approval": {
            "approvals_have": len(votes),
            "approvals_needed": needed,
            "voter_ids": votes,
        },
        "approved_by": memory.approved_by,
        "approved_at": memory.approved_at,
        "asset": serialize_asset(memory.asset) if memory.asset else None,
    }


def serialize_album(album: Album, pages: Optional[list[AlbumPage]] = None, approvals_needed: Optional[int] = None):
    status = getattr(album, "status", None) or "active"
    votes = json.loads(getattr(album, "removal_votes_json", None) or "[]")
    data = {
        "id": album.id,
        "circle_id": album.circle_id,
        "title": album.title,
        "description": album.description,
        "template_key": album.template_key,
        "target_photo_count": getattr(album, "target_photo_count", None) or 24,
        "cover_memory_id": getattr(album, "cover_memory_id", None),
        "memory_sequence": json.loads(getattr(album, "memory_sequence_json", None) or "[]"),
        "created_by": album.created_by,
        "status": status,
        "removal": {
            "requested_by": album.removal_requested_by,
            "approvals_have": len(votes),
            "approvals_needed": approvals_needed if approvals_needed is not None else len(votes),
            "voter_ids": votes,
        }
        if status == "pending_removal"
        else None,
    }
    if pages is not None:
        data["pages"] = [serialize_page(page) for page in pages]
    return data


def serialize_page(page: AlbumPage):
    return {
        "id": page.id,
        "album_id": page.album_id,
        "page_number": page.page_number,
        "layout_json": json.loads(page.layout_json),
        "version": page.version,
        "approval_status": page.approval_status,
    }


def share_url(request: Request, package: SharePackage):
    return str(request.url_for("get_public_share_package", token=package.token))


def share_status(package: SharePackage):
    if package.revoked_at:
        return "revoked"
    if package.expires_at and package.expires_at <= datetime.utcnow():
        return "expired"
    if package.access_type == "expires_after_view" and package.viewed_at:
        return "viewed"
    return "active"


def serialize_share_package(package: SharePackage, request: Request):
    return {
        "id": package.id,
        "circle_id": package.circle_id,
        "album_id": package.album_id,
        "title": package.title,
        "note": package.note,
        "access_type": package.access_type,
        "expires_at": package.expires_at,
        "allow_downloads": package.allow_downloads,
        "include_captions": package.include_captions,
        "page_ids": json.loads(package.page_ids_json or "[]"),
        "status": share_status(package),
        "share_url": share_url(request, package),
        "created_at": package.created_at,
        "revoked_at": package.revoked_at,
        "viewed_at": package.viewed_at,
    }


def require_active_share_package(db: Session, token: str):
    package = db.scalar(select(SharePackage).where(SharePackage.token == token))
    if not package or package.revoked_at:
        raise HTTPException(status_code=404, detail="This share package is no longer available")
    if package.expires_at and package.expires_at <= datetime.utcnow():
        raise HTTPException(status_code=410, detail="This share package has expired")
    if package.access_type == "expires_after_view" and package.viewed_at:
        raise HTTPException(status_code=410, detail="This share package has already been viewed")
    return package


def share_pages(db: Session, package: SharePackage):
    query = select(AlbumPage).where(AlbumPage.album_id == package.album_id)
    page_ids = json.loads(package.page_ids_json or "[]")
    if page_ids:
        query = query.where(AlbumPage.id.in_(page_ids))
    return db.scalars(query.order_by(AlbumPage.page_number)).all()


def page_asset_ids(pages: list[AlbumPage]):
    asset_ids: set[int] = set()
    for page in pages:
        layout = json.loads(page.layout_json)
        for memory in layout.get("memories", []):
            asset_id = memory.get("asset_id")
            if isinstance(asset_id, int):
                asset_ids.add(asset_id)
    return asset_ids


def serialize_public_share(package: SharePackage, album: Album, pages: list[AlbumPage], request: Request):
    token = package.token
    serialized_pages = []
    for page in pages:
        data = serialize_page(page)
        layout = data["layout_json"]
        for memory in layout.get("memories", []):
            asset_id = memory.get("asset_id")
            if isinstance(asset_id, int):
                memory["display_url"] = str(request.url_for("get_public_share_asset", token=token, asset_id=asset_id, variant="display"))
                memory["thumbnail_url"] = str(request.url_for("get_public_share_asset", token=token, asset_id=asset_id, variant="thumbnail"))
            if not package.include_captions:
                memory["caption"] = ""
                memory["story_preview"] = ""
        serialized_pages.append(data)
    return {
        "title": package.title,
        "note": package.note,
        "album": serialize_album(album),
        "allow_downloads": package.allow_downloads,
        "include_captions": package.include_captions,
        "expires_at": package.expires_at,
        "pages": serialized_pages,
    }


def parse_form_datetime(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    return datetime.fromisoformat(value)


def parse_exif_datetime(value) -> Optional[datetime]:
    if not value:
        return None
    text_value = value.decode(errors="ignore") if isinstance(value, bytes) else str(value)
    for fmt in ("%Y:%m:%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(text_value.strip(), fmt)
        except ValueError:
            continue
    return None


def image_capture_date(image: Image.Image) -> Optional[datetime]:
    try:
        exif = image.getexif()
    except Exception:
        return None
    for tag in (36867, 36868, 306):
        parsed = parse_exif_datetime(exif.get(tag))
        if parsed:
            return parsed
    return None


def active_member_ids(db: Session, circle_id: int) -> list[int]:
    members = db.scalars(
        select(CircleMember).where(
            CircleMember.circle_id == circle_id,
            CircleMember.status == "active",
        )
    ).all()
    return sorted(member.user_id for member in members)


def approval_progress(db: Session, memory: MemoryItem):
    needed_ids = active_member_ids(db, memory.circle_id)
    votes = sorted(set(json.loads(getattr(memory, "approval_votes_json", None) or "[]")))
    return {
        "approvals_have": len(set(votes).intersection(needed_ids)),
        "approvals_needed": len(needed_ids),
        "voter_ids": votes,
    }


def apply_memory_vote(db: Session, memory: MemoryItem, user_id: int):
    needed_ids = set(active_member_ids(db, memory.circle_id))
    votes = set(json.loads(getattr(memory, "approval_votes_json", None) or "[]"))
    votes.add(user_id)
    memory.approval_votes_json = json.dumps(sorted(votes))
    if needed_ids and needed_ids.issubset(votes):
        memory.approval_status = "approved"
        memory.approved_by = user_id
        memory.approved_at = datetime.utcnow()
    else:
        memory.approval_status = "pending"


def queue_notification(
    db: Session,
    *,
    user_id: int,
    circle_id: int,
    type: str,
    title: str,
    body: str,
    target_type: str,
    target_id: int,
):
    existing = db.scalar(
        select(Notification).where(
            Notification.user_id == user_id,
            Notification.circle_id == circle_id,
            Notification.type == type,
            Notification.target_type == target_type,
            Notification.target_id == target_id,
            Notification.read_at.is_(None),
        )
    )
    if existing:
        return existing
    notification = Notification(
        user_id=user_id,
        circle_id=circle_id,
        type=type,
        title=title,
        body=body,
        target_type=target_type,
        target_id=target_id,
    )
    db.add(notification)
    db.flush()
    deliver_notification(db, notification)
    return notification


def queue_approval_notifications(db: Session, memory: MemoryItem):
    votes = set(json.loads(getattr(memory, "approval_votes_json", None) or "[]"))
    queued = 0
    for user_id in active_member_ids(db, memory.circle_id):
        if user_id in votes:
            continue
        queue_notification(
            db,
            user_id=user_id,
            circle_id=memory.circle_id,
            type="photo_approval_needed",
            title="Photo waiting for approval",
            body="A family photo needs your approval before it can enter the album.",
            target_type="memory",
            target_id=memory.id,
        )
        queued += 1
    return queued


def serialize_notification(notification: Notification):
    return {
        "id": notification.id,
        "user_id": notification.user_id,
        "circle_id": notification.circle_id,
        "type": notification.type,
        "title": notification.title,
        "body": notification.body,
        "target_type": notification.target_type,
        "target_id": notification.target_id,
        "delivery_status": notification.delivery_status,
        "read_at": notification.read_at,
        "created_at": notification.created_at,
    }


def serialize_subscription(subscription: NotificationSubscription):
    return {
        "id": subscription.id,
        "user_id": subscription.user_id,
        "provider": subscription.provider,
        "endpoint": subscription.endpoint,
        "device_label": subscription.device_label,
        "enabled": subscription.enabled,
        "created_at": subscription.created_at,
    }


@app.post("/auth/register")
def register(payload: UserIn, db: Session = Depends(get_db)):
    if db.scalar(select(User).where(User.email == payload.email.lower())):
        raise HTTPException(status_code=409, detail="Email already registered")
    user = User(
        display_name=payload.display_name.strip(),
        email=payload.email.lower(),
        password_hash=hash_password(payload.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return {"token": create_access_token(user), "user": user_public(user)}


@app.post("/auth/login")
def login(payload: LoginIn, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == payload.email.lower()))
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    return {"token": create_access_token(user), "user": user_public(user)}


@app.get("/me")
def me(user: User = Depends(current_user)):
    return user_public(user)


@app.post("/me/notification-subscriptions")
def upsert_notification_subscription(
    payload: NotificationSubscriptionIn,
    db: Session = Depends(get_db),
    user: User = Depends(current_user),
):
    subscription = db.scalar(
        select(NotificationSubscription).where(
            NotificationSubscription.user_id == user.id,
            NotificationSubscription.provider == payload.provider,
            NotificationSubscription.endpoint == payload.endpoint,
        )
    )
    if not subscription:
        subscription = NotificationSubscription(
            user_id=user.id,
            provider=payload.provider,
            endpoint=payload.endpoint,
            device_label=payload.device_label,
        )
        db.add(subscription)
    else:
        subscription.enabled = True
        subscription.device_label = payload.device_label
    db.commit()
    db.refresh(subscription)
    return serialize_subscription(subscription)


@app.get("/me/notifications")
def list_my_notifications(
    unread_only: bool = True,
    db: Session = Depends(get_db),
    user: User = Depends(current_user),
):
    query = select(Notification).where(Notification.user_id == user.id)
    if unread_only:
        query = query.where(Notification.read_at.is_(None))
    notifications = db.scalars(query.order_by(Notification.created_at.desc())).all()
    return [serialize_notification(notification) for notification in notifications]


@app.post("/me/notifications/{notification_id}/read")
def mark_notification_read(
    notification_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(current_user),
):
    notification = db.get(Notification, notification_id)
    if not notification or notification.user_id != user.id:
        raise HTTPException(status_code=404, detail="Notification not found")
    notification.read_at = datetime.utcnow()
    db.commit()
    return serialize_notification(notification)


@app.post("/circles")
def create_circle(payload: CircleIn, db: Session = Depends(get_db), user: User = Depends(current_user)):
    circle = MemoryCircle(
        name=payload.name,
        description=payload.description,
        owner_user_id=user.id,
        default_approval_required=payload.default_approval_required,
    )
    db.add(circle)
    db.flush()
    db.add(CircleMember(circle_id=circle.id, user_id=user.id, role="owner", status="active", invited_by=user.id))
    log_activity(db, circle.id, user.id, "circle.created", "circle", circle.id, {"name": circle.name})
    db.commit()
    db.refresh(circle)
    return serialize_circle(circle)


@app.get("/circles")
def list_circles(db: Session = Depends(get_db), user: User = Depends(current_user)):
    rows = db.scalars(
        select(MemoryCircle)
        .join(CircleMember, CircleMember.circle_id == MemoryCircle.id)
        .where(CircleMember.user_id == user.id, CircleMember.status == "active")
        .order_by(MemoryCircle.created_at.desc())
    ).all()
    return [serialize_circle(row) for row in rows]


@app.get("/circles/{circle_id}")
def get_circle(circle_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user)
    circle = db.get(MemoryCircle, circle_id)
    if not circle:
        raise HTTPException(status_code=404, detail="Circle not found")
    return serialize_circle(circle)


@app.patch("/circles/{circle_id}")
def patch_circle(circle_id: int, payload: CirclePatch, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user, {"owner"})
    circle = db.get(MemoryCircle, circle_id)
    if not circle:
        raise HTTPException(status_code=404, detail="Circle not found")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(circle, field, value)
    log_activity(db, circle_id, user.id, "circle.updated", "circle", circle_id, payload.model_dump(exclude_unset=True))
    db.commit()
    return serialize_circle(circle)


@app.post("/circles/{circle_id}/invites")
def invite_member(circle_id: int, payload: InviteIn, db: Session = Depends(get_db), user: User = Depends(current_user)):
    if payload.role not in ROLE_ORDER:
        raise HTTPException(status_code=400, detail="Invalid role")
    require_member(db, circle_id, user, {"owner"})
    invited = db.scalar(select(User).where(User.email == payload.email.lower()))
    if not invited:
        invited = User(
            display_name=payload.display_name or payload.email.split("@")[0],
            email=payload.email.lower(),
            password_hash=hash_password("ChangeMe123!"),
        )
        db.add(invited)
        db.flush()
    member = member_for(db, circle_id, invited.id)
    if not member:
        member = CircleMember(circle_id=circle_id, user_id=invited.id, role=payload.role, status="active", invited_by=user.id)
        db.add(member)
    else:
        member.role = payload.role
        member.status = "active"
    log_activity(db, circle_id, user.id, "member.invited", "member", invited.id, {"role": payload.role})
    db.commit()
    db.refresh(member)
    return serialize_member(member)


@app.get("/circles/{circle_id}/members")
def list_members(circle_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user)
    members = db.scalars(select(CircleMember).where(CircleMember.circle_id == circle_id)).all()
    return [serialize_member(member) for member in members]


@app.patch("/circles/{circle_id}/members/{member_id}")
def patch_member(circle_id: int, member_id: int, payload: MemberPatch, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user, {"owner"})
    member = db.get(CircleMember, member_id)
    if not member or member.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Member not found")
    if payload.role:
        if payload.role not in ROLE_ORDER:
            raise HTTPException(status_code=400, detail="Invalid role")
        member.role = payload.role
    if payload.status:
        member.status = payload.status
    log_activity(db, circle_id, user.id, "member.updated", "member", member_id, payload.model_dump(exclude_unset=True))
    db.commit()
    return serialize_member(member)


@app.post("/circles/{circle_id}/assets/upload")
def upload_asset(
    circle_id: int,
    file: UploadFile = File(...),
    source_type: str = Form("local_upload"),
    capture_date: Optional[str] = Form(None),
    db: Session = Depends(get_db),
    user: User = Depends(current_user),
):
    require_member(db, circle_id, user, WRITE_ROLES)
    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=400, detail="Only JPEG, PNG, and WebP images are supported")
    raw = file.file.read()
    content_hash = hashlib.sha256(raw).hexdigest()
    existing = db.scalar(
        select(PhotoAsset).where(
            PhotoAsset.circle_id == circle_id,
            PhotoAsset.content_hash == content_hash,
        )
    )
    if existing:
        # Same photo already lives in this circle; reuse it instead of
        # storing a duplicate copy.
        return serialize_asset(existing)
    source = PhotoSource(user_id=user.id, source_type=source_type, source_name=file.filename or "Local upload")
    db.add(source)
    db.flush()
    try:
        with Image.open(BytesIO(raw)) as image:
            width, height = image.size
            detected_capture_date = image_capture_date(image)
            image.thumbnail((1600, 1600))
            display_io = BytesIO()
            image.convert("RGB").save(display_io, format="JPEG", quality=86)
        with Image.open(BytesIO(raw)) as image:
            image.thumbnail((360, 360))
            thumbnail_io = BytesIO()
            image.convert("RGB").save(thumbnail_io, format="JPEG", quality=82)
    except Exception:
        raise HTTPException(status_code=400, detail="Uploaded file is not a readable image")
    display_bytes = display_io.getvalue()
    thumbnail_bytes = thumbnail_io.getvalue()

    thumbnail_path = ""
    display_path = ""
    thumbnail_blob = None
    display_blob = None
    if ASSET_STORAGE == "db":
        thumbnail_blob = thumbnail_bytes
        display_blob = display_bytes
    else:
        circle_dir = STORAGE_ROOT / str(circle_id)
        circle_dir.mkdir(parents=True, exist_ok=True)
        extension = ALLOWED_IMAGE_TYPES[file.content_type]
        base_name = f"{content_hash[:20]}"
        (circle_dir / f"{base_name}-source{extension}").write_bytes(raw)
        thumbnail_file = circle_dir / f"{base_name}-thumb.jpg"
        display_file = circle_dir / f"{base_name}-display.jpg"
        thumbnail_file.write_bytes(thumbnail_bytes)
        display_file.write_bytes(display_bytes)
        thumbnail_path = str(thumbnail_file)
        display_path = str(display_file)

    asset = PhotoAsset(
        circle_id=circle_id,
        source_id=source.id,
        source_type=source_type,
        source_reference=f"upload:{content_hash}",
        content_hash=content_hash,
        original_filename=file.filename or "upload",
        mime_type=file.content_type or "application/octet-stream",
        file_size=len(raw),
        width=width,
        height=height,
        capture_date=parse_form_datetime(capture_date) or detected_capture_date,
        thumbnail_path=thumbnail_path,
        display_path=display_path,
        thumbnail_blob=thumbnail_blob,
        display_blob=display_blob,
        created_by=user.id,
    )
    db.add(asset)
    db.flush()
    log_activity(db, circle_id, user.id, "asset.uploaded", "asset", asset.id, {"filename": asset.original_filename})
    db.commit()
    db.refresh(asset)
    return serialize_asset(asset)


@app.post("/circles/{circle_id}/assets/match")
def match_assets(circle_id: int, payload: AssetMatchIn, db: Session = Depends(get_db), user: User = Depends(current_user)):
    """Returns circle assets whose content hash matches, so clients can link
    photos that already exist instead of uploading duplicate copies."""
    require_member(db, circle_id, user, WRITE_ROLES)
    if not payload.hashes:
        return {"matches": {}}
    rows = db.scalars(
        select(PhotoAsset).where(
            PhotoAsset.circle_id == circle_id,
            PhotoAsset.content_hash.in_(payload.hashes),
        )
    ).all()
    return {"matches": {asset.content_hash: serialize_asset(asset) for asset in rows}}


@app.get("/circles/{circle_id}/photos")
def list_uploaded_photos(circle_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user)
    assets = db.scalars(select(PhotoAsset).where(PhotoAsset.circle_id == circle_id).order_by(PhotoAsset.created_at.desc())).all()
    memories = db.scalars(select(MemoryItem).where(MemoryItem.circle_id == circle_id)).all()
    memory_by_asset = {memory.asset_id: memory for memory in memories}
    approvals_needed = len(active_member_ids(db, circle_id))
    return [
        serialize_uploaded_photo(asset, memory_by_asset.get(asset.id), approvals_needed=approvals_needed)
        for asset in assets
    ]


@app.post("/circles/{circle_id}/photos/send-for-approval")
def send_unapproved_photos_for_approval(circle_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user, WRITE_ROLES)
    memories = db.scalars(
        select(MemoryItem).where(
            MemoryItem.circle_id == circle_id,
            MemoryItem.approval_status.in_(["draft", "pending", "changes_requested"]),
        )
    ).all()
    sent = 0
    already_pending = 0
    notifications_queued = 0
    for memory in memories:
        before = memory.approval_status
        if before != "pending":
            memory.approval_status = "pending"
            sent += 1
        else:
            already_pending += 1
        notifications_queued += queue_approval_notifications(db, memory)
    log_activity(
        db,
        circle_id,
        user.id,
        "photos.sent_for_approval",
        "circle",
        circle_id,
        {
            "sent": sent,
            "already_pending": already_pending,
            "notifications_queued": notifications_queued,
        },
    )
    db.commit()
    return {
        "sent": sent,
        "already_pending": already_pending,
        "notifications_queued": notifications_queued,
    }


def send_asset_file(circle_id: int, asset_id: int, variant: str, db: Session, user: User, request: Request):
    require_member(db, circle_id, user)
    asset = db.get(PhotoAsset, asset_id)
    if not asset or asset.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Asset not found")
    # Each processed image is derived from immutable content, so it can be
    # cached hard by the browser and revalidated cheaply with an ETag.
    etag = f'"{asset.content_hash}-{variant}"'
    cache_headers = {
        "Cache-Control": "private, max-age=31536000, immutable",
        "ETag": etag,
    }
    if_none_match = request.headers.get("if-none-match")
    if if_none_match and etag in {tag.strip() for tag in if_none_match.split(",")}:
        return Response(status_code=304, headers=cache_headers)
    blob = asset.thumbnail_blob if variant == "thumbnail" else asset.display_blob
    if blob is not None:
        return Response(content=blob, media_type="image/jpeg", headers=cache_headers)
    path = Path(asset.thumbnail_path if variant == "thumbnail" else asset.display_path)
    if not str(path) or not path.exists():
        raise HTTPException(status_code=404, detail="Asset file missing")
    return FileResponse(path, media_type="image/jpeg", headers=cache_headers)


@app.get("/circles/{circle_id}/assets/{asset_id}/thumbnail")
def get_thumbnail(circle_id: int, asset_id: int, request: Request, db: Session = Depends(get_db), user: User = Depends(current_user)):
    return send_asset_file(circle_id, asset_id, "thumbnail", db, user, request)


@app.get("/circles/{circle_id}/assets/{asset_id}/display")
def get_display(circle_id: int, asset_id: int, request: Request, db: Session = Depends(get_db), user: User = Depends(current_user)):
    return send_asset_file(circle_id, asset_id, "display", db, user, request)


@app.post("/circles/{circle_id}/memories")
def create_memory(circle_id: int, payload: MemoryIn, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user, WRITE_ROLES)
    asset = db.get(PhotoAsset, payload.asset_id)
    if not asset or asset.circle_id != circle_id:
        raise HTTPException(status_code=400, detail="Asset does not belong to this circle")
    status = payload.approval_status
    if status not in {"draft", "pending"}:
        raise HTTPException(status_code=400, detail="New memories must start as draft or pending")
    memory = MemoryItem(
        circle_id=circle_id,
        asset_id=payload.asset_id,
        caption=payload.caption,
        story=payload.story,
        event_name=payload.event_name,
        memory_date=payload.memory_date or asset.capture_date,
        location_text=payload.location_text,
        people_json=json.dumps(payload.people_json),
        submitted_by=user.id,
        approval_status=status,
        approval_votes_json=json.dumps([user.id]) if status == "pending" else "[]",
    )
    if status == "pending":
        apply_memory_vote(db, memory, user.id)
    db.add(memory)
    db.flush()
    if memory.approval_status == "pending":
        queue_approval_notifications(db, memory)
    log_activity(db, circle_id, user.id, "memory.created", "memory", memory.id, {"status": status})
    db.commit()
    db.refresh(memory)
    return serialize_memory(memory, approvals_needed=len(active_member_ids(db, circle_id)))


@app.get("/circles/{circle_id}/memories")
def list_memories(circle_id: int, status: Optional[str] = None, db: Session = Depends(get_db), user: User = Depends(current_user)):
    member = require_member(db, circle_id, user)
    query = select(MemoryItem).where(MemoryItem.circle_id == circle_id)
    if member.role == "viewer":
        if status == "pending":
            query = query.where(MemoryItem.approval_status == "pending")
        else:
            query = query.where(MemoryItem.approval_status == "approved")
        if status and status not in {"approved", "pending"}:
            return []
    elif status:
        query = query.where(MemoryItem.approval_status == status)
    query = query.order_by(MemoryItem.memory_date.asc().nulls_last(), MemoryItem.created_at.asc())
    approvals_needed = len(active_member_ids(db, circle_id))
    return [serialize_memory(memory, approvals_needed=approvals_needed) for memory in db.scalars(query).all()]


@app.get("/circles/{circle_id}/memories/{memory_id}")
def get_memory(circle_id: int, memory_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    member = require_member(db, circle_id, user)
    memory = db.get(MemoryItem, memory_id)
    if not memory or memory.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Memory not found")
    if member.role == "viewer" and memory.approval_status not in {"approved", "pending"}:
        raise HTTPException(status_code=403, detail="Viewers can only see approved memories and memories waiting for approval")
    return serialize_memory(memory, approvals_needed=len(active_member_ids(db, circle_id)))


@app.patch("/circles/{circle_id}/memories/{memory_id}")
def patch_memory(circle_id: int, memory_id: int, payload: MemoryPatch, db: Session = Depends(get_db), user: User = Depends(current_user)):
    member = require_member(db, circle_id, user, WRITE_ROLES)
    memory = db.get(MemoryItem, memory_id)
    if not memory or memory.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Memory not found")
    if member.role == "contributor" and memory.submitted_by != user.id:
        raise HTTPException(status_code=403, detail="Contributors can edit only their own memories")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(memory, field, json.dumps(value) if field == "people_json" else value)
    log_activity(db, circle_id, user.id, "memory.updated", "memory", memory_id, payload.model_dump(exclude_unset=True))
    db.commit()
    return serialize_memory(memory, approvals_needed=len(active_member_ids(db, circle_id)))


@app.post("/circles/{circle_id}/memories/{memory_id}/submit")
def submit_memory(circle_id: int, memory_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    member = require_member(db, circle_id, user, WRITE_ROLES)
    memory = db.get(MemoryItem, memory_id)
    if not memory or memory.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Memory not found")
    if member.role == "contributor" and memory.submitted_by != user.id:
        raise HTTPException(status_code=403, detail="Contributors can submit only their own memories")
    apply_memory_vote(db, memory, user.id)
    queue_approval_notifications(db, memory)
    log_activity(db, circle_id, user.id, "memory.submitted", "memory", memory_id)
    db.commit()
    return serialize_memory(memory, approvals_needed=len(active_member_ids(db, circle_id)))


def approval_action(circle_id: int, memory_id: int, status: str, action: str, db: Session, user: User, patch: Optional[MemoryPatch] = None):
    member = require_member(db, circle_id, user)
    memory = db.get(MemoryItem, memory_id)
    if not memory or memory.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Memory not found")
    if status != "approved" and member.role not in APPROVE_ROLES:
        raise HTTPException(status_code=403, detail="Only reviewers can reject or request changes")
    if patch:
        if member.role not in APPROVE_ROLES:
            raise HTTPException(status_code=403, detail="Only reviewers can edit memories during approval")
        for field, value in patch.model_dump(exclude_unset=True).items():
            setattr(memory, field, json.dumps(value) if field == "people_json" else value)
    if status == "approved":
        apply_memory_vote(db, memory, user.id)
        action = "memory.approval_recorded" if memory.approval_status != "approved" else action
        if memory.approval_status == "pending":
            queue_approval_notifications(db, memory)
    else:
        memory.approval_status = status
    log_activity(db, circle_id, user.id, action, "memory", memory_id, {"status": status})
    db.commit()
    return serialize_memory(memory, approvals_needed=len(active_member_ids(db, circle_id)))


@app.post("/circles/{circle_id}/memories/{memory_id}/approve")
def approve_memory(circle_id: int, memory_id: int, patch: Optional[MemoryPatch] = None, db: Session = Depends(get_db), user: User = Depends(current_user)):
    return approval_action(circle_id, memory_id, "approved", "memory.approved", db, user, patch)


@app.post("/circles/{circle_id}/memories/{memory_id}/reject")
def reject_memory(circle_id: int, memory_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    return approval_action(circle_id, memory_id, "rejected", "memory.rejected", db, user)


@app.post("/circles/{circle_id}/memories/{memory_id}/request-changes")
def request_changes(circle_id: int, memory_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    return approval_action(circle_id, memory_id, "changes_requested", "memory.changes_requested", db, user)


@app.post("/circles/{circle_id}/albums")
def create_album(circle_id: int, payload: AlbumIn, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user, APPROVE_ROLES)
    if payload.target_photo_count < 1 or payload.target_photo_count > 200:
        raise HTTPException(status_code=400, detail="Choose an album size between 1 and 200 photos")
    album = Album(
        circle_id=circle_id,
        title=payload.title,
        description=payload.description,
        template_key=payload.template_key,
        target_photo_count=payload.target_photo_count,
        cover_memory_id=payload.cover_memory_id,
        memory_sequence_json=json.dumps(payload.memory_sequence),
        created_by=user.id,
    )
    db.add(album)
    db.flush()
    log_activity(db, circle_id, user.id, "album.created", "album", album.id, {"title": album.title})
    db.commit()
    db.refresh(album)
    return serialize_album(album)


@app.get("/circles/{circle_id}/albums")
def list_albums(circle_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user)
    albums = db.scalars(select(Album).where(Album.circle_id == circle_id).order_by(Album.created_at.desc())).all()
    approvals_needed = len(album_manager_ids(db, circle_id))
    return [serialize_album(album, approvals_needed=approvals_needed) for album in albums]


@app.get("/circles/{circle_id}/albums/{album_id}")
def get_album(circle_id: int, album_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user)
    album = db.get(Album, album_id)
    if not album or album.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Album not found")
    approvals_needed = len(album_manager_ids(db, circle_id))
    pages = db.scalars(select(AlbumPage).where(AlbumPage.album_id == album_id).order_by(AlbumPage.page_number)).all()
    return serialize_album(album, pages, approvals_needed=approvals_needed)


def album_manager_ids(db: Session, circle_id: int) -> list[int]:
    """User ids allowed to manage albums (owners and reviewers)."""
    members = db.scalars(
        select(CircleMember).where(
            CircleMember.circle_id == circle_id,
            CircleMember.status == "active",
        )
    ).all()
    return [member.user_id for member in members if member.role in APPROVE_ROLES]


def delete_album_record(db: Session, album: Album):
    db.execute(delete(AlbumPage).where(AlbumPage.album_id == album.id))
    db.delete(album)


@app.post("/circles/{circle_id}/albums/{album_id}/retire")
def request_album_retire(circle_id: int, album_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user, APPROVE_ROLES)
    album = db.get(Album, album_id)
    if not album or album.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Album not found")
    managers = set(album_manager_ids(db, circle_id))
    votes = {user.id}
    if votes >= managers:
        # The requester is the only album manager, so their approval is enough.
        delete_album_record(db, album)
        log_activity(db, circle_id, user.id, "album.removed", "album", album_id)
        db.commit()
        return {"status": "removed", "album_id": album_id}
    album.status = "pending_removal"
    album.removal_requested_by = user.id
    album.removal_votes_json = json.dumps(sorted(votes))
    log_activity(db, circle_id, user.id, "album.removal_requested", "album", album_id)
    db.commit()
    db.refresh(album)
    return serialize_album(album, approvals_needed=len(managers))


@app.post("/circles/{circle_id}/albums/{album_id}/retire/approve")
def approve_album_retire(circle_id: int, album_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user, APPROVE_ROLES)
    album = db.get(Album, album_id)
    if not album or album.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Album not found")
    if album.status != "pending_removal":
        raise HTTPException(status_code=400, detail="This album is not waiting to be removed")
    managers = set(album_manager_ids(db, circle_id))
    votes = set(json.loads(album.removal_votes_json or "[]"))
    votes.add(user.id)
    if votes >= managers:
        delete_album_record(db, album)
        log_activity(db, circle_id, user.id, "album.removed", "album", album_id)
        db.commit()
        return {"status": "removed", "album_id": album_id}
    album.removal_votes_json = json.dumps(sorted(votes))
    log_activity(db, circle_id, user.id, "album.removal_approved", "album", album_id)
    db.commit()
    db.refresh(album)
    return serialize_album(album, approvals_needed=len(managers))


@app.post("/circles/{circle_id}/albums/{album_id}/retire/cancel")
def cancel_album_retire(circle_id: int, album_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user, APPROVE_ROLES)
    album = db.get(Album, album_id)
    if not album or album.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Album not found")
    album.status = "active"
    album.removal_requested_by = None
    album.removal_votes_json = "[]"
    log_activity(db, circle_id, user.id, "album.removal_cancelled", "album", album_id)
    db.commit()
    db.refresh(album)
    return serialize_album(album)


@app.post("/circles/{circle_id}/albums/{album_id}/share-packages")
def create_share_package(
    circle_id: int,
    album_id: int,
    payload: SharePackageIn,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(current_user),
):
    require_member(db, circle_id, user, {"owner"})
    album = db.get(Album, album_id)
    if not album or album.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Album not found")
    if payload.access_type not in {"saved", "expires_at", "expires_after_view"}:
        raise HTTPException(status_code=400, detail="Choose a supported share package access type")
    if payload.access_type == "expires_at" and not payload.expires_at:
        raise HTTPException(status_code=400, detail="Choose when this share package should expire")
    pages = db.scalars(select(AlbumPage).where(AlbumPage.album_id == album_id)).all()
    available_page_ids = {page.id for page in pages}
    selected_page_ids = payload.page_ids or []
    if any(page_id not in available_page_ids for page_id in selected_page_ids):
        raise HTTPException(status_code=400, detail="One of those pages is not in this album")
    package = SharePackage(
        circle_id=circle_id,
        album_id=album_id,
        token=secrets.token_urlsafe(24),
        title=(payload.title or album.title).strip() or album.title,
        note=payload.note.strip(),
        access_type=payload.access_type,
        expires_at=payload.expires_at if payload.access_type == "expires_at" else None,
        allow_downloads=payload.allow_downloads,
        include_captions=payload.include_captions,
        page_ids_json=json.dumps(selected_page_ids),
        created_by=user.id,
    )
    db.add(package)
    db.flush()
    log_activity(db, circle_id, user.id, "share_package.created", "share_package", package.id, {"album_id": album_id})
    db.commit()
    db.refresh(package)
    return serialize_share_package(package, request)


@app.get("/circles/{circle_id}/albums/{album_id}/share-packages")
def list_share_packages(
    circle_id: int,
    album_id: int,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(current_user),
):
    require_member(db, circle_id, user, {"owner"})
    album = db.get(Album, album_id)
    if not album or album.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Album not found")
    packages = db.scalars(
        select(SharePackage)
        .where(SharePackage.circle_id == circle_id, SharePackage.album_id == album_id)
        .order_by(SharePackage.created_at.desc())
    ).all()
    return [serialize_share_package(package, request) for package in packages]


@app.post("/circles/{circle_id}/albums/{album_id}/share-packages/{package_id}/revoke")
def revoke_share_package(
    circle_id: int,
    album_id: int,
    package_id: int,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(current_user),
):
    require_member(db, circle_id, user, {"owner"})
    package = db.get(SharePackage, package_id)
    if not package or package.circle_id != circle_id or package.album_id != album_id:
        raise HTTPException(status_code=404, detail="Share package not found")
    if not package.revoked_at:
        package.revoked_at = datetime.utcnow()
        log_activity(db, circle_id, user.id, "share_package.revoked", "share_package", package.id, {"album_id": album_id})
    db.commit()
    return serialize_share_package(package, request)


@app.get("/share/{token}", name="get_public_share_package")
def get_public_share_package(token: str, request: Request, db: Session = Depends(get_db)):
    package = require_active_share_package(db, token)
    album = db.get(Album, package.album_id)
    if not album:
        raise HTTPException(status_code=404, detail="This share package is no longer available")
    pages = share_pages(db, package)
    payload = serialize_public_share(package, album, pages, request)
    if package.access_type == "expires_after_view":
        package.viewed_at = datetime.utcnow()
        db.commit()
    return payload


@app.get("/share/{token}/assets/{asset_id}/{variant}", name="get_public_share_asset")
def get_public_share_asset(token: str, asset_id: int, variant: str, db: Session = Depends(get_db)):
    if variant not in {"thumbnail", "display"}:
        raise HTTPException(status_code=404, detail="Asset not found")
    package = db.scalar(select(SharePackage).where(SharePackage.token == token))
    if not package or package.revoked_at:
        raise HTTPException(status_code=404, detail="This share package is no longer available")
    if package.expires_at and package.expires_at <= datetime.utcnow():
        raise HTTPException(status_code=410, detail="This share package has expired")
    if (
        package.access_type == "expires_after_view"
        and package.viewed_at
        and package.viewed_at + FIRST_VIEW_ASSET_GRACE <= datetime.utcnow()
    ):
        raise HTTPException(status_code=410, detail="This share package has expired")
    pages = share_pages(db, package)
    if asset_id not in page_asset_ids(pages):
        raise HTTPException(status_code=404, detail="Asset not found")
    asset = db.get(PhotoAsset, asset_id)
    if not asset or asset.circle_id != package.circle_id:
        raise HTTPException(status_code=404, detail="Asset not found")
    blob = asset.thumbnail_blob if variant == "thumbnail" else asset.display_blob
    if blob is not None:
        return Response(content=blob, media_type="image/jpeg")
    path = Path(asset.thumbnail_path if variant == "thumbnail" else asset.display_path)
    if not str(path) or not path.exists():
        raise HTTPException(status_code=404, detail="Asset file missing")
    return FileResponse(path, media_type="image/jpeg")


@app.patch("/circles/{circle_id}/albums/{album_id}")
def patch_album(circle_id: int, album_id: int, payload: AlbumPatch, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user, APPROVE_ROLES)
    album = db.get(Album, album_id)
    if not album or album.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Album not found")
    changes = payload.model_dump(exclude_unset=True)
    if "target_photo_count" in changes and changes["target_photo_count"] is not None:
        if changes["target_photo_count"] < 1 or changes["target_photo_count"] > 200:
            raise HTTPException(status_code=400, detail="Choose an album size between 1 and 200 photos")
    if payload.cover_memory_id is not None:
        cover = db.get(MemoryItem, payload.cover_memory_id)
        if not cover or cover.circle_id != circle_id or cover.approval_status != "approved":
            raise HTTPException(status_code=400, detail="Choose an approved memory from this circle as the cover")
    for field, value in changes.items():
        if field == "memory_sequence":
            approved_ids = {
                memory.id
                for memory in db.scalars(
                    select(MemoryItem).where(
                        MemoryItem.circle_id == circle_id,
                        MemoryItem.approval_status == "approved",
                    )
                ).all()
            }
            if any(memory_id not in approved_ids for memory_id in value):
                raise HTTPException(status_code=400, detail="Sequence can include only approved memories from this circle")
            album.memory_sequence_json = json.dumps(value)
        else:
            setattr(album, field, value)
    log_activity(db, circle_id, user.id, "album.updated", "album", album_id, changes)
    db.commit()
    db.refresh(album)
    return serialize_album(album)


def page_layout(page_number: int, memories: list[MemoryItem], template: str):
    return {
        "template": template,
        "page_number": page_number,
        "background": "#fff7ed",
        "image_fit": "contain",
        "memories": [
            {
                "memory_id": memory.id,
                "asset_id": memory.asset_id,
                "caption": memory.caption,
                "story_preview": memory.story[:220],
                "display_url": f"/circles/{memory.circle_id}/assets/{memory.asset_id}/display",
                "thumbnail_url": f"/circles/{memory.circle_id}/assets/{memory.asset_id}/thumbnail",
            }
            for memory in memories
        ],
    }


def ordered_album_memories(db: Session, circle_id: int, album: Album):
    approved = db.scalars(
        select(MemoryItem)
        .where(MemoryItem.circle_id == circle_id, MemoryItem.approval_status == "approved")
    ).all()
    by_id = {memory.id: memory for memory in approved}
    sequence = json.loads(getattr(album, "memory_sequence_json", None) or "[]")
    ordered = [by_id[memory_id] for memory_id in sequence if memory_id in by_id]
    sequenced_ids = set(sequence)
    remaining = [memory for memory in approved if memory.id not in sequenced_ids]
    remaining.sort(
        key=lambda memory: (
            memory.memory_date or (memory.asset.capture_date if memory.asset else None) or datetime.max,
            memory.approved_at or datetime.max,
            memory.created_at,
        )
    )
    ordered.extend(remaining)
    target = getattr(album, "target_photo_count", None) or 24
    return ordered[:target]


@app.post("/circles/{circle_id}/albums/{album_id}/pages/generate")
def generate_pages(circle_id: int, album_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user, APPROVE_ROLES)
    album = db.get(Album, album_id)
    if not album or album.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Album not found")
    db.execute(delete(AlbumPage).where(AlbumPage.album_id == album_id))
    memories = ordered_album_memories(db, circle_id, album)
    pages: list[AlbumPage] = []
    page_no = 1
    cover = db.get(MemoryItem, album.cover_memory_id) if getattr(album, "cover_memory_id", None) else (memories[0] if memories else None)
    title_layout = {"template": "event_title", "title": album.title, "description": album.description}
    if cover is not None:
        title_layout["cover"] = page_layout(0, [cover], "cover_photo")["memories"][0]
    title_page = AlbumPage(album_id=album.id, page_number=page_no, layout_json=json.dumps(title_layout), approval_status="approved")
    db.add(title_page)
    pages.append(title_page)
    page_no += 1
    index = 0
    templates = [("one_photo_feature", 1), ("two_photo_story", 2)]
    template_index = 0
    while index < len(memories):
        template, count = templates[template_index % len(templates)]
        group = memories[index : index + count]
        page = AlbumPage(album_id=album.id, page_number=page_no, layout_json=json.dumps(page_layout(page_no, group, template)), approval_status="approved")
        db.add(page)
        pages.append(page)
        page_no += 1
        index += len(group)
        template_index += 1
    log_activity(db, circle_id, user.id, "album.pages_generated", "album", album_id, {"page_count": len(pages)})
    db.commit()
    return [serialize_page(page) for page in pages]


@app.patch("/circles/{circle_id}/albums/{album_id}/pages/{page_id}")
def patch_page(circle_id: int, album_id: int, page_id: int, payload: PagePatch, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user, APPROVE_ROLES)
    album = db.get(Album, album_id)
    page = db.get(AlbumPage, page_id)
    if not album or album.circle_id != circle_id or not page or page.album_id != album_id:
        raise HTTPException(status_code=404, detail="Page not found")
    page.layout_json = json.dumps(payload.layout_json)
    page.approval_status = payload.approval_status
    page.version += 1
    log_activity(db, circle_id, user.id, "album.page_updated", "page", page_id)
    db.commit()
    return serialize_page(page)


@app.get("/circles/{circle_id}/activity")
def activity(circle_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user)
    logs = db.scalars(select(ActivityLog).where(ActivityLog.circle_id == circle_id).order_by(ActivityLog.created_at.desc())).all()
    return [
        {
            "id": item.id,
            "actor_user_id": item.actor_user_id,
            "action_type": item.action_type,
            "target_type": item.target_type,
            "target_id": item.target_id,
            "details_json": json.loads(item.details_json or "{}"),
            "created_at": item.created_at,
        }
        for item in logs
    ]


@app.get("/circles/{circle_id}/health")
def health(circle_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user)
    assets = db.scalars(select(PhotoAsset).where(PhotoAsset.circle_id == circle_id)).all()

    def ready(asset: PhotoAsset) -> bool:
        if asset.display_blob is not None and asset.thumbnail_blob is not None:
            return True
        return (
            bool(asset.display_path)
            and bool(asset.thumbnail_path)
            and Path(asset.display_path).exists()
            and Path(asset.thumbnail_path).exists()
        )

    missing = [asset.id for asset in assets if not ready(asset)]
    return {
        "circle_id": circle_id,
        "asset_count": len(assets),
        "missing_asset_ids": missing,
        "status": "healthy" if not missing else "attention_needed",
        "future_checks": ["source connector permissions", "archive device freshness", "peer recovery coverage"],
    }


@app.get("/health")
def api_health():
    return {"status": "ok", "storage_root": str(STORAGE_ROOT)}

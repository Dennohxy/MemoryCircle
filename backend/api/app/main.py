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
    PhotoAsset,
    PhotoSource,
    SharePackage,
    User,
)


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


@app.on_event("startup")
def startup():
    Base.metadata.create_all(bind=engine)
    ensure_asset_blob_columns()
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


class PagePatch(BaseModel):
    layout_json: dict
    approval_status: str = "approved"


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


def serialize_memory(memory: MemoryItem):
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
        "approved_by": memory.approved_by,
        "approved_at": memory.approved_at,
        "asset": serialize_asset(memory.asset) if memory.asset else None,
    }


def serialize_album(album: Album, pages: Optional[list[AlbumPage]] = None):
    data = {
        "id": album.id,
        "circle_id": album.circle_id,
        "title": album.title,
        "description": album.description,
        "template_key": album.template_key,
        "created_by": album.created_by,
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
        capture_date=parse_form_datetime(capture_date),
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
        memory_date=payload.memory_date,
        location_text=payload.location_text,
        people_json=json.dumps(payload.people_json),
        submitted_by=user.id,
        approval_status=status,
    )
    db.add(memory)
    db.flush()
    log_activity(db, circle_id, user.id, "memory.created", "memory", memory.id, {"status": status})
    db.commit()
    db.refresh(memory)
    return serialize_memory(memory)


@app.get("/circles/{circle_id}/memories")
def list_memories(circle_id: int, status: Optional[str] = None, db: Session = Depends(get_db), user: User = Depends(current_user)):
    member = require_member(db, circle_id, user)
    query = select(MemoryItem).where(MemoryItem.circle_id == circle_id)
    if member.role == "viewer":
        query = query.where(MemoryItem.approval_status == "approved")
        if status and status != "approved":
            return []
    elif status:
        query = query.where(MemoryItem.approval_status == status)
    query = query.order_by(MemoryItem.memory_date.asc().nulls_last(), MemoryItem.created_at.asc())
    return [serialize_memory(memory) for memory in db.scalars(query).all()]


@app.get("/circles/{circle_id}/memories/{memory_id}")
def get_memory(circle_id: int, memory_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    member = require_member(db, circle_id, user)
    memory = db.get(MemoryItem, memory_id)
    if not memory or memory.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Memory not found")
    if member.role == "viewer" and memory.approval_status != "approved":
        raise HTTPException(status_code=403, detail="Viewers can only see approved memories")
    return serialize_memory(memory)


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
    return serialize_memory(memory)


@app.post("/circles/{circle_id}/memories/{memory_id}/submit")
def submit_memory(circle_id: int, memory_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    member = require_member(db, circle_id, user, WRITE_ROLES)
    memory = db.get(MemoryItem, memory_id)
    if not memory or memory.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Memory not found")
    if member.role == "contributor" and memory.submitted_by != user.id:
        raise HTTPException(status_code=403, detail="Contributors can submit only their own memories")
    memory.approval_status = "pending"
    log_activity(db, circle_id, user.id, "memory.submitted", "memory", memory_id)
    db.commit()
    return serialize_memory(memory)


def approval_action(circle_id: int, memory_id: int, status: str, action: str, db: Session, user: User, patch: Optional[MemoryPatch] = None):
    require_member(db, circle_id, user, APPROVE_ROLES)
    memory = db.get(MemoryItem, memory_id)
    if not memory or memory.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Memory not found")
    if memory.submitted_by == user.id and not member_for(db, circle_id, user.id).role in APPROVE_ROLES:
        raise HTTPException(status_code=403, detail="Contributors cannot approve their own memory")
    if patch:
        for field, value in patch.model_dump(exclude_unset=True).items():
            setattr(memory, field, json.dumps(value) if field == "people_json" else value)
    memory.approval_status = status
    if status == "approved":
        memory.approved_by = user.id
        memory.approved_at = datetime.utcnow()
    log_activity(db, circle_id, user.id, action, "memory", memory_id, {"status": status})
    db.commit()
    return serialize_memory(memory)


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
    album = Album(circle_id=circle_id, title=payload.title, description=payload.description, template_key=payload.template_key, created_by=user.id)
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
    return [serialize_album(album) for album in albums]


@app.get("/circles/{circle_id}/albums/{album_id}")
def get_album(circle_id: int, album_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user)
    album = db.get(Album, album_id)
    if not album or album.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Album not found")
    pages = db.scalars(select(AlbumPage).where(AlbumPage.album_id == album_id).order_by(AlbumPage.page_number)).all()
    return serialize_album(album, pages)


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
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(album, field, value)
    log_activity(db, circle_id, user.id, "album.updated", "album", album_id, payload.model_dump(exclude_unset=True))
    db.commit()
    db.refresh(album)
    return serialize_album(album)


def page_layout(page_number: int, memories: list[MemoryItem], template: str):
    return {
        "template": template,
        "page_number": page_number,
        "background": "#fff7ed",
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


@app.post("/circles/{circle_id}/albums/{album_id}/pages/generate")
def generate_pages(circle_id: int, album_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    require_member(db, circle_id, user, APPROVE_ROLES)
    album = db.get(Album, album_id)
    if not album or album.circle_id != circle_id:
        raise HTTPException(status_code=404, detail="Album not found")
    db.execute(delete(AlbumPage).where(AlbumPage.album_id == album_id))
    memories = db.scalars(
        select(MemoryItem)
        .where(MemoryItem.circle_id == circle_id, MemoryItem.approval_status == "approved")
        .order_by(MemoryItem.memory_date.asc().nulls_last(), MemoryItem.approved_at.asc().nulls_last(), MemoryItem.created_at.asc())
    ).all()
    pages: list[AlbumPage] = []
    page_no = 1
    title_page = AlbumPage(album_id=album.id, page_number=page_no, layout_json=json.dumps({"template": "event_title", "title": album.title, "description": album.description}), approval_status="approved")
    db.add(title_page)
    pages.append(title_page)
    page_no += 1
    index = 0
    templates = [("one_photo_feature", 1), ("two_photo_story", 2), ("four_photo_grid", 4)]
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

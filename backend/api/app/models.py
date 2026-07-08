from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, LargeBinary, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


def now():
    return datetime.utcnow()


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    display_name: Mapped[str] = mapped_column(String(160))
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)


class MemoryCircle(Base):
    __tablename__ = "memory_circles"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    description: Mapped[str] = mapped_column(Text, default="")
    owner_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    default_approval_required: Mapped[bool] = mapped_column(Boolean, default=True)
    # "active" or "archived"; a circle is archived after it is merged away.
    status: Mapped[str] = mapped_column(String(40), default="active")
    merged_into_id: Mapped[Optional[int]] = mapped_column(ForeignKey("memory_circles.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)

    owner = relationship("User")


class CircleMember(Base):
    __tablename__ = "circle_members"
    __table_args__ = (UniqueConstraint("circle_id", "user_id", name="circle_user_unique"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    circle_id: Mapped[int] = mapped_column(ForeignKey("memory_circles.id"), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    role: Mapped[str] = mapped_column(String(40))
    status: Mapped[str] = mapped_column(String(40), default="active")
    invited_by: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)

    user = relationship("User", foreign_keys=[user_id])


class PhotoSource(Base):
    __tablename__ = "photo_sources"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    source_type: Mapped[str] = mapped_column(String(80), default="local_upload")
    source_name: Mapped[str] = mapped_column(String(200), default="Local upload")
    connection_status: Mapped[str] = mapped_column(String(80), default="available")
    permission_scope: Mapped[str] = mapped_column(String(160), default="single_upload")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    last_checked_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)


class PhotoAsset(Base):
    __tablename__ = "photo_assets"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    circle_id: Mapped[int] = mapped_column(ForeignKey("memory_circles.id"), index=True)
    source_id: Mapped[int] = mapped_column(ForeignKey("photo_sources.id"))
    source_type: Mapped[str] = mapped_column(String(80))
    source_reference: Mapped[str] = mapped_column(String(500))
    content_hash: Mapped[str] = mapped_column(String(128), index=True)
    original_filename: Mapped[str] = mapped_column(String(260))
    mime_type: Mapped[str] = mapped_column(String(100))
    file_size: Mapped[int] = mapped_column(Integer)
    width: Mapped[int] = mapped_column(Integer)
    height: Mapped[int] = mapped_column(Integer)
    capture_date: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    thumbnail_path: Mapped[str] = mapped_column(String(500), default="")
    display_path: Mapped[str] = mapped_column(String(500), default="")
    # Used when ASSET_STORAGE=db: image bytes live in the database so hosts
    # with ephemeral disks (free tiers) never lose uploads.
    thumbnail_blob: Mapped[Optional[bytes]] = mapped_column(LargeBinary, nullable=True)
    display_blob: Mapped[Optional[bytes]] = mapped_column(LargeBinary, nullable=True)
    cache_status: Mapped[str] = mapped_column(String(40), default="display_copy")
    availability_status: Mapped[str] = mapped_column(String(60), default="available")
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)


class MemoryItem(Base):
    __tablename__ = "memory_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    circle_id: Mapped[int] = mapped_column(ForeignKey("memory_circles.id"), index=True)
    asset_id: Mapped[int] = mapped_column(ForeignKey("photo_assets.id"))
    caption: Mapped[str] = mapped_column(String(280))
    story: Mapped[str] = mapped_column(Text, default="")
    event_name: Mapped[str] = mapped_column(String(200), default="")
    memory_date: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    location_text: Mapped[str] = mapped_column(String(200), default="")
    people_json: Mapped[str] = mapped_column(Text, default="[]")
    submitted_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    approval_status: Mapped[str] = mapped_column(String(60), default="draft", index=True)
    approval_votes_json: Mapped[str] = mapped_column(Text, default="[]")
    approved_by: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id"), nullable=True)
    approved_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)

    asset = relationship("PhotoAsset")


class CircleJoinRequest(Base):
    """A request from a signed-in person to be added to a circle they found
    by searching. The circle owner approves or declines it."""

    __tablename__ = "circle_join_requests"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    circle_id: Mapped[int] = mapped_column(ForeignKey("memory_circles.id"), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    status: Mapped[str] = mapped_column(String(40), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)


class CircleMergeRequest(Base):
    """A request from one circle's owner to merge their circle into another.
    The target circle's owner must accept before any content is moved."""

    __tablename__ = "circle_merge_requests"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    source_circle_id: Mapped[int] = mapped_column(ForeignKey("memory_circles.id"), index=True)
    target_circle_id: Mapped[int] = mapped_column(ForeignKey("memory_circles.id"), index=True)
    requested_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    status: Mapped[str] = mapped_column(String(40), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)


class CircleInviteLink(Base):
    """A shareable link that lets anyone who opens it join a circle."""

    __tablename__ = "circle_invite_links"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    circle_id: Mapped[int] = mapped_column(ForeignKey("memory_circles.id"), index=True)
    token: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    role: Mapped[str] = mapped_column(String(40), default="contributor")
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)


class Album(Base):
    __tablename__ = "albums"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    circle_id: Mapped[int] = mapped_column(ForeignKey("memory_circles.id"), index=True)
    title: Mapped[str] = mapped_column(String(220))
    description: Mapped[str] = mapped_column(Text, default="")
    template_key: Mapped[str] = mapped_column(String(100), default="classic")
    # None means "use the family maximum" (12 photos per active member).
    target_photo_count: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    cover_memory_id: Mapped[Optional[int]] = mapped_column(ForeignKey("memory_items.id"), nullable=True)
    memory_sequence_json: Mapped[str] = mapped_column(Text, default="[]")
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    # Removal needs approval from all album managers; "active" or
    # "pending_removal". Votes hold the approving user ids.
    status: Mapped[str] = mapped_column(String(40), default="active")
    removal_requested_by: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id"), nullable=True)
    removal_votes_json: Mapped[str] = mapped_column(Text, default="[]")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)


class AlbumPage(Base):
    __tablename__ = "album_pages"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    album_id: Mapped[int] = mapped_column(ForeignKey("albums.id"), index=True)
    page_number: Mapped[int] = mapped_column(Integer)
    layout_json: Mapped[str] = mapped_column(Text)
    version: Mapped[int] = mapped_column(Integer, default=1)
    approval_status: Mapped[str] = mapped_column(String(60), default="approved")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)


class SharePackage(Base):
    __tablename__ = "share_packages"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    circle_id: Mapped[int] = mapped_column(ForeignKey("memory_circles.id"), index=True)
    album_id: Mapped[int] = mapped_column(ForeignKey("albums.id"), index=True)
    token: Mapped[str] = mapped_column(String(160), unique=True, index=True)
    title: Mapped[str] = mapped_column(String(220))
    note: Mapped[str] = mapped_column(Text, default="")
    access_type: Mapped[str] = mapped_column(String(60), default="expires_at")
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    allow_downloads: Mapped[bool] = mapped_column(Boolean, default=False)
    include_captions: Mapped[bool] = mapped_column(Boolean, default=True)
    page_ids_json: Mapped[str] = mapped_column(Text, default="[]")
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    viewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)


class NotificationSubscription(Base):
    __tablename__ = "notification_subscriptions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    provider: Mapped[str] = mapped_column(String(60), default="local")
    endpoint: Mapped[str] = mapped_column(String(500))
    device_label: Mapped[str] = mapped_column(String(160), default="")
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    circle_id: Mapped[int] = mapped_column(ForeignKey("memory_circles.id"), index=True)
    type: Mapped[str] = mapped_column(String(80))
    title: Mapped[str] = mapped_column(String(220))
    body: Mapped[str] = mapped_column(Text, default="")
    target_type: Mapped[str] = mapped_column(String(80), default="")
    target_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    delivery_status: Mapped[str] = mapped_column(String(60), default="queued")
    read_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)


class ActivityLog(Base):
    __tablename__ = "activity_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    circle_id: Mapped[int] = mapped_column(ForeignKey("memory_circles.id"), index=True)
    actor_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    action_type: Mapped[str] = mapped_column(String(100))
    target_type: Mapped[str] = mapped_column(String(100))
    target_id: Mapped[int] = mapped_column(Integer)
    details_json: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

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
    # Blob columns are deferred so metadata/gallery queries do not transfer
    # every image from the remote database. Media routes load one blob only
    # after authorization and ETag checks pass.
    thumbnail_blob: Mapped[Optional[bytes]] = mapped_column(LargeBinary, nullable=True, deferred=True)
    display_blob: Mapped[Optional[bytes]] = mapped_column(LargeBinary, nullable=True, deferred=True)
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
    # Guest (no-account) uploads keep submitted_by = the campaign owner but
    # record who really contributed here.
    guest_name: Mapped[Optional[str]] = mapped_column(String(160), nullable=True)
    guest_email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    campaign_id: Mapped[Optional[int]] = mapped_column(ForeignKey("guest_campaigns.id"), nullable=True)
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
    # Yearbook pilot fields; `classic` albums behave exactly as before.
    album_kind: Mapped[str] = mapped_column(String(60), default="classic")
    campaign_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    theme_preset_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    theme_snapshot_json: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    theme_snapshot_version: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    revision: Mapped[int] = mapped_column(Integer, default=1)
    publication_status: Mapped[str] = mapped_column(String(40), default="draft")
    published_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    quota_policy: Mapped[str] = mapped_column(String(40), default="circle_members")
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


class PasswordResetToken(Base):
    """A one-time token emailed to someone who forgot their password."""

    __tablename__ = "password_reset_tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    token: Mapped[str] = mapped_column(String(160), unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    used_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)


class GuestCampaign(Base):
    """A time-limited link that lets non-logged-in guests upload photos to a
    circle (for an event or campaign). The owner sets and can extend the window."""

    __tablename__ = "guest_campaigns"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    circle_id: Mapped[int] = mapped_column(ForeignKey("memory_circles.id"), index=True)
    token: Mapped[str] = mapped_column(String(160), unique=True, index=True)
    title: Mapped[str] = mapped_column(String(220))
    note: Mapped[str] = mapped_column(Text, default="")
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    require_email_verify: Mapped[bool] = mapped_column(Boolean, default=True)
    revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    # Yearbook pilot fields. `photo_collection` campaigns behave exactly as
    # before; `university_graduation` campaigns add structured contributions.
    campaign_type: Mapped[str] = mapped_column(String(60), default="photo_collection")
    theme_preset_id: Mapped[Optional[int]] = mapped_column(ForeignKey("theme_presets.id"), nullable=True)
    details_json: Mapped[str] = mapped_column(Text, default="{}")
    contribution_settings_json: Mapped[str] = mapped_column(Text, default="{}")
    consent_text: Mapped[str] = mapped_column(Text, default="")
    consent_version: Mapped[int] = mapped_column(Integer, default=0)
    # `draft` -> `published` -> `closed`/`archived`. Legacy photo campaigns
    # are treated as published.
    status: Mapped[str] = mapped_column(String(40), default="published")
    published_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    linked_album_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    participant_quota: Mapped[int] = mapped_column(Integer, default=250)
    total_contribution_quota: Mapped[int] = mapped_column(Integer, default=1500)
    per_guest_photo_quota: Mapped[int] = mapped_column(Integer, default=20)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)


class ThemePreset(Base):
    """A circle-owned, versioned set of constrained visual rules (colors,
    typography preset, cover/header/footer variants) plus brand asset refs."""

    __tablename__ = "theme_presets"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    circle_id: Mapped[int] = mapped_column(ForeignKey("memory_circles.id"), index=True)
    name: Mapped[str] = mapped_column(String(160))
    preset_kind: Mapped[str] = mapped_column(String(60), default="university_graduation")
    version: Mapped[int] = mapped_column(Integer, default=1)
    tokens_json: Mapped[str] = mapped_column(Text, default="{}")
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    archived_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)


class BrandAsset(Base):
    """An owner-uploaded brand image (logo, cover, background) scoped to a
    circle and theme preset. Served only through authorized routes."""

    __tablename__ = "brand_assets"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    circle_id: Mapped[int] = mapped_column(ForeignKey("memory_circles.id"), index=True)
    theme_preset_id: Mapped[Optional[int]] = mapped_column(ForeignKey("theme_presets.id"), nullable=True, index=True)
    kind: Mapped[str] = mapped_column(String(40))
    mime_type: Mapped[str] = mapped_column(String(80))
    width: Mapped[int] = mapped_column(Integer, default=0)
    height: Mapped[int] = mapped_column(Integer, default=0)
    file_size: Mapped[int] = mapped_column(Integer, default=0)
    content_hash: Mapped[str] = mapped_column(String(128), index=True)
    display_path: Mapped[str] = mapped_column(String(500), default="")
    display_blob: Mapped[Optional[bytes]] = mapped_column(LargeBinary, nullable=True, deferred=True)
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    rights_confirmed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)


class CampaignContributor(Base):
    """A guest's durable identity inside one campaign: name + verified email,
    consent evidence, and a campaign-scoped token for submissions."""

    __tablename__ = "campaign_contributors"
    __table_args__ = (UniqueConstraint("campaign_id", "guest_email", name="campaign_contributor_email_unique"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    campaign_id: Mapped[int] = mapped_column(ForeignKey("guest_campaigns.id"), index=True)
    guest_name: Mapped[str] = mapped_column(String(160))
    guest_email: Mapped[str] = mapped_column(String(255), index=True)
    token: Mapped[str] = mapped_column(String(160), unique=True, index=True)
    verification_status: Mapped[str] = mapped_column(String(40), default="unverified")
    verified_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    verify_code: Mapped[str] = mapped_column(String(12), default="")
    verify_expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    verify_sent_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    verify_attempts: Mapped[int] = mapped_column(Integer, default=0)
    consent_version: Mapped[int] = mapped_column(Integer, default=0)
    consented_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    withdrawn_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)


class CampaignContribution(Base):
    """One structured guest submission: a photo memory, graduate profile,
    dedication, official message, typed signature, or acknowledgement."""

    __tablename__ = "campaign_contributions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    campaign_id: Mapped[int] = mapped_column(ForeignKey("guest_campaigns.id"), index=True)
    contributor_id: Mapped[int] = mapped_column(ForeignKey("campaign_contributors.id"), index=True)
    contribution_type: Mapped[str] = mapped_column(String(60), index=True)
    payload_json: Mapped[str] = mapped_column(Text, default="{}")
    asset_id: Mapped[Optional[int]] = mapped_column(ForeignKey("photo_assets.id"), nullable=True)
    signature_asset_id: Mapped[Optional[int]] = mapped_column(ForeignKey("photo_assets.id"), nullable=True)
    moderation_status: Mapped[str] = mapped_column(String(40), default="pending", index=True)
    votes_json: Mapped[str] = mapped_column(Text, default="[]")
    visibility: Mapped[str] = mapped_column(String(40), default="yearbook")
    display_name: Mapped[str] = mapped_column(String(160), default="")
    consent_version: Mapped[int] = mapped_column(Integer, default=0)
    consented_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    sort_hint: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)


class YearbookSection(Base):
    """An ordered section of a yearbook album (cover, profiles, mosaic,
    dedications, signatures...). Content rules live in JSON; pages are
    generated from them per revision."""

    __tablename__ = "yearbook_sections"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    album_id: Mapped[int] = mapped_column(ForeignKey("albums.id"), index=True)
    section_type: Mapped[str] = mapped_column(String(60))
    title: Mapped[str] = mapped_column(String(220), default="")
    subtitle: Mapped[str] = mapped_column(String(220), default="")
    position: Mapped[int] = mapped_column(Integer, default=0)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    layout_variant: Mapped[str] = mapped_column(String(60), default="standard")
    settings_json: Mapped[str] = mapped_column(Text, default="{}")
    source_rule_json: Mapped[str] = mapped_column(Text, default="{}")
    manual_content_json: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now, onupdate=now)


class GuestUploadSession(Base):
    """A guest's lightweight identity for a campaign: a name and email, no
    account. The email is confirmed with a one-time code when required."""

    __tablename__ = "guest_upload_sessions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    campaign_id: Mapped[int] = mapped_column(ForeignKey("guest_campaigns.id"), index=True)
    guest_name: Mapped[str] = mapped_column(String(160))
    guest_email: Mapped[str] = mapped_column(String(255), index=True)
    token: Mapped[str] = mapped_column(String(160), unique=True, index=True)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)
    verify_code: Mapped[str] = mapped_column(String(12), default="")
    verify_expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    verify_sent_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    verify_attempts: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

from datetime import datetime, timedelta
from io import BytesIO

from PIL import Image


def register(client, email, role_name="User"):
    response = client.post(
        "/auth/register",
        json={"display_name": role_name, "email": email, "password": "Password123!"},
    )
    assert response.status_code == 200, response.text
    return response.json()["token"]


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def image_file(color=(210, 140, 96), capture_date=None, size=(900, 700)):
    stream = BytesIO()
    image = Image.new("RGB", size, color)
    if capture_date:
        exif = image.getexif()
        exif[36867] = capture_date
        image.save(stream, format="JPEG", exif=exif)
    else:
        image.save(stream, format="JPEG")
    stream.seek(0)
    return stream


def setup_circle(client):
    owner = register(client, "owner@test.com", "Owner")
    circle = client.post("/circles", json={"name": "Otieno Family Memories"}, headers=auth(owner)).json()
    client.post(
        f"/circles/{circle['id']}/invites",
        json={"email": "approver@test.com", "display_name": "Approver", "role": "approver"},
        headers=auth(owner),
    )
    client.post(
        f"/circles/{circle['id']}/invites",
        json={"email": "contributor@test.com", "display_name": "Contributor", "role": "contributor"},
        headers=auth(owner),
    )
    client.post(
        f"/circles/{circle['id']}/invites",
        json={"email": "viewer@test.com", "display_name": "Viewer", "role": "viewer"},
        headers=auth(owner),
    )
    approver = client.post("/auth/login", json={"email": "approver@test.com", "password": "ChangeMe123!"}).json()["token"]
    contributor = client.post("/auth/login", json={"email": "contributor@test.com", "password": "ChangeMe123!"}).json()["token"]
    viewer = client.post("/auth/login", json={"email": "viewer@test.com", "password": "ChangeMe123!"}).json()["token"]
    # Owner-invited members start as pending; accept so they are active.
    for token in (approver, contributor, viewer):
        client.post(f"/circles/{circle['id']}/membership/accept", headers=auth(token))
    return circle["id"], owner, approver, contributor, viewer


def upload_memory(client, circle_id, token, status="draft"):
    asset = client.post(
        f"/circles/{circle_id}/assets/upload",
        files={"file": ("photo.jpg", image_file(), "image/jpeg")},
        headers=auth(token),
    )
    assert asset.status_code == 200, asset.text
    memory = client.post(
        f"/circles/{circle_id}/memories",
        json={
            "asset_id": asset.json()["id"],
            "caption": "Graduation day",
            "story": "Everyone gathered to celebrate.",
            "event_name": "Graduation",
            "approval_status": status,
        },
        headers=auth(token),
    )
    assert memory.status_code == 200, memory.text
    return asset.json(), memory.json()


def approve_all_reviewers(client, circle_id, memory_id, owner, approver):
    """Owners and approvers form the voting group; all must approve."""
    last = None
    for token in (owner, approver):
        last = client.post(f"/circles/{circle_id}/memories/{memory_id}/approve", headers=auth(token))
        assert last.status_code == 200, last.text
    return last.json()


def test_registration_login_and_circle_creation(client):
    token = register(client, "new@test.com", "New User")
    me = client.get("/me", headers=auth(token))
    assert me.status_code == 200
    assert me.json()["email"] == "new@test.com"
    circle = client.post("/circles", json={"name": "Family Album"}, headers=auth(token))
    assert circle.status_code == 200
    assert circle.json()["name"] == "Family Album"


def test_role_authorization_and_member_management(client):
    circle_id, owner, _approver, _contributor, viewer = setup_circle(client)
    forbidden = client.post(
        f"/circles/{circle_id}/invites",
        json={"email": "blocked@test.com", "role": "viewer"},
        headers=auth(viewer),
    )
    assert forbidden.status_code == 403
    members = client.get(f"/circles/{circle_id}/members", headers=auth(owner))
    assert len(members.json()) == 4


def test_asset_upload_thumbnail_and_memory_workflow(client):
    circle_id, owner, approver, contributor, viewer = setup_circle(client)
    asset, memory = upload_memory(client, circle_id, contributor)
    thumb = client.get(f"/circles/{circle_id}/assets/{asset['id']}/thumbnail", headers=auth(contributor))
    assert thumb.status_code == 200
    submitted = client.post(f"/circles/{circle_id}/memories/{memory['id']}/submit", headers=auth(contributor))
    assert submitted.json()["approval_status"] == "pending"
    viewer_pending = client.get(f"/circles/{circle_id}/memories?status=pending", headers=auth(viewer))
    assert viewer_pending.status_code == 200
    assert len(viewer_pending.json()) == 1
    blocked = client.post(f"/circles/{circle_id}/memories/{memory['id']}/approve", headers=auth(contributor))
    assert blocked.status_code == 403
    approved = client.post(f"/circles/{circle_id}/memories/{memory['id']}/approve", headers=auth(approver))
    assert approved.json()["approval_status"] == "pending"
    assert approved.json()["approval"]["approvals_have"] == 1
    assert approved.json()["approval"]["approvals_needed"] == 2
    approved = approve_all_reviewers(client, circle_id, memory["id"], owner, approver)
    assert approved["approval_status"] == "approved"
    visible = client.get(f"/circles/{circle_id}/memories", headers=auth(viewer))
    assert len(visible.json()) == 1

    photos = client.get(f"/circles/{circle_id}/photos", headers=auth(viewer))
    assert photos.status_code == 200, photos.text
    assert photos.json()[0]["asset"]["id"] == asset["id"]
    assert photos.json()[0]["memory"]["id"] == memory["id"]


def test_unapproved_photos_can_be_sent_for_circle_approval_with_notifications(client):
    circle_id, owner, approver, contributor, viewer = setup_circle(client)
    asset, memory = upload_memory(client, circle_id, contributor, status="draft")
    assert memory["approval_status"] == "draft"

    subscription = client.post(
        "/me/notification-subscriptions",
        json={
            "provider": "local",
            "endpoint": "test-device-approver",
            "device_label": "Approver test device",
        },
        headers=auth(approver),
    )
    assert subscription.status_code == 200, subscription.text

    sent = client.post(f"/circles/{circle_id}/photos/send-for-approval", headers=auth(owner))
    assert sent.status_code == 200, sent.text
    assert sent.json()["sent"] == 1
    # Only the voting group (owner + approver) is asked to approve.
    assert sent.json()["notifications_queued"] == 2

    pending = client.get(f"/circles/{circle_id}/memories?status=pending", headers=auth(viewer)).json()
    assert pending[0]["id"] == memory["id"]

    notifications = client.get("/me/notifications", headers=auth(approver))
    assert notifications.status_code == 200, notifications.text
    assert notifications.json()[0]["type"] == "photo_approval_needed"
    assert notifications.json()[0]["target_id"] == memory["id"]

    viewer_notifications = client.get("/me/notifications", headers=auth(viewer))
    assert viewer_notifications.json() == []


def test_photo_source_date_is_used_for_memory_and_album_order(client):
    circle_id, owner, approver, contributor, viewer = setup_circle(client)
    dates = ["2024:05:03 10:00:00", "2022:01:02 09:00:00"]
    memory_ids = []
    for index, capture_date in enumerate(dates):
        asset = client.post(
            f"/circles/{circle_id}/assets/upload",
            files={"file": (f"dated-{index}.jpg", image_file(capture_date=capture_date), "image/jpeg")},
            headers=auth(contributor),
        )
        assert asset.status_code == 200, asset.text
        memory = client.post(
            f"/circles/{circle_id}/memories",
            json={
                "asset_id": asset.json()["id"],
                "caption": f"Dated photo {index}",
                "approval_status": "pending",
            },
            headers=auth(contributor),
        )
        assert memory.status_code == 200, memory.text
        assert memory.json()["memory_date"].startswith(capture_date[:4].replace(":", "-"))
        approve_all_reviewers(client, circle_id, memory.json()["id"], owner, approver)
        memory_ids.append(memory.json()["id"])

    album = client.post(
        f"/circles/{circle_id}/albums",
        json={"title": "Dated Album"},
        headers=auth(owner),
    ).json()
    pages = client.post(f"/circles/{circle_id}/albums/{album['id']}/pages/generate", headers=auth(owner)).json()
    ordered_memory_ids = [
        item["memory_id"]
        for page in pages[1:]
        for item in page["layout_json"].get("memories", [])
    ]
    assert ordered_memory_ids[:2] == [memory_ids[1], memory_ids[0]]


def test_rejection_workflow(client):
    circle_id, _owner, approver, contributor, _viewer = setup_circle(client)
    _asset, memory = upload_memory(client, circle_id, contributor, status="pending")
    rejected = client.post(f"/circles/{circle_id}/memories/{memory['id']}/reject", headers=auth(approver))
    assert rejected.status_code == 200
    assert rejected.json()["approval_status"] == "rejected"


def test_album_page_generation_and_flip_payload(client):
    circle_id, owner, approver, contributor, viewer = setup_circle(client)
    for index in range(5):
        _asset, memory = upload_memory(client, circle_id, contributor, status="pending")
        approve_all_reviewers(client, circle_id, memory["id"], owner, approver)
    album = client.post(
        f"/circles/{circle_id}/albums",
        json={"title": "Family Highlights", "target_photo_count": 4},
        headers=auth(approver),
    )
    assert album.status_code == 200
    pages = client.post(f"/circles/{circle_id}/albums/{album.json()['id']}/pages/generate", headers=auth(approver))
    assert pages.status_code == 200
    assert pages.json()[0]["layout_json"]["template"] == "event_title"
    assert pages.json()[0]["layout_json"]["cover"]["memory_id"]
    fetched = client.get(f"/circles/{circle_id}/albums/{album.json()['id']}", headers=auth(approver))
    assert len(fetched.json()["pages"]) >= 3
    assert fetched.json()["target_photo_count"] == 4


def test_album_size_is_capped_at_twelve_per_member(client):
    circle_id, owner, _approver, _contributor, _viewer = setup_circle(client)
    # Four active members, so the family maximum is 48 photos.
    too_big = client.post(
        f"/circles/{circle_id}/albums",
        json={"title": "Oversized", "target_photo_count": 49},
        headers=auth(owner),
    )
    assert too_big.status_code == 400
    assert "12 photos per member" in too_big.json()["detail"]

    album = client.post(
        f"/circles/{circle_id}/albums",
        json={"title": "Family Maximum"},
        headers=auth(owner),
    )
    assert album.status_code == 200, album.text
    assert album.json()["target_photo_count"] == 48
    assert album.json()["max_photo_count"] == 48

    over_patch = client.patch(
        f"/circles/{circle_id}/albums/{album.json()['id']}",
        json={"target_photo_count": 100},
        headers=auth(owner),
    )
    assert over_patch.status_code == 400

    ok_patch = client.patch(
        f"/circles/{circle_id}/albums/{album.json()['id']}",
        json={"target_photo_count": 12},
        headers=auth(owner),
    )
    assert ok_patch.status_code == 200, ok_patch.text
    assert ok_patch.json()["target_photo_count"] == 12


def create_album_with_pages(client, circle_id, owner, approver, contributor):
    _asset, memory = upload_memory(client, circle_id, contributor, status="pending")
    viewer = client.post("/auth/login", json={"email": "viewer@test.com", "password": "ChangeMe123!"}).json()["token"]
    approve_all_reviewers(client, circle_id, memory["id"], owner, approver)
    album = client.post(
        f"/circles/{circle_id}/albums",
        json={"title": "Family Highlights"},
        headers=auth(approver),
    ).json()
    client.post(f"/circles/{circle_id}/albums/{album['id']}/pages/generate", headers=auth(approver))
    return client.get(f"/circles/{circle_id}/albums/{album['id']}", headers=auth(owner)).json()


def test_owner_can_create_and_revoke_public_share_package(client):
    circle_id, owner, approver, contributor, viewer = setup_circle(client)
    album = create_album_with_pages(client, circle_id, owner, approver, contributor)

    denied = client.post(
        f"/circles/{circle_id}/albums/{album['id']}/share-packages",
        json={"access_type": "saved"},
        headers=auth(viewer),
    )
    assert denied.status_code == 403

    package = client.post(
        f"/circles/{circle_id}/albums/{album['id']}/share-packages",
        json={"access_type": "saved", "note": "For Auntie", "allow_downloads": False},
        headers=auth(owner),
    )
    assert package.status_code == 200, package.text
    payload = package.json()
    assert payload["status"] == "active"
    assert payload["share_url"].endswith(f"/share/{payload['share_url'].split('/')[-1]}")

    public = client.get(payload["share_url"])
    assert public.status_code == 200, public.text
    public_payload = public.json()
    assert public_payload["title"] == "Family Highlights"
    assert public_payload["note"] == "For Auntie"
    assert public_payload["pages"][1]["layout_json"]["memories"][0]["display_url"].startswith("http://testserver/share/")

    packages = client.get(
        f"/circles/{circle_id}/albums/{album['id']}/share-packages",
        headers=auth(owner),
    )
    assert len(packages.json()) == 1

    revoked = client.post(
        f"/circles/{circle_id}/albums/{album['id']}/share-packages/{payload['id']}/revoke",
        headers=auth(owner),
    )
    assert revoked.json()["status"] == "revoked"
    unavailable = client.get(payload["share_url"])
    assert unavailable.status_code == 404


def test_expiring_share_package_stops_after_first_view(client):
    circle_id, owner, approver, contributor, _viewer = setup_circle(client)
    album = create_album_with_pages(client, circle_id, owner, approver, contributor)

    package = client.post(
        f"/circles/{circle_id}/albums/{album['id']}/share-packages",
        json={"access_type": "expires_after_view"},
        headers=auth(owner),
    )
    assert package.status_code == 200, package.text
    share_url = package.json()["share_url"]
    assert client.get(share_url).status_code == 200
    assert client.get(share_url).status_code == 410


def test_dated_share_package_expires(client):
    circle_id, owner, approver, contributor, _viewer = setup_circle(client)
    album = create_album_with_pages(client, circle_id, owner, approver, contributor)

    package = client.post(
        f"/circles/{circle_id}/albums/{album['id']}/share-packages",
        json={
            "access_type": "expires_at",
            "expires_at": (datetime.utcnow() - timedelta(minutes=1)).isoformat(),
        },
        headers=auth(owner),
    )
    assert package.status_code == 200, package.text
    assert package.json()["status"] == "expired"
    assert client.get(package.json()["share_url"]).status_code == 410


def test_upload_rejects_non_images(client):
    circle_id, _owner, _approver, contributor, _viewer = setup_circle(client)
    response = client.post(
        f"/circles/{circle_id}/assets/upload",
        files={"file": ("notes.txt", BytesIO(b"not an image"), "text/plain")},
        headers=auth(contributor),
    )
    assert response.status_code == 400


def test_upload_dedupe_and_hash_match(client):
    circle_id, owner, approver, contributor, viewer = setup_circle(client)
    photo_bytes = image_file(color=(120, 90, 200)).getvalue()

    first = client.post(
        f"/circles/{circle_id}/assets/upload",
        files={"file": ("one.jpg", BytesIO(photo_bytes), "image/jpeg")},
        headers=auth(owner),
    )
    assert first.status_code == 200, first.text

    duplicate = client.post(
        f"/circles/{circle_id}/assets/upload",
        files={"file": ("copy-of-one.jpg", BytesIO(photo_bytes), "image/jpeg")},
        headers=auth(contributor),
    )
    assert duplicate.status_code == 200, duplicate.text
    assert duplicate.json()["id"] == first.json()["id"]

    content_hash = first.json()["content_hash"]
    match = client.post(
        f"/circles/{circle_id}/assets/match",
        json={"hashes": [content_hash, "deadbeef"]},
        headers=auth(contributor),
    )
    assert match.status_code == 200, match.text
    matches = match.json()["matches"]
    assert content_hash in matches
    assert matches[content_hash]["id"] == first.json()["id"]
    assert "deadbeef" not in matches

    empty = client.post(
        f"/circles/{circle_id}/assets/match",
        json={"hashes": []},
        headers=auth(owner),
    )
    assert empty.json() == {"matches": {}}

    denied = client.post(
        f"/circles/{circle_id}/assets/match",
        json={"hashes": [content_hash]},
        headers=auth(viewer),
    )
    assert denied.status_code == 403


def test_asset_responses_are_cacheable(client):
    owner = register(client, "cache@test.com", "Cache")
    circle = client.post("/circles", json={"name": "Cache Circle"}, headers=auth(owner)).json()
    asset = client.post(
        f"/circles/{circle['id']}/assets/upload",
        files={"file": ("p.jpg", image_file(), "image/jpeg")},
        headers=auth(owner),
    ).json()

    first = client.get(asset["thumbnail_url"], headers=auth(owner))
    assert first.status_code == 200, first.text
    assert "immutable" in first.headers.get("cache-control", "")
    etag = first.headers.get("etag")
    assert etag

    cached = client.get(
        asset["thumbnail_url"],
        headers={**auth(owner), "If-None-Match": etag},
    )
    assert cached.status_code == 304


def test_album_edit_permissions(client):
    circle_id, owner, approver, contributor, viewer = setup_circle(client)
    _, memory = upload_memory(client, circle_id, owner, status="pending")
    approve_all_reviewers(client, circle_id, memory["id"], owner, approver)
    album = client.post(
        f"/circles/{circle_id}/albums",
        json={"title": "First Title", "description": "First note"},
        headers=auth(owner),
    ).json()

    updated = client.patch(
        f"/circles/{circle_id}/albums/{album['id']}",
        json={
            "title": "Renamed Album",
            "description": "A warmer note",
            "target_photo_count": 12,
            "cover_memory_id": memory["id"],
            "memory_sequence": [memory["id"]],
        },
        headers=auth(approver),
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["title"] == "Renamed Album"
    assert updated.json()["description"] == "A warmer note"
    assert updated.json()["target_photo_count"] == 12
    assert updated.json()["cover_memory_id"] == memory["id"]
    assert updated.json()["memory_sequence"] == [memory["id"]]

    fetched = client.get(f"/circles/{circle_id}/albums/{album['id']}", headers=auth(viewer)).json()
    assert fetched["title"] == "Renamed Album"

    denied = client.patch(
        f"/circles/{circle_id}/albums/{album['id']}",
        json={"title": "Sneaky"},
        headers=auth(contributor),
    )
    assert denied.status_code == 403


def test_album_removal_single_manager_is_immediate(client):
    owner = register(client, "solo@test.com", "Solo")
    circle = client.post("/circles", json={"name": "Solo Circle"}, headers=auth(owner)).json()
    album = client.post(f"/circles/{circle['id']}/albums", json={"title": "Trip"}, headers=auth(owner)).json()

    removed = client.post(f"/circles/{circle['id']}/albums/{album['id']}/retire", headers=auth(owner))
    assert removed.status_code == 200, removed.text
    assert removed.json()["status"] == "removed"

    listed = client.get(f"/circles/{circle['id']}/albums", headers=auth(owner)).json()
    assert all(a["id"] != album["id"] for a in listed)


def test_album_removal_needs_all_managers(client):
    circle_id, owner, approver, contributor, viewer = setup_circle(client)
    album = client.post(f"/circles/{circle_id}/albums", json={"title": "Reunion"}, headers=auth(owner)).json()

    # Contributor cannot request removal.
    denied = client.post(f"/circles/{circle_id}/albums/{album['id']}/retire", headers=auth(contributor))
    assert denied.status_code == 403

    # Owner requests; two managers (owner + approver) so it waits.
    pending = client.post(f"/circles/{circle_id}/albums/{album['id']}/retire", headers=auth(owner))
    assert pending.status_code == 200, pending.text
    body = pending.json()
    assert body["status"] == "pending_removal"
    assert body["removal"]["approvals_have"] == 1
    assert body["removal"]["approvals_needed"] == 2

    # Still present in listings while pending.
    listed = client.get(f"/circles/{circle_id}/albums", headers=auth(owner)).json()
    assert any(a["id"] == album["id"] and a["status"] == "pending_removal" for a in listed)

    # Second manager approves -> removed.
    done = client.post(f"/circles/{circle_id}/albums/{album['id']}/retire/approve", headers=auth(approver))
    assert done.status_code == 200, done.text
    assert done.json()["status"] == "removed"
    listed_after = client.get(f"/circles/{circle_id}/albums", headers=auth(owner)).json()
    assert all(a["id"] != album["id"] for a in listed_after)


def test_album_removal_can_be_cancelled(client):
    circle_id, owner, approver, contributor, viewer = setup_circle(client)
    album = client.post(f"/circles/{circle_id}/albums", json={"title": "Keep me"}, headers=auth(owner)).json()
    client.post(f"/circles/{circle_id}/albums/{album['id']}/retire", headers=auth(owner))
    cancelled = client.post(f"/circles/{circle_id}/albums/{album['id']}/retire/cancel", headers=auth(approver))
    assert cancelled.status_code == 200, cancelled.text
    assert cancelled.json()["status"] == "active"


def test_member_search_finds_registered_people(client):
    circle_id, owner, approver, contributor, viewer = setup_circle(client)
    register(client, "grandma@test.com", "Grandma Ada")

    found = client.get(f"/circles/{circle_id}/member-search?q=grandma", headers=auth(owner)).json()
    assert any(r["email"] == "grandma@test.com" and not r["already_member"] for r in found)

    members = client.get(f"/circles/{circle_id}/member-search?q=approver", headers=auth(owner)).json()
    assert any(r["email"] == "approver@test.com" and r["already_member"] for r in members)

    assert client.get(f"/circles/{circle_id}/member-search?q=a", headers=auth(owner)).json() == []

    denied = client.get(f"/circles/{circle_id}/member-search?q=grandma", headers=auth(contributor))
    assert denied.status_code == 403


def test_invite_link_join_flow(client):
    circle_id, owner, approver, contributor, viewer = setup_circle(client)

    link = client.post(
        f"/circles/{circle_id}/invite-links",
        json={"role": "contributor"},
        headers=auth(owner),
    )
    assert link.status_code == 200, link.text
    token = link.json()["token"]

    info = client.get(f"/invite/{token}").json()
    assert info["circle_name"] == "Otieno Family Memories"
    assert info["role"] == "contributor"

    newcomer = register(client, "cousin@test.com", "Cousin Zawadi")
    joined = client.post(f"/invite/{token}/accept", headers=auth(newcomer))
    assert joined.status_code == 200, joined.text
    assert joined.json()["id"] == circle_id

    circles = client.get("/circles", headers=auth(newcomer)).json()
    assert any(c["id"] == circle_id for c in circles)

    # Non-owner cannot mint links; bad token is rejected.
    assert client.post(f"/circles/{circle_id}/invite-links", json={"role": "viewer"}, headers=auth(contributor)).status_code == 403
    assert client.get("/invite/not-a-real-token").status_code == 404


def test_search_circle_and_request_to_join(client):
    circle_id, owner, approver, contributor, viewer = setup_circle(client)
    outsider = register(client, "neighbor@test.com", "Neighbor Njeri")

    # Search finds the circle by name.
    found = client.get("/circles/search?q=otieno", headers=auth(outsider)).json()
    assert any(c["id"] == circle_id and not c["is_member"] and c["request_status"] is None for c in found)

    # Request to join -> pending, and the search now reflects it.
    req = client.post(f"/circles/{circle_id}/join-requests", headers=auth(outsider))
    assert req.status_code == 200, req.text
    request_id = req.json()["id"]
    again = client.get("/circles/search?q=otieno", headers=auth(outsider)).json()
    assert any(c["id"] == circle_id and c["request_status"] == "pending" for c in again)

    # Owner sees and approves it; outsider becomes a member.
    pending = client.get(f"/circles/{circle_id}/join-requests", headers=auth(owner)).json()
    assert any(r["id"] == request_id and r["user"]["email"] == "neighbor@test.com" for r in pending)
    approved = client.post(f"/circles/{circle_id}/join-requests/{request_id}/approve", headers=auth(owner))
    assert approved.status_code == 200, approved.text
    assert any(c["id"] == circle_id for c in client.get("/circles", headers=auth(outsider)).json())

    # Non-owner cannot view or moderate requests.
    assert client.get(f"/circles/{circle_id}/join-requests", headers=auth(contributor)).status_code == 403


def test_delete_memory_removes_it_from_the_album(client):
    circle_id, owner, approver, contributor, viewer = setup_circle(client)
    _, memory = upload_memory(client, circle_id, owner, status="pending")
    approve_all_reviewers(client, circle_id, memory["id"], owner, approver)
    album = client.post(f"/circles/{circle_id}/albums", json={"title": "Trip"}, headers=auth(owner)).json()
    client.post(f"/circles/{circle_id}/albums/{album['id']}/pages/generate", headers=auth(owner))

    def photo_ids():
        pages = client.get(f"/circles/{circle_id}/albums/{album['id']}", headers=auth(owner)).json()["pages"]
        ids = []
        for page in pages:
            for entry in page["layout_json"].get("memories", []):
                ids.append(entry["memory_id"])
        return ids

    assert memory["id"] in photo_ids()

    # A viewer cannot delete.
    assert client.delete(f"/circles/{circle_id}/memories/{memory['id']}", headers=auth(viewer)).status_code == 403

    removed = client.delete(f"/circles/{circle_id}/memories/{memory['id']}", headers=auth(owner))
    assert removed.status_code == 200, removed.text

    # The album rebuilt without that photo, and the memory is gone.
    assert memory["id"] not in photo_ids()
    assert client.get(f"/circles/{circle_id}/memories/{memory['id']}", headers=auth(owner)).status_code == 404


def test_invited_member_must_accept_before_access(client):
    owner = register(client, "host@test.com", "Host")
    circle = client.post("/circles", json={"name": "Host Circle"}, headers=auth(owner)).json()
    circle_id = circle["id"]
    newcomer = register(client, "guest@test.com", "Guest Gathoni")

    # Owner adds the newcomer -> pending, not active.
    invited = client.post(
        f"/circles/{circle_id}/invites",
        json={"email": "guest@test.com", "role": "contributor"},
        headers=auth(owner),
    )
    assert invited.status_code == 200, invited.text
    assert invited.json()["status"] == "invited"

    # Before accepting: not in circle list, and no album/photo access.
    assert all(c["id"] != circle_id for c in client.get("/circles", headers=auth(newcomer)).json())
    assert client.get(f"/circles/{circle_id}/albums", headers=auth(newcomer)).status_code == 403

    # The invitation shows up for the newcomer.
    invites = client.get("/me/invitations", headers=auth(newcomer)).json()
    assert any(i["circle_id"] == circle_id and i["inviter_name"] == "Host" for i in invites)

    # Accept -> now a member with access.
    accepted = client.post(f"/circles/{circle_id}/membership/accept", headers=auth(newcomer))
    assert accepted.status_code == 200, accepted.text
    assert any(c["id"] == circle_id for c in client.get("/circles", headers=auth(newcomer)).json())
    assert client.get(f"/circles/{circle_id}/albums", headers=auth(newcomer)).status_code == 200
    assert client.get("/me/invitations", headers=auth(newcomer)).json() == []


def test_declined_invitation_stays_out(client):
    owner = register(client, "host2@test.com", "Host Two")
    circle_id = client.post("/circles", json={"name": "Host Two Circle"}, headers=auth(owner)).json()["id"]
    newcomer = register(client, "guest2@test.com", "Guest Two")
    client.post(f"/circles/{circle_id}/invites", json={"email": "guest2@test.com", "role": "viewer"}, headers=auth(owner))

    declined = client.post(f"/circles/{circle_id}/membership/decline", headers=auth(newcomer))
    assert declined.status_code == 200, declined.text
    assert all(c["id"] != circle_id for c in client.get("/circles", headers=auth(newcomer)).json())
    assert client.get("/me/invitations", headers=auth(newcomer)).json() == []


def _make_owner_with_circle(client, email, name, circle_name):
    owner = register(client, email, name)
    circle = client.post("/circles", json={"name": circle_name}, headers=auth(owner)).json()
    return owner, circle["id"]


def test_circle_merge_moves_content_and_archives_source(client):
    # Two owners, two circles.
    owner_a, alpha = _make_owner_with_circle(client, "a@test.com", "Owner A", "Grandma's House")
    owner_b, beta = _make_owner_with_circle(client, "b@test.com", "Owner B", "Otieno Family")

    # A shared person is an approver in the source and a viewer in the target.
    # The first invite creates the account (default password ChangeMe123!).
    for circle_id, role in ((alpha, "approver"), (beta, "viewer")):
        client.post(f"/circles/{circle_id}/invites", json={"email": "shared@test.com", "role": role},
                    headers=auth(owner_a if circle_id == alpha else owner_b))
    shared = client.post("/auth/login", json={"email": "shared@test.com", "password": "ChangeMe123!"}).json()["token"]
    client.post(f"/circles/{alpha}/membership/accept", headers=auth(shared))
    client.post(f"/circles/{beta}/membership/accept", headers=auth(shared))

    # Source content: a unique photo/memory/album, plus a photo identical to one in the target.
    _, mem = upload_memory(client, alpha, owner_a, status="pending")
    client.post(f"/circles/{alpha}/memories/{mem['id']}/approve", headers=auth(owner_a))
    client.post(f"/circles/{alpha}/memories/{mem['id']}/approve", headers=auth(shared))
    album = client.post(f"/circles/{alpha}/albums", json={"title": "Trip"}, headers=auth(owner_a)).json()
    # Identical photo (same default color -> same content hash) in both circles.
    client.post(f"/circles/{alpha}/assets/upload", files={"file": ("dup.jpg", image_file(), "image/jpeg")}, headers=auth(owner_a))
    client.post(f"/circles/{beta}/assets/upload", files={"file": ("dup.jpg", image_file(), "image/jpeg")}, headers=auth(owner_b))

    # Source owner requests the merge into the target.
    req = client.post(f"/circles/{alpha}/merge-requests", json={"target_circle_id": beta}, headers=auth(owner_a))
    assert req.status_code == 200, req.text
    request_id = req.json()["id"]

    # Only the TARGET owner may accept.
    assert client.post(f"/circles/{beta}/merge-requests/{request_id}/accept", headers=auth(owner_a)).status_code == 403
    accepted = client.post(f"/circles/{beta}/merge-requests/{request_id}/accept", headers=auth(owner_b))
    assert accepted.status_code == 200, accepted.text

    # Source is archived and gone from its owner's list.
    assert all(c["id"] != alpha for c in client.get("/circles", headers=auth(owner_a)).json())

    # The album and memory now live in the target.
    beta_albums = client.get(f"/circles/{beta}/albums", headers=auth(owner_b)).json()
    assert any(a["title"] == "Trip" for a in beta_albums)
    beta_photos = client.get(f"/circles/{beta}/photos", headers=auth(owner_b)).json()
    asset_ids = [p["asset"]["id"] for p in beta_photos]
    assert len(asset_ids) == len(set(asset_ids)), "identical photo should be deduped, not duplicated"

    # Shared person kept the higher role (approver from the source).
    members = client.get(f"/circles/{beta}/members", headers=auth(owner_b)).json()
    shared_member = next(m for m in members if m["user"]["email"] == "shared@test.com")
    assert shared_member["role"] == "approver"


def _backdate_member_activity(user_email, circle_id, days):
    from sqlalchemy import select
    from sqlalchemy.orm import Session
    from app.database import engine
    from app.models import ActivityLog, CircleMember, User
    from datetime import datetime, timedelta
    when = datetime.utcnow() - timedelta(days=days)
    with Session(engine) as session:
        uid = session.scalar(select(User.id).where(User.email == user_email))
        for log in session.scalars(select(ActivityLog).where(ActivityLog.circle_id == circle_id, ActivityLog.actor_user_id == uid)):
            log.created_at = when
        member = session.scalar(select(CircleMember).where(CircleMember.circle_id == circle_id, CircleMember.user_id == uid))
        member.created_at = when
        session.commit()


def test_inactive_members_are_demoted_then_flagged(client):
    from sqlalchemy import select  # local import for helper symmetry
    circle_id, owner, approver, contributor, viewer = setup_circle(client)

    # Approver goes quiet for 35 days -> demoted one step to contributor.
    _backdate_member_activity("approver@test.com", circle_id, 35)
    # Contributor goes quiet for 100 days -> flagged for the owner.
    _backdate_member_activity("contributor@test.com", circle_id, 100)

    members = client.get(f"/circles/{circle_id}/members", headers=auth(owner)).json()
    by_email = {m["user"]["email"]: m for m in members}

    assert by_email["approver@test.com"]["role"] == "contributor"  # auto-demoted
    assert by_email["contributor@test.com"]["inactivity_tier"] == "flagged"
    # Owner is never demoted or flagged.
    assert by_email["owner@test.com"]["role"] == "owner"
    assert by_email["owner@test.com"]["inactivity_tier"] == "active"

    # Owner removes the flagged member with a plain status patch.
    flagged_id = by_email["contributor@test.com"]["id"]
    removed = client.patch(f"/circles/{circle_id}/members/{flagged_id}", json={"status": "removed"}, headers=auth(owner))
    assert removed.status_code == 200, removed.text
    remaining = client.get(f"/circles/{circle_id}/members", headers=auth(owner)).json()
    assert all(m["user"]["email"] != "contributor@test.com" or m["status"] == "removed" for m in remaining)


def _upload_and_approve(client, circle_id, owner, approver, color, size):
    asset = client.post(
        f"/circles/{circle_id}/assets/upload",
        files={"file": ("p.jpg", image_file(color=color, size=size), "image/jpeg")},
        headers=auth(owner),
    ).json()
    memory = client.post(
        f"/circles/{circle_id}/memories",
        json={"asset_id": asset["id"], "caption": "A moment", "approval_status": "pending"},
        headers=auth(owner),
    ).json()
    approve_all_reviewers(client, circle_id, memory["id"], owner, approver)
    return memory["id"]


def test_album_pages_match_photo_orientation(client):
    circle_id, owner, approver, _contributor, _viewer = setup_circle(client)
    # One landscape (900x700) then two portraits (700x900), distinct colors so
    # they are distinct assets.
    land = _upload_and_approve(client, circle_id, owner, approver, (200, 100, 50), (900, 700))
    port1 = _upload_and_approve(client, circle_id, owner, approver, (50, 200, 100), (700, 900))
    port2 = _upload_and_approve(client, circle_id, owner, approver, (100, 50, 200), (700, 900))

    album = client.post(f"/circles/{circle_id}/albums", json={"title": "Orientation"}, headers=auth(owner)).json()
    client.patch(
        f"/circles/{circle_id}/albums/{album['id']}",
        json={"memory_sequence": [land, port1, port2]},
        headers=auth(owner),
    )
    client.post(f"/circles/{circle_id}/albums/{album['id']}/pages/generate", headers=auth(owner))
    pages = client.get(f"/circles/{circle_id}/albums/{album['id']}", headers=auth(owner)).json()["pages"]

    # Page 0 is the title; the single content page mixes a landscape band over
    # a portrait pair.
    content = [p for p in pages if p["layout_json"].get("rows")]
    assert len(content) == 1, "landscape + two portraits should fit one mixed page"
    rows = content[0]["layout_json"]["rows"]
    assert [r["kind"] for r in rows] == ["landscape", "portrait"]
    assert rows[0]["memories"][0]["memory_id"] == land
    assert rows[0]["memories"][0]["orientation"] == "landscape"
    assert rows[0]["memories"][0]["aspect_ratio"] > 1.15
    assert [m["memory_id"] for m in rows[1]["memories"]] == [port1, port2]
    assert all(m["orientation"] == "portrait" for m in rows[1]["memories"])
    assert all(m["aspect_ratio"] < 0.87 for m in rows[1]["memories"])


def test_album_falls_back_to_photo_date_when_caption_is_a_filename(client):
    circle_id, owner, approver, _contributor, _viewer = setup_circle(client)
    # Upload with a capture date and a camera-filename-style caption.
    asset = client.post(
        f"/circles/{circle_id}/assets/upload",
        files={"file": ("IMG_20240503.jpg", image_file(capture_date="2024:05:03 10:00:00"), "image/jpeg")},
        headers=auth(owner),
    ).json()
    memory = client.post(
        f"/circles/{circle_id}/memories",
        json={"asset_id": asset["id"], "caption": "IMG 20240503 123456", "approval_status": "pending"},
        headers=auth(owner),
    ).json()
    approve_all_reviewers(client, circle_id, memory["id"], owner, approver)

    album = client.post(f"/circles/{circle_id}/albums", json={"title": "Dates"}, headers=auth(owner)).json()
    client.post(f"/circles/{circle_id}/albums/{album['id']}/pages/generate", headers=auth(owner))
    pages = client.get(f"/circles/{circle_id}/albums/{album['id']}", headers=auth(owner)).json()["pages"]

    entry = next(
        m for p in pages for m in p["layout_json"].get("memories", []) if m["memory_id"] == memory["id"]
    )
    # The filename caption is dropped; the date is offered as the label.
    assert entry["caption"] == ""
    assert entry["date_label"] == "May 3, 2024"


def test_album_keeps_a_real_caption(client):
    circle_id, owner, approver, _contributor, _viewer = setup_circle(client)
    asset = client.post(
        f"/circles/{circle_id}/assets/upload",
        files={"file": ("p.jpg", image_file(), "image/jpeg")},
        headers=auth(owner),
    ).json()
    memory = client.post(
        f"/circles/{circle_id}/memories",
        json={"asset_id": asset["id"], "caption": "Grandma's 70th birthday", "approval_status": "pending"},
        headers=auth(owner),
    ).json()
    approve_all_reviewers(client, circle_id, memory["id"], owner, approver)
    album = client.post(f"/circles/{circle_id}/albums", json={"title": "Real"}, headers=auth(owner)).json()
    client.post(f"/circles/{circle_id}/albums/{album['id']}/pages/generate", headers=auth(owner))
    pages = client.get(f"/circles/{circle_id}/albums/{album['id']}", headers=auth(owner)).json()["pages"]
    entry = next(
        m for p in pages for m in p["layout_json"].get("memories", []) if m["memory_id"] == memory["id"]
    )
    assert entry["caption"] == "Grandma's 70th birthday"


def test_photo_without_exif_still_gets_a_date_label(client):
    # WhatsApp/downloaded images often have no capture date; the album should
    # still show a date (falling back to when it was added) and stay sortable.
    circle_id, owner, approver, _contributor, _viewer = setup_circle(client)
    asset = client.post(
        f"/circles/{circle_id}/assets/upload",
        files={"file": ("1001158095.jpg", image_file(), "image/jpeg")},
        headers=auth(owner),
    ).json()
    memory = client.post(
        f"/circles/{circle_id}/memories",
        json={"asset_id": asset["id"], "caption": "1001158095", "approval_status": "pending"},
        headers=auth(owner),
    ).json()
    approve_all_reviewers(client, circle_id, memory["id"], owner, approver)
    album = client.post(f"/circles/{circle_id}/albums", json={"title": "Our Memory Book"}, headers=auth(owner)).json()
    client.post(f"/circles/{circle_id}/albums/{album['id']}/pages/generate", headers=auth(owner))
    pages = client.get(f"/circles/{circle_id}/albums/{album['id']}", headers=auth(owner)).json()["pages"]
    entry = next(m for p in pages for m in p["layout_json"].get("memories", []) if m["memory_id"] == memory["id"])
    # The numeric filename caption is dropped and a real date is shown instead.
    assert entry["caption"] == ""
    assert entry["date_label"] != ""
    assert "," in entry["date_label"]


def test_change_password(client):
    token = register(client, "changer@test.com", "Changer")
    bad = client.post("/auth/change-password",
                      json={"current_password": "wrong", "new_password": "NewPass123!"},
                      headers=auth(token))
    assert bad.status_code == 400
    ok = client.post("/auth/change-password",
                     json={"current_password": "Password123!", "new_password": "NewPass123!"},
                     headers=auth(token))
    assert ok.status_code == 200, ok.text
    # Old password no longer works; new one does.
    assert client.post("/auth/login", json={"email": "changer@test.com", "password": "Password123!"}).status_code == 401
    assert client.post("/auth/login", json={"email": "changer@test.com", "password": "NewPass123!"}).status_code == 200


def _reset_token_for(email):
    from sqlalchemy import select
    from sqlalchemy.orm import Session
    from app.database import engine
    from app.models import PasswordResetToken, User
    with Session(engine) as session:
        uid = session.scalar(select(User.id).where(User.email == email))
        return session.scalar(
            select(PasswordResetToken.token)
            .where(PasswordResetToken.user_id == uid)
            .order_by(PasswordResetToken.created_at.desc())
        )


def test_forgot_and_reset_password(client):
    register(client, "forgot@test.com", "Forgetful")
    # Unknown email still returns 200 (no account enumeration).
    assert client.post("/auth/forgot-password", json={"email": "nobody@test.com"}).status_code == 200
    assert client.post("/auth/forgot-password", json={"email": "forgot@test.com"}).status_code == 200

    token = _reset_token_for("forgot@test.com")
    assert token
    reset = client.post("/auth/reset-password", json={"token": token, "new_password": "Reset123!"})
    assert reset.status_code == 200, reset.text
    assert client.post("/auth/login", json={"email": "forgot@test.com", "password": "Reset123!"}).status_code == 200
    # The token cannot be reused.
    assert client.post("/auth/reset-password", json={"token": token, "new_password": "Again123!"}).status_code == 400


def test_guest_campaign_upload_flow(client):
    circle_id, owner, approver, _contributor, _viewer = setup_circle(client)
    # No email verification so the test doesn't need a code.
    campaign = client.post(f"/circles/{circle_id}/campaigns",
                           json={"title": "Reunion 2026", "require_email_verify": False},
                           headers=auth(owner)).json()
    token = campaign["token"]
    assert campaign["is_open"] is True

    reg = client.post(f"/campaigns/{token}/guest", json={"name": "Aunt May", "email": "may@guest.com"})
    assert reg.status_code == 200, reg.text
    guest_token = reg.json()["guest_token"]

    up = client.post(f"/campaigns/{token}/upload",
                     data={"guest_token": guest_token, "caption": "At the park"},
                     files={"file": ("p.jpg", image_file(), "image/jpeg")})
    assert up.status_code == 200, up.text
    assert up.json()["pending"] is True

    # It shows up in the reviewer queue, attributed to the guest, and is pending.
    pending = client.get(f"/circles/{circle_id}/memories?status=pending", headers=auth(owner)).json()
    guest_mem = next(m for m in pending if m.get("guest_name") == "Aunt May")
    assert guest_mem["approval_status"] == "pending"

    approve_all_reviewers(client, circle_id, guest_mem["id"], owner, approver)

    # Now the guest gallery (no login) shows the approved photo.
    view = client.get(f"/campaigns/{token}").json()
    assert len(view["gallery"]) == 1
    assert view["gallery"][0]["thumbnail_url"].startswith(f"/campaigns/{token}/assets/")

    # Revoking closes the link.
    client.post(f"/circles/{circle_id}/campaigns/{campaign['id']}/revoke", headers=auth(owner))
    assert client.post(f"/campaigns/{token}/upload",
                       data={"guest_token": guest_token},
                       files={"file": ("p2.jpg", image_file(color=(1, 2, 3)), "image/jpeg")}).status_code == 410


def test_guest_campaign_email_verification(client):
    circle_id, owner, _approver, _contributor, _viewer = setup_circle(client)
    campaign = client.post(f"/circles/{circle_id}/campaigns",
                           json={"title": "Gala", "require_email_verify": True},
                           headers=auth(owner)).json()
    token = campaign["token"]
    reg = client.post(f"/campaigns/{token}/guest", json={"name": "Guest", "email": "g@guest.com"})
    # With no email configured in tests, the guest is let in directly.
    assert reg.status_code == 200, reg.text
    assert "guest_token" in reg.json()


def test_only_owner_manages_campaigns(client):
    circle_id, _owner, approver, _contributor, _viewer = setup_circle(client)
    assert client.post(f"/circles/{circle_id}/campaigns", json={"title": "X"}, headers=auth(approver)).status_code == 403


def test_campaign_gallery_shows_only_campaign_photos(client):
    # A circle's own private memories must never appear on a guest link.
    circle_id, owner, approver, _contributor, _viewer = setup_circle(client)
    _asset, memory = upload_memory(client, circle_id, owner, status="pending")
    approve_all_reviewers(client, circle_id, memory["id"], owner, approver)

    campaign = client.post(f"/circles/{circle_id}/campaigns",
                           json={"title": "Open day", "require_email_verify": False},
                           headers=auth(owner)).json()
    token = campaign["token"]

    # The circle's approved family photo is NOT in the guest gallery...
    assert client.get(f"/campaigns/{token}").json()["gallery"] == []
    # ...and its asset is not reachable through the campaign asset route.
    asset_id = memory["asset_id"]
    leaked = client.get(f"/campaigns/{token}/assets/{asset_id}/thumbnail")
    assert leaked.status_code == 404

    # A photo contributed through the campaign IS visible once approved.
    reg = client.post(f"/campaigns/{token}/guest", json={"name": "Guest", "email": "g2@guest.com"})
    up = client.post(f"/campaigns/{token}/upload",
                     data={"guest_token": reg.json()["guest_token"]},
                     files={"file": ("c.jpg", image_file(color=(9, 9, 9)), "image/jpeg")})
    assert up.status_code == 200, up.text
    pending = client.get(f"/circles/{circle_id}/memories?status=pending", headers=auth(owner)).json()
    guest_mem = next(m for m in pending if m.get("guest_name") == "Guest")
    approve_all_reviewers(client, circle_id, guest_mem["id"], owner, approver)
    gallery = client.get(f"/campaigns/{token}").json()["gallery"]
    assert len(gallery) == 1

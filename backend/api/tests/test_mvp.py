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


def image_file(color=(210, 140, 96)):
    stream = BytesIO()
    Image.new("RGB", (900, 700), color).save(stream, format="JPEG")
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
    circle_id, _owner, approver, contributor, viewer = setup_circle(client)
    asset, memory = upload_memory(client, circle_id, contributor)
    thumb = client.get(f"/circles/{circle_id}/assets/{asset['id']}/thumbnail", headers=auth(contributor))
    assert thumb.status_code == 200
    submitted = client.post(f"/circles/{circle_id}/memories/{memory['id']}/submit", headers=auth(contributor))
    assert submitted.json()["approval_status"] == "pending"
    viewer_pending = client.get(f"/circles/{circle_id}/memories?status=pending", headers=auth(viewer))
    assert viewer_pending.status_code == 200
    assert viewer_pending.json() == []
    approved = client.post(f"/circles/{circle_id}/memories/{memory['id']}/approve", headers=auth(approver))
    assert approved.json()["approval_status"] == "approved"
    visible = client.get(f"/circles/{circle_id}/memories", headers=auth(viewer))
    assert len(visible.json()) == 1


def test_rejection_workflow(client):
    circle_id, _owner, approver, contributor, _viewer = setup_circle(client)
    _asset, memory = upload_memory(client, circle_id, contributor, status="pending")
    rejected = client.post(f"/circles/{circle_id}/memories/{memory['id']}/reject", headers=auth(approver))
    assert rejected.status_code == 200
    assert rejected.json()["approval_status"] == "rejected"


def test_album_page_generation_and_flip_payload(client):
    circle_id, _owner, approver, contributor, _viewer = setup_circle(client)
    for index in range(5):
        _asset, memory = upload_memory(client, circle_id, contributor, status="pending")
        client.post(f"/circles/{circle_id}/memories/{memory['id']}/approve", headers=auth(approver))
    album = client.post(
        f"/circles/{circle_id}/albums",
        json={"title": "Family Highlights"},
        headers=auth(approver),
    )
    assert album.status_code == 200
    pages = client.post(f"/circles/{circle_id}/albums/{album.json()['id']}/pages/generate", headers=auth(approver))
    assert pages.status_code == 200
    assert pages.json()[0]["layout_json"]["template"] == "event_title"
    fetched = client.get(f"/circles/{circle_id}/albums/{album.json()['id']}", headers=auth(approver))
    assert len(fetched.json()["pages"]) >= 3


def create_album_with_pages(client, circle_id, owner, approver, contributor):
    _asset, memory = upload_memory(client, circle_id, contributor, status="pending")
    client.post(f"/circles/{circle_id}/memories/{memory['id']}/approve", headers=auth(approver))
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
    client.post(f"/circles/{circle_id}/memories/{memory['id']}/approve", headers=auth(owner))
    album = client.post(
        f"/circles/{circle_id}/albums",
        json={"title": "First Title", "description": "First note"},
        headers=auth(owner),
    ).json()

    updated = client.patch(
        f"/circles/{circle_id}/albums/{album['id']}",
        json={"title": "Renamed Album", "description": "A warmer note"},
        headers=auth(approver),
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["title"] == "Renamed Album"
    assert updated.json()["description"] == "A warmer note"

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

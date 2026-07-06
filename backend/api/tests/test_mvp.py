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

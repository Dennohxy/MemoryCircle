from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image, ImageDraw

from .database import Base, engine
from .main import app


USERS = {
    "owner": ("Owner Otieno", "owner@example.com", "Password123!"),
    "approver": ("Approver Otieno", "approver@example.com", "Password123!"),
    "contributor": ("Contributor Otieno", "contributor@example.com", "Password123!"),
    "viewer": ("Viewer Otieno", "viewer@example.com", "Password123!"),
}


def image_bytes(index: int) -> BytesIO:
    image = Image.new("RGB", (1000, 720), (230 - index * 8, 185 + index * 4, 125 + index * 6))
    draw = ImageDraw.Draw(image)
    draw.rectangle((70, 70, 930, 650), outline=(90, 68, 52), width=8)
    draw.text((120, 310), f"Memory Circle {index}", fill=(40, 32, 28))
    stream = BytesIO()
    image.save(stream, format="JPEG")
    stream.seek(0)
    return stream


def register(client: TestClient, key: str) -> str:
    name, email, password = USERS[key]
    response = client.post("/auth/register", json={"display_name": name, "email": email, "password": password})
    if response.status_code == 409:
        response = client.post("/auth/login", json={"email": email, "password": password})
    response.raise_for_status()
    return response.json()["token"]


def run_seed(reset: bool = False):
    if reset:
        Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    client = TestClient(app)
    owner_token = register(client, "owner")
    headers = {"Authorization": f"Bearer {owner_token}"}
    circle = client.post(
        "/circles",
        json={"name": "Otieno Family Memories", "description": "A demo circle for the Memory Circle MVP."},
        headers=headers,
    ).json()
    circle_id = circle["id"]
    for key, role in [("approver", "approver"), ("contributor", "contributor"), ("viewer", "viewer")]:
        name, email, _ = USERS[key]
        client.post(f"/circles/{circle_id}/invites", json={"display_name": name, "email": email, "role": role}, headers=headers)
    statuses = ["approved"] * 8 + ["pending", "rejected"]
    for index, status in enumerate(statuses, start=1):
        upload = client.post(
            f"/circles/{circle_id}/assets/upload",
            files={"file": (f"memory-{index}.jpg", image_bytes(index), "image/jpeg")},
            headers=headers,
        ).json()
        memory = client.post(
            f"/circles/{circle_id}/memories",
            json={
                "asset_id": upload["id"],
                "caption": f"Family highlight {index}",
                "story": "A placeholder story showing where family recollections, context, and voices belong.",
                "event_name": "Family Highlights",
                "memory_date": f"2024-0{((index - 1) % 9) + 1}-01T00:00:00",
                "location_text": "Nairobi / Tokyo",
                "approval_status": "pending",
            },
            headers=headers,
        ).json()
        if status == "approved":
            client.post(f"/circles/{circle_id}/memories/{memory['id']}/approve", headers=headers)
        elif status == "rejected":
            client.post(f"/circles/{circle_id}/memories/{memory['id']}/reject", headers=headers)
    album = client.post(
        f"/circles/{circle_id}/albums",
        json={"title": "Family Highlights", "description": "Generated demo album from approved memories."},
        headers=headers,
    ).json()
    client.post(f"/circles/{circle_id}/albums/{album['id']}/pages/generate", headers=headers)
    return {"circle_id": circle_id, "album_id": album["id"], "demo_password": "Password123!"}


if __name__ == "__main__":
    print(run_seed(reset=True))

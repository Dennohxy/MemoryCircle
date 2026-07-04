import os
import shutil
import tempfile

import pytest
from fastapi.testclient import TestClient

os.environ["DATABASE_URL"] = "sqlite:///:memory:"
os.environ["STORAGE_ROOT"] = tempfile.mkdtemp(prefix="memory-circle-test-")

from app.database import Base, engine
from app.main import app


@pytest.fixture()
def client():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture(autouse=True)
def cleanup_storage():
    yield
    root = os.environ["STORAGE_ROOT"]
    if os.path.exists(root):
        shutil.rmtree(root, ignore_errors=True)
        os.makedirs(root, exist_ok=True)

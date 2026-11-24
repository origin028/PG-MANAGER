"""Uploaded files: local disk (dev) or a Cloud Storage bucket (Cloud Run). Always encrypted; only our own keys readable."""
import pytest

from app.core.config import settings
from app.core.exceptions import NotFoundError
from app.services.file_service import FileService

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 300


class FakeBlob:
    def __init__(self, store, key):
        self.store, self.key = store, key

    def upload_from_string(self, data, content_type=None):
        self.store[self.key] = data

    def exists(self):
        return self.key in self.store

    def download_as_bytes(self):
        return self.store[self.key]


class FakeBucket:
    def __init__(self):
        self.store = {}

    def blob(self, key):
        return FakeBlob(self.store, key)


def test_local_round_trip_is_encrypted_at_rest():
    key = FileService._validate_and_store(JPEG, "id.jpg", "aadhaar_front_file")
    from app.services.file_service import BASE_DIR

    assert (BASE_DIR / key).read_bytes() != JPEG  # encrypted on disk
    data, mime = FileService.load(key)
    assert data == JPEG and mime == "image/jpeg"
    (BASE_DIR / key).unlink()


def test_bucket_round_trip(monkeypatch):
    bucket = FakeBucket()
    monkeypatch.setattr(settings, "STORAGE_BACKEND", "gcs")
    monkeypatch.setattr(FileService, "_gcs_bucket", staticmethod(lambda: bucket))
    key = FileService._validate_and_store(JPEG, "selfie.jpg", "resident_selfie_file")
    assert key in bucket.store and bucket.store[key] != JPEG
    assert FileService.load(key)[0] == JPEG
    with pytest.raises(NotFoundError):
        FileService.load("uploads/kyc/" + "0" * 32 + ".jpg.enc")  # not in the bucket


@pytest.mark.parametrize("bad", ["../app/core/config.py", "uploads/kyc/../../.env", "/etc/passwd", "uploads/kyc/abc.jpg", "", None,
                                 "uploads/kyc/" + "a" * 32 + ".exe.enc"])
def test_only_generated_keys_can_be_read(bad):
    with pytest.raises(NotFoundError):
        FileService.load(bad)

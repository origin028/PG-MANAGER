import asyncio
from pathlib import Path

import pytest

from app.core.exceptions import BadRequestError
from app.services.file_service import FileService, UPLOAD_DIR

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
PDF = b"%PDF-1.4\n" + b"0" * 64


def save(content, name):
    return asyncio.run(FileService.validate_and_save_upload(content, "aadhaar_front_file", filename=name))


def test_kyc_file_encrypted_at_rest_and_roundtrips():
    key = save(JPEG, "aadhaar.jpg")
    path = UPLOAD_DIR / Path(key).name
    assert key.startswith("uploads/kyc/") and key.endswith(".enc")
    on_disk = path.read_bytes()
    assert JPEG not in on_disk and not on_disk.startswith(b"\xff\xd8")  # ciphertext, not the image
    plain, mime = FileService.read_document(path)
    assert plain == JPEG and mime == "image/jpeg"
    path.unlink()


@pytest.mark.parametrize("content,name", [(PNG, "a.png"), (PDF, "b.pdf")])
def test_valid_png_pdf_accepted(content, name):
    key = save(content, name)
    (UPLOAD_DIR / Path(key).name).unlink()


@pytest.mark.parametrize(
    "content,name",
    [
        (b"<?php echo 1; ?>" + b"x" * 50, "shell.jpg"),   # script disguised as image
        (b"MZ" + b"\x00" * 64, "tool.pdf"),                # executable disguised as pdf
        (PNG, "wrong-ext.jpg"),                            # real PNG, wrong extension
        (JPEG, "doc.exe"),                                  # disallowed extension
        (b"", "empty.jpg"),
        (JPEG + b"0" * (5 * 1024 * 1024), "big.jpg"),      # > 5 MB
    ],
)
def test_invalid_uploads_rejected(content, name):
    with pytest.raises(BadRequestError):
        save(content, name)


def test_user_supplied_filename_never_reaches_disk():
    key = save(JPEG, "../../etc/passwd.jpg")
    assert ".." not in key and "passwd" not in key
    (UPLOAD_DIR / Path(key).name).unlink()

import inspect
import os
import re
import uuid
from pathlib import Path
from typing import Any, Dict, Optional, Tuple, Union

from app.core.crypto import decrypt_bytes, encrypt_bytes
from app.core.exceptions import BadRequestError

ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".pdf"}
MAX_FILE_SIZE = 5 * 1024 * 1024  # 5 MB

BASE_DIR = Path(__file__).resolve().parent.parent.parent
UPLOAD_DIR = BASE_DIR / "uploads" / "kyc"
# Keys look like uploads/kyc/<32 hex>.<ext>.enc (older demo files may lack .enc).
STORED_KEY = re.compile(r"uploads/kyc/[0-9a-f]{32}\.(jpg|jpeg|png|pdf)(\.enc)?")


def sanitize_filename(filename: str) -> str:
    """Sanitizes filename removing directory traversal characters and special symbols."""
    clean = os.path.basename(filename)
    clean = re.sub(r"[^\w.\-]", "_", clean)
    return clean[:100]  # truncate overly long names


# Magic-byte signatures: the declared extension/MIME is never trusted on its own.
_SIGNATURES = (
    (b"\xff\xd8\xff", "image/jpeg", {".jpg", ".jpeg"}),
    (b"\x89PNG\r\n\x1a\n", "image/png", {".png"}),
    (b"%PDF-", "application/pdf", {".pdf"}),
)


def sniff_mime(content: bytes) -> Optional[str]:
    for magic, mime, _ in _SIGNATURES:
        if content.startswith(magic):
            return mime
    return None


class FileService:
    @staticmethod
    def ensure_upload_dir() -> Path:
        UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
        return UPLOAD_DIR

    @classmethod
    def _validate_and_store(cls, content: bytes, orig_name: str, field_name: str) -> str:
        ext = os.path.splitext(orig_name)[1].lower()
        if ext not in ALLOWED_EXTENSIONS:
            raise BadRequestError(
                f"Invalid file extension '{ext}' for '{field_name}'. Allowed extensions: {', '.join(sorted(ALLOWED_EXTENSIONS))}."
            )
        if len(content) == 0:
            raise BadRequestError(f"Uploaded file for '{field_name}' is empty.")
        if len(content) > MAX_FILE_SIZE:
            raise BadRequestError(
                f"File '{orig_name}' ({len(content)} bytes) exceeds the 5MB size limit for '{field_name}'."
            )
        detected = sniff_mime(content)
        if detected is None:
            raise BadRequestError(f"File for '{field_name}' is not a valid JPEG, PNG or PDF document.")
        allowed_exts = next(exts for _, mime, exts in _SIGNATURES if mime == detected)
        if ext not in allowed_exts:
            raise BadRequestError(f"File content does not match its extension for '{field_name}'.")

        # Random name only: user-supplied names never reach storage.
        key = f"uploads/kyc/{uuid.uuid4().hex}{ext}.enc"
        cls._put(key, encrypt_bytes(content))
        return key

    @classmethod
    async def validate_and_save_upload(
        cls,
        upload: Any,
        field_name: str,
        filename: Optional[str] = None,
    ) -> str:
        """Validates (size, extension, magic bytes), encrypts, stores. Returns the storage key."""
        if upload is None:
            raise BadRequestError(f"Missing required file for '{field_name}'.")

        if hasattr(upload, "read") and hasattr(upload, "filename"):
            orig_name = upload.filename or f"{field_name}.jpg"
            raw = upload.read()
            content = await raw if inspect.iscoroutine(raw) else raw
            return cls._validate_and_store(content, orig_name, field_name)

        if isinstance(upload, bytes):
            return cls._validate_and_store(upload, filename or f"{field_name}.jpg", field_name)

        raise BadRequestError(f"Unsupported upload type for '{field_name}'.")

    # ---- storage backends -------------------------------------------------------------------
    @staticmethod
    def _gcs_bucket():
        from google.cloud import storage  # imported only when the bucket backend is used

        from app.core.config import settings

        if not settings.GCS_BUCKET:
            raise RuntimeError("GCS_BUCKET is not set.")
        return storage.Client().bucket(settings.GCS_BUCKET)

    @classmethod
    def _put(cls, key: str, data: bytes) -> None:
        from app.core.config import settings

        if settings.STORAGE_BACKEND.lower() == "gcs":
            cls._gcs_bucket().blob(key).upload_from_string(data, content_type="application/octet-stream")
        else:
            cls.ensure_upload_dir()
            (BASE_DIR / key).write_bytes(data)

    @classmethod
    def load(cls, key: Optional[str]) -> Tuple[bytes, str]:
        """Reads a stored file by the key we saved it under. Raises NotFoundError for anything else."""
        from app.core.config import settings
        from app.core.exceptions import NotFoundError

        clean = (key or "").strip().lstrip("/\\")
        if not STORED_KEY.fullmatch(clean):  # only names this service generated: no path tricks
            raise NotFoundError("File not found.")
        try:
            if settings.STORAGE_BACKEND.lower() == "gcs":
                blob = cls._gcs_bucket().blob(clean)
                if not blob.exists():
                    raise NotFoundError("File not found.")
                raw = blob.download_as_bytes()
            else:
                path = (BASE_DIR / clean).resolve()
                if (BASE_DIR / "uploads").resolve() not in path.parents or not path.is_file():
                    raise NotFoundError("File not found.")
                raw = path.read_bytes()
            if clean.endswith(".enc"):
                raw = decrypt_bytes(raw)
        except NotFoundError:
            raise
        except ValueError:
            raise NotFoundError("File could not be read.")
        return raw, sniff_mime(raw) or "application/octet-stream"

    @staticmethod
    def read_document(full_path: Path) -> Tuple[bytes, str]:
        """Returns (plaintext bytes, mime type). Handles encrypted (.enc) and legacy plain files."""
        raw = full_path.read_bytes()
        if full_path.name.endswith(".enc"):
            raw = decrypt_bytes(raw)
        return raw, sniff_mime(raw) or "application/octet-stream"

    @classmethod
    def validate_kyc_method_and_files(
        cls,
        verification_method: str,
        files_present: Dict[str, bool],
    ) -> str:
        """
        Strictly validates that document combination matches chosen KYC method:
        - Aadhaar + PAN requires: aadhaar_front_file, aadhaar_back_file, pan_card_file, resident_selfie_file.
        - Passport Only requires: passport_file, resident_selfie_file.
        - Resident selfie is mandatory for both.
        - Reject invalid document combinations.
        """
        norm_method = verification_method.strip().upper()
        if "AADHAAR" in norm_method and "PAN" in norm_method:
            resolved_method = "AADHAAR_PAN"
        elif "PASSPORT" in norm_method:
            resolved_method = "PASSPORT"
        else:
            raise BadRequestError(
                "Invalid verification method. Allowed methods: 'Aadhaar + PAN' or 'Passport Only'."
            )

        if not files_present.get("resident_selfie_file"):
            raise BadRequestError("Resident selfie ('resident_selfie_file') is mandatory for registration.")

        if resolved_method == "AADHAAR_PAN":
            if files_present.get("passport_file"):
                raise BadRequestError(
                    "Passport file cannot be submitted when 'Aadhaar + PAN' verification method is chosen."
                )
            missing = []
            if not files_present.get("aadhaar_front_file"):
                missing.append("aadhaar_front_file")
            if not files_present.get("aadhaar_back_file"):
                missing.append("aadhaar_back_file")
            if not files_present.get("pan_card_file"):
                missing.append("pan_card_file")
            if missing:
                raise BadRequestError(
                    f"Aadhaar + PAN verification method requires missing documents: {', '.join(missing)}."
                )

        elif resolved_method == "PASSPORT":
            forbidden = []
            if files_present.get("aadhaar_front_file"):
                forbidden.append("aadhaar_front_file")
            if files_present.get("aadhaar_back_file"):
                forbidden.append("aadhaar_back_file")
            if files_present.get("pan_card_file"):
                forbidden.append("pan_card_file")
            if forbidden:
                raise BadRequestError(
                    f"Aadhaar/PAN documents ({', '.join(forbidden)}) cannot be submitted when 'Passport Only' method is chosen."
                )
            if not files_present.get("passport_file"):
                raise BadRequestError("Passport Only verification method requires 'passport_file'.")

        return resolved_method

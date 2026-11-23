import inspect
import os
import re
import uuid
from pathlib import Path
from typing import Any, Dict, Optional, Tuple, Union

from app.core.exceptions import BadRequestError

ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".pdf"}
ALLOWED_MIME_TYPES = {"image/jpeg", "image/png", "application/pdf", "application/octet-stream"}
MAX_FILE_SIZE = 5 * 1024 * 1024  # 5 MB

BASE_DIR = Path(__file__).resolve().parent.parent.parent
UPLOAD_DIR = BASE_DIR / "uploads" / "kyc"


def sanitize_filename(filename: str) -> str:
    """Sanitizes filename removing directory traversal characters and special symbols."""
    clean = os.path.basename(filename)
    clean = re.sub(r"[^\w.\-]", "_", clean)
    return clean[:100]  # truncate overly long names


class FileService:
    @staticmethod
    def ensure_upload_dir() -> Path:
        UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
        return UPLOAD_DIR

    @classmethod
    async def validate_and_save_upload(
        cls,
        upload: Any,
        field_name: str,
        filename: Optional[str] = None,
    ) -> str:
        """
        Validates uploaded file format and size, writes to disk, and returns relative storage path.
        Accepts FastAPI/Starlette UploadFile or raw bytes with filename.
        """
        if upload is None:
            raise BadRequestError(f"Missing required file for '{field_name}'.")

        cls.ensure_upload_dir()

        if hasattr(upload, "read") and hasattr(upload, "filename"):
            orig_name = upload.filename or f"{field_name}.jpg"
            ext = os.path.splitext(orig_name)[1].lower()
            if ext not in ALLOWED_EXTENSIONS:
                raise BadRequestError(
                    f"Invalid file extension '{ext}' for '{field_name}'. Allowed extensions: {', '.join(sorted(ALLOWED_EXTENSIONS))}."
                )

            raw = upload.read()
            if inspect.iscoroutine(raw):
                content = await raw
            else:
                content = raw

            if len(content) == 0:
                raise BadRequestError(f"Uploaded file for '{field_name}' is empty.")
            if len(content) > MAX_FILE_SIZE:
                raise BadRequestError(
                    f"File '{orig_name}' ({len(content)} bytes) exceeds the 5MB size limit for '{field_name}'."
                )

            safe_name = sanitize_filename(orig_name)
            stored_filename = f"{uuid.uuid4().hex}_{safe_name}"
            target_path = UPLOAD_DIR / stored_filename

            with open(target_path, "wb") as f:
                f.write(content)

            return f"uploads/kyc/{stored_filename}"

        elif isinstance(upload, bytes):
            orig_name = filename or f"{field_name}.jpg"
            ext = os.path.splitext(orig_name)[1].lower()
            if ext not in ALLOWED_EXTENSIONS:
                raise BadRequestError(
                    f"Invalid file extension '{ext}' for '{field_name}'. Allowed extensions: {', '.join(sorted(ALLOWED_EXTENSIONS))}."
                )
            if len(upload) == 0:
                raise BadRequestError(f"Uploaded file for '{field_name}' is empty.")
            if len(upload) > MAX_FILE_SIZE:
                raise BadRequestError(
                    f"File '{orig_name}' exceeds the 5MB size limit for '{field_name}'."
                )

            safe_name = sanitize_filename(orig_name)
            stored_filename = f"{uuid.uuid4().hex}_{safe_name}"
            target_path = UPLOAD_DIR / stored_filename

            with open(target_path, "wb") as f:
                f.write(upload)

            return f"uploads/kyc/{stored_filename}"

        raise BadRequestError(f"Unsupported upload type for '{field_name}'.")

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

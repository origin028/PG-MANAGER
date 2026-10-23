from abc import ABC, abstractmethod


class ObjectStorageInterface(ABC):
    """Abstract interface for private cloud object storage (S3 / Cloud Storage)."""

    @abstractmethod
    def upload_file(self, file_bytes: bytes, destination_path: str, content_type: str) -> str:
        """Uploads private file and returns internal storage key."""
        pass

    @abstractmethod
    def generate_presigned_url(self, file_path: str, expiration_seconds: int = 900) -> str:
        """Generates a secure, expiring signed URL (e.g. 15 minutes) for private document access."""
        pass


class S3CompatibleStorage(ObjectStorageInterface):
    def upload_file(self, file_bytes: bytes, destination_path: str, content_type: str) -> str:
        return f"private/{destination_path}"

    def generate_presigned_url(self, file_path: str, expiration_seconds: int = 900) -> str:
        return f"https://storage.originpg.internal/{file_path}?token=mock_presigned_token&expires={expiration_seconds}"

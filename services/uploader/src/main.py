import os
import logging

from .keys import ensure_keypair
from .sftp import SFTPUploader
from .watcher import watch

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


def main():
    # Generate/load SSH keypair
    key_path = str(ensure_keypair())

    # Load config from environment
    host = os.environ.get("SFTP_HOST")
    if not host:
        logger.error("SFTP_HOST is required")
        raise SystemExit(1)

    port = int(os.environ.get("SFTP_PORT", "22"))
    user = os.environ.get("SFTP_USER")
    if not user:
        logger.error("SFTP_USER is required")
        raise SystemExit(1)

    remote_path = os.environ.get("SFTP_REMOTE_PATH", "/uploads")
    temp_extension = os.environ.get("SFTP_TEMP_EXTENSION", ".uploading")
    retry_count = int(os.environ.get("SFTP_RETRY_COUNT", "3"))
    retry_delay = int(os.environ.get("SFTP_RETRY_DELAY", "30"))
    watch_path = os.environ.get("WATCH_PATH", "/downloads/complete")

    uploader = SFTPUploader(
        host=host,
        port=port,
        user=user,
        key_path=key_path,
        remote_path=remote_path,
        temp_extension=temp_extension,
        retry_count=retry_count,
        retry_delay=retry_delay,
    )

    logger.info(f"SFTP target: {user}@{host}:{port}{remote_path}")
    watch(watch_path, uploader)


if __name__ == "__main__":
    main()

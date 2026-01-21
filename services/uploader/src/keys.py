import logging
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ed25519

logger = logging.getLogger(__name__)

KEY_DIR = Path("/config/keys")
PRIVATE_KEY = KEY_DIR / "id_ed25519"
PUBLIC_KEY = KEY_DIR / "id_ed25519.pub"


def ensure_keypair() -> Path:
    """Generate SSH keypair if it doesn't exist. Returns path to private key."""
    KEY_DIR.mkdir(parents=True, exist_ok=True)

    if PRIVATE_KEY.exists():
        logger.info(f"Using existing keypair: {PRIVATE_KEY}")
    else:
        logger.info("Generating new Ed25519 SSH keypair...")
        private_key = ed25519.Ed25519PrivateKey.generate()

        # Write private key
        private_pem = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.OpenSSH,
            encryption_algorithm=serialization.NoEncryption(),
        )
        PRIVATE_KEY.write_bytes(private_pem)
        PRIVATE_KEY.chmod(0o600)

        # Write public key
        public_key = private_key.public_key()
        public_ssh = public_key.public_bytes(
            encoding=serialization.Encoding.OpenSSH,
            format=serialization.PublicFormat.OpenSSH,
        )
        PUBLIC_KEY.write_bytes(public_ssh + b" downloader-uploader\n")
        PUBLIC_KEY.chmod(0o644)

        logger.info(f"Keypair generated: {PRIVATE_KEY}")

    # Always print public key on startup for easy access
    if PUBLIC_KEY.exists():
        pub = PUBLIC_KEY.read_text().strip()
        logger.info("=" * 60)
        logger.info("SFTP PUBLIC KEY (add to remote authorized_keys):")
        logger.info(pub)
        logger.info("=" * 60)

    return PRIVATE_KEY

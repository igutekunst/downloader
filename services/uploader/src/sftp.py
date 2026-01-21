import os
import logging
import time
from pathlib import Path

import paramiko

logger = logging.getLogger(__name__)


class SFTPUploader:
    def __init__(
        self,
        host: str,
        port: int,
        user: str,
        key_path: str | None,
        remote_path: str,
        temp_extension: str,
        retry_count: int,
        retry_delay: int,
    ):
        self.host = host
        self.port = port
        self.user = user
        self.key_path = key_path
        self.remote_path = remote_path
        self.temp_extension = temp_extension
        self.retry_count = retry_count
        self.retry_delay = retry_delay

    def _connect(self) -> paramiko.SFTPClient:
        transport = paramiko.Transport((self.host, self.port))
        if self.key_path and os.path.exists(self.key_path):
            pkey = paramiko.Ed25519Key.from_private_key_file(self.key_path)
            transport.connect(username=self.user, pkey=pkey)
        else:
            # Fall back to SSH agent
            transport.connect(username=self.user)
        return paramiko.SFTPClient.from_transport(transport)

    def _mkdir_p(self, sftp: paramiko.SFTPClient, remote_dir: str):
        """Recursively create remote directories."""
        dirs = []
        while remote_dir:
            try:
                sftp.stat(remote_dir)
                break
            except FileNotFoundError:
                dirs.append(remote_dir)
                remote_dir = os.path.dirname(remote_dir)
        for d in reversed(dirs):
            try:
                sftp.mkdir(d)
            except OSError:
                pass  # Already exists

    def _upload_file(self, sftp: paramiko.SFTPClient, local: Path, remote_base: str):
        """Upload a single file with temp extension, then rename."""
        relative = local.name
        remote_temp = f"{remote_base}/{relative}{self.temp_extension}"
        remote_final = f"{remote_base}/{relative}"

        self._mkdir_p(sftp, remote_base)
        logger.info(f"Uploading {local} -> {remote_temp}")
        sftp.put(str(local), remote_temp)
        logger.info(f"Renaming {remote_temp} -> {remote_final}")
        sftp.rename(remote_temp, remote_final)

    def _upload_dir(self, sftp: paramiko.SFTPClient, local: Path, remote_base: str):
        """Recursively upload a directory."""
        remote_dir = f"{remote_base}/{local.name}"
        self._mkdir_p(sftp, remote_dir)

        for item in local.iterdir():
            if item.is_file():
                self._upload_file(sftp, item, remote_dir)
            elif item.is_dir():
                self._upload_dir(sftp, item, remote_dir)

    def upload(self, local_path: Path) -> bool:
        """Upload file or directory with retries."""
        for attempt in range(1, self.retry_count + 1):
            try:
                sftp = self._connect()
                try:
                    if local_path.is_file():
                        self._upload_file(sftp, local_path, self.remote_path)
                    elif local_path.is_dir():
                        self._upload_dir(sftp, local_path, self.remote_path)
                    logger.info(f"Upload complete: {local_path}")
                    return True
                finally:
                    sftp.close()
            except Exception as e:
                logger.error(f"Attempt {attempt}/{self.retry_count} failed: {e}")
                if attempt < self.retry_count:
                    time.sleep(self.retry_delay)
        logger.error(f"Upload failed after {self.retry_count} attempts: {local_path}")
        return False

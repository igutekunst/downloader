import logging
import time
from pathlib import Path
from threading import Timer

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler, FileCreatedEvent, DirCreatedEvent

from .sftp import SFTPUploader

logger = logging.getLogger(__name__)

# Debounce delay to wait for file writes to settle
DEBOUNCE_SECONDS = 10


class UploadHandler(FileSystemEventHandler):
    def __init__(self, uploader: SFTPUploader):
        self.uploader = uploader
        self._pending: dict[str, Timer] = {}

    def _schedule_upload(self, path: Path):
        """Schedule upload after debounce delay."""
        key = str(path)
        if key in self._pending:
            self._pending[key].cancel()

        def do_upload():
            del self._pending[key]
            if path.exists():
                logger.info(f"Starting upload: {path}")
                self.uploader.upload(path)

        timer = Timer(DEBOUNCE_SECONDS, do_upload)
        self._pending[key] = timer
        timer.start()

    def on_created(self, event: FileCreatedEvent | DirCreatedEvent):
        path = Path(event.src_path)
        # Only handle top-level items in watch directory
        if path.parent == Path(self.uploader.remote_path).parent:
            return
        logger.info(f"Detected: {path}")
        self._schedule_upload(path)


def watch(watch_path: str, uploader: SFTPUploader):
    """Start watching directory for new files/folders."""
    path = Path(watch_path)
    path.mkdir(parents=True, exist_ok=True)

    handler = UploadHandler(uploader)
    observer = Observer()
    observer.schedule(handler, str(path), recursive=False)
    observer.start()

    logger.info(f"Watching {path} for completed downloads...")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()

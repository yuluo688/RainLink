"""Stage verified Go modules without changing the read-only module cache."""

from pathlib import Path
import shutil
import stat


def copy_module_sources(source: Path, destination: Path) -> None:
    """Leave disposable source directories writable for local extensions."""
    def writable_directories(root: Path) -> None:
        if root.is_dir():
            for path in [root, *(p for p in root.rglob("*") if p.is_dir())]:
                path.chmod(path.stat().st_mode | stat.S_IWUSR)

    # A failed or repeated build can already contain copied cache directories.
    writable_directories(destination)
    shutil.copytree(source, destination, dirs_exist_ok=True,
                    copy_function=shutil.copyfile)
    writable_directories(destination)

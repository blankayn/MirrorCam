"""Create a portable source archive without build products or validation dependencies."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
destination = root / "build/MirrorCam-source.zip"
destination.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(destination, "w", ZIP_DEFLATED) as archive:
    for file in sorted(root.rglob("*")):
        relative = file.relative_to(root)
        if file.is_file() and not any(part in {"build", ".git", "DerivedData", "__pycache__", "xcuserdata"} for part in relative.parts):
            archive.write(file, "MirrorCam/" + relative.as_posix())
with ZipFile(destination) as archive:
    assert archive.testzip() is None, "Archive integrity check failed"
    print(f"Created {destination}: {len(archive.namelist())} files, {destination.stat().st_size:,} bytes")

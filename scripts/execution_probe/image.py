#!/usr/bin/env python3
"""Build an offline, RAM-only ARM64 guest. No host extraction or Linux execution."""
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import stat
import tarfile
import urllib.request
import zlib

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUTPUT = ROOT / ".build/execution-probe"


def artifact(item):
    url = item["url"]
    if not url.startswith("https://dl-cdn.alpinelinux.org/alpine/v3.22/"):
        raise ValueError("Only the pinned official Alpine mirror is permitted")
    path = OUTPUT / "downloads" / url.rsplit("/", 1)[1]
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        print(f"Download {path.name}: {item['bytes']} bytes", flush=True)
        with urllib.request.urlopen(url, timeout=60) as response:
            data = response.read(item["bytes"] + 1)
        check(data, item)
        temporary = path.with_suffix(".partial")
        temporary.write_bytes(data)
        temporary.replace(path)
    data = path.read_bytes()
    check(data, item)
    return data


def check(data, item):
    if len(data) != item["bytes"] or hashlib.sha256(data).hexdigest() != item["sha256"]:
        raise ValueError(f"Size/SHA256 mismatch: {item['name']}; no automatic fingerprint refresh")


def archive_entries(data):
    entries = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for entry in archive:
            name = entry.name.removeprefix("./").rstrip("/")
            if not name:
                continue
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts:
                raise ValueError("Archive traversal")
            if entry.isdir():
                entries[name] = (stat.S_IFDIR | 0o755, b"")
            elif entry.issym():
                entries[name] = (stat.S_IFLNK | 0o777, entry.linkname.encode())
            elif entry.isfile():
                entries[name] = (stat.S_IFREG | (entry.mode & 0o755), archive.extractfile(entry).read())
            elif entry.islnk():
                entries[name] = (stat.S_IFREG | (entry.mode & 0o755), archive.extractfile(entry).read())
            # Device files are not copied. Linux mounts its own devtmpfs.
    return entries


def cpio(entries):
    """Deterministic newc without extracting tar/symlinks onto the host."""
    result = io.BytesIO()
    for inode, (name, (mode, data)) in enumerate(
        sorted(entries.items()) + [("TRAILER!!!", (0, b""))], 1
    ):
        encoded = name.encode() + b"\0"
        fields = [inode, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(encoded), 0]
        result.write(b"070701" + "".join(f"{value:08x}" for value in fields).encode())
        result.write(encoded)
        result.write(b"\0" * (-result.tell() % 4))
        result.write(data)
        result.write(b"\0" * (-result.tell() % 4))
    return result.getvalue()


def main():
    lock = json.loads((HERE / "image-lock.json").read_text())
    items = {item["name"]: item for item in lock["artifacts"]}
    if lock["formatVersion"] != 1 or lock["architecture"] != "aarch64":
        raise ValueError("Unsupported guest lock")
    entries = archive_entries(artifact(items["rootfs"]))
    kernel_archive = archive_entries(artifact(items["kernel"]))
    compressed = kernel_archive["boot/vmlinuz-virt"][1]
    offset = compressed.find(b"\x1f\x8b\x08")
    if offset < 0:
        raise ValueError("Expected pinned Alpine ARM64 gzip EFI stub")
    kernel = zlib.decompress(compressed[offset:], wbits=31)
    if kernel[56:60] != b"ARM\x64":
        raise ValueError("Not an ARM64 Linux Image")
    for directory in ["dev", "proc", "sys", "run", "work", "packages"]:
        entries[directory] = (stat.S_IFDIR | 0o755, b"")
    for name, item in items.items():
        if name not in ["rootfs", "kernel"]:
            entries["packages/" + item["url"].rsplit("/", 1)[1]] = (stat.S_IFREG | 0o444, artifact(item))
    # Kernel itself is a signed Alpine APK; verify it in the guest as well.
    entries["packages/linux-virt-" + items["kernel"]["version"] + ".apk"] = (
        stat.S_IFREG | 0o444, artifact(items["kernel"]))
    # Do not install the kernel package (it pulls initramfs tooling). Verify it only.
    # The agent moves it aside before apk add.
    entries["init"] = (stat.S_IFREG | 0o755, (HERE / "init.sh").read_bytes())
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "Image").write_bytes(kernel)
    (OUTPUT / "initrd.gz").write_bytes(gzip.compress(cpio(entries), compresslevel=1, mtime=0))
    print(f"Guest prepared in {OUTPUT}; no files mounted from the host", flush=True)


if __name__ == "__main__":
    main()

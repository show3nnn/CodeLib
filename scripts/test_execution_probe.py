"""Fast image/protocol build invariants; no VM boot, network or host execution."""
import io
import json
from pathlib import Path
import stat
import tarfile
import unittest

from execution_probe.image import archive_entries, check, cpio


class ExecutionImageTests(unittest.TestCase):
    def test_locked_download_cannot_silently_change(self):
        import hashlib
        item = dict(name="fixture", bytes=3, sha256=hashlib.sha256(b"abc").hexdigest())
        check(b"abc", item)
        for value in [b"abd", b"abcd", b""]:
            with self.assertRaises(ValueError):
                check(value, item)

    def test_archive_traversal_rejected_without_host_extraction(self):
        for name in ["/escape", "../escape", "lib/../../escape"]:
            buffer = io.BytesIO()
            with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
                entry = tarfile.TarInfo(name)
                entry.size = 1
                archive.addfile(entry, io.BytesIO(b"x"))
            with self.assertRaises(ValueError):
                archive_entries(buffer.getvalue())

    def test_symlinks_are_inert_cpio_data_and_suid_is_removed(self):
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
            link = tarfile.TarInfo("bin/escape")
            link.type = tarfile.SYMTYPE
            link.linkname = "/host/secret"
            archive.addfile(link)
            file = tarfile.TarInfo("bin/tool")
            file.mode = 0o6755
            file.size = 3
            archive.addfile(file, io.BytesIO(b"abc"))
        entries = archive_entries(buffer.getvalue())
        self.assertEqual(entries["bin/escape"], (stat.S_IFLNK | 0o777, b"/host/secret"))
        self.assertEqual(entries["bin/tool"][0] & 0o6000, 0)
        first = cpio(entries)
        second = cpio(dict(reversed(list(entries.items()))))
        self.assertEqual(first, second)
        self.assertTrue(first.startswith(b"070701"))
        self.assertIn(b"TRAILER!!!\0", first)

    def test_guest_lock_has_only_pinned_official_artifacts(self):
        root = Path(__file__).resolve().parent
        lock = json.loads((root / "execution_probe/image-lock.json").read_text())
        self.assertEqual(lock["architecture"], "aarch64")
        names = [item["name"] for item in lock["artifacts"]]
        self.assertEqual(len(names), len(set(names)))
        self.assertTrue({"kernel", "rootfs", "g++", "musl-dev"} <= set(names))
        for item in lock["artifacts"]:
            self.assertTrue(item["url"].startswith("https://dl-cdn.alpinelinux.org/alpine/v3.22/"))
            self.assertRegex(item["sha256"], r"^[a-f0-9]{64}$")
            self.assertGreater(item["bytes"], 0)
            self.assertLess(item["bytes"], 80 * 1024 * 1024)


if __name__ == "__main__":
    unittest.main()

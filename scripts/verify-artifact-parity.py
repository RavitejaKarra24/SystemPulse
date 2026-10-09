#!/usr/bin/env python3
"""Read-only bundle metadata/payload parity; codesign verification stays in the shell driver."""

import argparse
import hashlib
import os
import plistlib
import stat
import sys
from pathlib import Path


def manifest(bundle):
    if bundle.is_symlink() or not bundle.is_dir():
        raise ValueError(f"Not a regular app bundle directory: {bundle}")
    result = {}
    for directory, directories, files in os.walk(bundle, followlinks=False):
        for name in directories + files:
            path = Path(directory) / name
            relative = str(path.relative_to(bundle))
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                result[relative] = ("symlink", os.readlink(path))
            elif stat.S_ISDIR(mode):
                result[relative] = ("directory",)
            elif stat.S_ISREG(mode):
                digest = hashlib.sha256()
                with path.open("rb") as stream:
                    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                        digest.update(chunk)
                result[relative] = ("file", mode & 0o111, digest.hexdigest())
            else:
                raise ValueError(f"Unsupported bundle entry: {path}")
    return result


def verify(source_plist, archive_app, comparison_apps):
    with source_plist.open("rb") as stream:
        expected = plistlib.load(stream)
    with (archive_app / "Contents/Info.plist").open("rb") as stream:
        actual = plistlib.load(stream)
    if expected != actual:
        keys = sorted(
            key
            for key in expected.keys() | actual.keys()
            if expected.get(key) != actual.get(key)
        )
        raise ValueError(
            f"Archive metadata differs from {source_plist}: {', '.join(keys)}"
        )
    executable_name = expected.get("CFBundleExecutable")
    if (
        not isinstance(executable_name, str)
        or not executable_name
        or Path(executable_name).name != executable_name
    ):
        raise ValueError("Invalid CFBundleExecutable")
    executable = archive_app / "Contents/MacOS" / executable_name
    icon = archive_app / "Contents/Resources/AppIcon.icns"
    if (
        executable.is_symlink()
        or not executable.is_file()
        or not executable.stat().st_mode & 0o111
    ):
        raise ValueError(f"Missing regular executable: {executable}")
    if icon.is_symlink() or not icon.is_file():
        raise ValueError(f"Missing regular icon: {icon}")
    archived = manifest(archive_app)
    for bundle in comparison_apps:
        other = manifest(bundle)
        differences = sorted(
            key
            for key in archived.keys() | other.keys()
            if archived.get(key) != other.get(key)
        )
        if differences:
            raise ValueError(
                f"Bundle parity failed for {bundle}: {', '.join(differences)}"
            )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-plist", required=True, type=Path)
    parser.add_argument("--archive-app", required=True, type=Path)
    parser.add_argument("--compare-app", action="append", default=[], type=Path)
    args = parser.parse_args()
    try:
        verify(args.source_plist, args.archive_app, args.compare_app)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"Artifact verification: {error}", file=sys.stderr)
        return 1
    print("Archive metadata and all requested bundle payloads match.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

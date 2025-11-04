#!/usr/bin/env python3
"""
Add Apache 2.0 copyright header to source files under a target directory.

Supported extensions (default): dart, c, cc, cpp, h, hpp

Usage:
  python3 tools/add_apache_header.py --path lib --owner "kozakemi" --year 2025
  python3 tools/add_apache_header.py --path elinux --owner "kozakemi" --ext "c,cc,cpp,h,hpp"

Defaults:
  --path defaults to "lib"
  --owner defaults to "kozakemi"
  --year defaults to current year
  --ext  defaults to "dart,c,cc,cpp,h,hpp" (comma-separated)

Idempotent:
  Skips files that already contain the Apache 2.0 header.
"""

import argparse
import os
import sys
import datetime

HEADER_TEMPLATE_BLOCK = """/*
Copyright {year} {owner}

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
"""


def has_apache_header(text: str) -> bool:
    """Detect if file already contains Apache 2.0 header markers."""
    markers = [
        "Licensed under the Apache License, Version 2.0",
        "http://www.apache.org/licenses/LICENSE-2.0",
        "limitations under the License",
    ]
    top_chunk = text[:5000]  # check first ~5KB to keep it fast
    return all(m in top_chunk for m in markers)


def prepend_header(path: str, owner: str, year: int) -> bool:
    """Prepend header to file if missing. Return True if modified."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
    except UnicodeDecodeError:
        # Skip non-UTF8 files
        return False

    if has_apache_header(content):
        return False

    header = HEADER_TEMPLATE_BLOCK.format(owner=owner, year=year).rstrip() + "\n\n"
    new_content = header + content

    with open(path, "w", encoding="utf-8") as f:
        f.write(new_content)
    return True


def parse_exts(ext_arg: str):
    exts = [e.strip().lower() for e in ext_arg.split(',') if e.strip()]
    normalized = set()
    for e in exts:
        if not e:
            continue
        if e.startswith('.'):
            normalized.add(e)
        else:
            normalized.add('.' + e)
    return normalized


def main():
    parser = argparse.ArgumentParser(description="Add Apache header to Dart files")
    parser.add_argument("--path", default="lib", help="Target directory (default: lib)")
    parser.add_argument("--owner", default="kozakemi", help="Copyright owner name")
    parser.add_argument(
        "--year",
        type=int,
        default=datetime.datetime.now().year,
        help="Copyright year (default: current year)",
    )
    parser.add_argument("--dry-run", action="store_true", help="Only report, do not modify")
    parser.add_argument(
        "--ext",
        default="dart,c,cc,cpp,h,hpp",
        help="Comma-separated list of file extensions to process",
    )
    args = parser.parse_args()

    root = os.path.abspath(args.path)
    if not os.path.isdir(root):
        print(f"[ERROR] Path not found or not a directory: {root}", file=sys.stderr)
        sys.exit(1)

    exts = parse_exts(args.ext)

    modified = []
    skipped = []
    failed = []
    total = 0

    for dirpath, dirnames, filenames in os.walk(root):
        for name in filenames:
            _, ext = os.path.splitext(name)
            if ext.lower() not in exts:
                continue
            total += 1
            fp = os.path.join(dirpath, name)

            try:
                with open(fp, "r", encoding="utf-8") as f:
                    content = f.read()
            except Exception as e:
                failed.append((fp, str(e)))
                continue

            if has_apache_header(content):
                skipped.append(fp)
                continue

            if args.dry_run:
                modified.append(fp)
                continue

            try:
                if prepend_header(fp, args.owner, args.year):
                    modified.append(fp)
                else:
                    skipped.append(fp)
            except Exception as e:
                failed.append((fp, str(e)))

    print(f"Scanned Dart files: {total}")
    print(f"To modify: {len(modified)}")
    print(f"Already had header: {len(skipped)}")
    if modified:
        print("\nModified files:")
        for fp in modified:
            print(f"  + {fp}")
    if skipped:
        print("\nSkipped files (header already present):")
        for fp in skipped[:20]:
            print(f"  - {fp}")
        if len(skipped) > 20:
            print(f"  ...and {len(skipped) - 20} more")
    if failed:
        print("\nFailed files:")
        for fp, err in failed:
            print(f"  ! {fp}: {err}")


if __name__ == "__main__":
    main()
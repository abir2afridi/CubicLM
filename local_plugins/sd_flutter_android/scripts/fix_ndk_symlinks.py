#!/usr/bin/env python3
"""Fix broken symlinks in Android NDK extracted with Python zipfile.

Python's zipfile module doesn't preserve Unix symlinks, so files that should
be symlinks are extracted as tiny text files containing the target path.

Usage:
    python3 fix_ndk_symlinks.py ~/tools/android-ndk-r27c
"""
import os
import sys


def fix_symlinks(base_dir):
    fixed = 0
    errors = []

    for root, dirs, files in os.walk(base_dir):
        for name in files:
            path = os.path.join(root, name)
            try:
                size = os.path.getsize(path)
                if size < 100 and not os.path.islink(path):
                    content = open(path, 'rb').read().decode('utf-8', errors='replace').strip()
                    # Heuristic: looks like a relative path and not a script/text file
                    if (
                        content
                        and ('/' in content or content in ('lld',))
                        and not content.startswith('#')
                        and not content.startswith('//')
                    ):
                        target = os.path.join(root, content)
                        if os.path.exists(target) and target != path:
                            print(f'Fix symlink: {path} -> {content}')
                            os.remove(path)
                            os.symlink(content, path)
                            fixed += 1
                        else:
                            abs_target = os.path.join(base_dir, content.lstrip('/'))
                            if os.path.exists(abs_target) and abs_target != path:
                                rel = os.path.relpath(abs_target, root)
                                print(f'Fix symlink (abs): {path} -> {rel}')
                                os.remove(path)
                                os.symlink(rel, path)
                                fixed += 1
                            else:
                                errors.append(f'Missing target for {path}: {content}')
            except Exception as e:
                errors.append(f'Error on {path}: {e}')

    print(f'\nFixed {fixed} symlinks')
    if errors:
        print(f'{len(errors)} errors (showing first 20):')
        for e in errors[:20]:
            print(f'  {e}')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <ndk-dir>')
        sys.exit(1)
    fix_symlinks(sys.argv[1])

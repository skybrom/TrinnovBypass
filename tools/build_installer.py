#!/usr/bin/env python3
"""Rebuilds 'Install Trinnov Bypass.command' by embedding src/trinnov_bypass.py into the template.

src/ is the source of truth; run this after editing it:  python3 tools/build_installer.py
"""
import os
import stat

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
template = open(os.path.join(root, "installer", "Install Trinnov Bypass.command.in")).read()
script = open(os.path.join(root, "src", "trinnov_bypass.py")).read().rstrip("\n")
assert "PYEOF" not in script, "script must not contain the heredoc terminator"

out = os.path.join(root, "Install Trinnov Bypass.command")
with open(out, "w") as f:
    f.write(template.replace("@@SCRIPT@@", script))
os.chmod(out, os.stat(out).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
print("wrote", out)

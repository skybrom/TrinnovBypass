#!/bin/bash
# Installs "Trinnov Bypass": bypass / engage / toggle the Trinnov Nova's calibration (the Optimizer)
# from a Stream Deck button or a keyboard shortcut. No configuration, no admin password.
set -e
SUPPORT="$HOME/Library/Application Support/TrinnovBypass"
APPS="$HOME/Applications/Trinnov Bypass"
SERVICES="$HOME/Library/Services"
SCRIPT="$SUPPORT/trinnov_bypass.py"

echo "Installing Trinnov Bypass..."
if ! /usr/bin/python3 --version >/dev/null 2>&1; then
  echo
  echo "macOS needs to install its developer tools (Python) first."
  echo "Click Install in the window that just appeared, then run this installer again."
  exit 1
fi

mkdir -p "$SUPPORT" "$APPS" "$SERVICES"

cat > "$SCRIPT" <<'PYEOF'
#!/usr/bin/env python3
"""Trinnov Nova: bypass or engage the calibration (the 'Optimizer' button), from the command line.

    trinnov_bypass.py bypass    calibration OFF (processing bypassed)
    trinnov_bypass.py engage    calibration ON
    trinnov_bypass.py toggle    flip it
    trinnov_bypass.py status    just report

It sends the same message as the Optimizer button of the Nova's web interface. The Nova is found
automatically on the local network. Exit code 0 on success, 1 on failure; the last line printed
is a short human-readable result.
"""
import base64, json, os, re, socket, struct, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

SUPPORT = os.path.expanduser("~/Library/Application Support/TrinnovBypass")
CACHE = os.path.join(SUPPORT, "last_ip")
PORT = int(os.environ.get("TRINNOV_PORT", "80"))
BYPASS_PATH = "/optimizer/volume/bypass"


class Failure(Exception):
    pass


# ---------------------------------------------------------------- finding the Nova
def is_nova(ip, timeout):
    try:
        with socket.create_connection((ip, PORT), timeout=timeout) as s:
            s.settimeout(timeout + 1)
            s.sendall(b"GET / HTTP/1.0\r\nHost: " + ip.encode() + b"\r\n\r\n")
            return b"TrinnovDisplayServer" in s.recv(1024)
    except OSError:
        return False


def local_prefixes():
    forced = os.environ.get("TRINNOV_PREFIXES")
    if forced:
        return forced.split(",")
    out = subprocess.run(["/sbin/ifconfig"], capture_output=True, text=True).stdout
    found = []
    for m in re.finditer(r"inet (\d+\.\d+\.\d+)\.\d+ netmask", out):
        p = m.group(1)
        if not p.startswith(("127.", "169.254.")) and p not in found:
            found.append(p)
    return found


def find_nova():
    override = os.environ.get("TRINNOV_IP")
    if override:
        return override
    try:
        cached = open(CACHE).read().strip()
    except OSError:
        cached = ""
    if cached and is_nova(cached, 1.0):
        return cached
    candidates = [f"{p}.{i}" for p in local_prefixes() for i in range(1, 255)]
    with ThreadPoolExecutor(max_workers=128) as pool:
        hits = [ip for ip, ok in zip(candidates, pool.map(lambda ip: is_nova(ip, 0.7), candidates)) if ok]
    if not hits:
        raise Failure("No Trinnov Nova found on the network")
    try:
        os.makedirs(SUPPORT, exist_ok=True)
        open(CACHE, "w").write(hits[0])
    except OSError:
        pass
    return hits[0]


# ---------------------------------------------------------------- talking to the Nova
def mask_frame(payload):
    mask = os.urandom(4)
    n = len(payload)
    hdr = bytes([0x82, 0x80 | n]) if n < 126 else bytes([0x82, 0x80 | 126]) + struct.pack(">H", n)
    return hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload))


def message(kind, path, obj=None):
    p = path.encode()
    body = json.dumps(obj).encode() if obj is not None else b""
    return mask_frame(struct.pack(">ibi", 5 + len(p) + len(body), kind, len(p)) + p + body)


class Nova:
    GET, PUBREQ = 0, 3

    def __init__(self, ip):
        try:
            self.sock = socket.create_connection((ip, PORT), timeout=4)
            key = base64.b64encode(os.urandom(16)).decode()
            self.sock.sendall((f"GET /ws HTTP/1.1\r\nHost: {ip}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                               f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
            resp = self.sock.recv(1024)
        except OSError as e:
            raise Failure(f"Cannot reach the Nova at {ip} ({e})")
        if b" 101 " not in resp.split(b"\r\n")[0]:
            raise Failure("The Nova refused the connection")
        self.buf = b""

    def read_value(self, path, timeout=3.0):
        """Ask for a value and wait for its answer ({"_": value})."""
        self.sock.sendall(message(self.GET, path))
        end = time.time() + timeout
        pattern = re.escape(path.encode()) + rb'\{"_":\s*(true|false|null|-?[\d.]+|"[^"]*")\}'
        self.sock.settimeout(0.5)
        while time.time() < end:
            try:
                data = self.sock.recv(65536)
            except socket.timeout:
                continue
            except OSError as e:
                raise Failure(f"Connection to the Nova lost ({e})")
            if not data:
                raise Failure("Connection to the Nova closed")
            self.buf += data
            m = re.search(pattern, self.buf)
            if m:
                self.buf = b""
                return json.loads(m.group(1))
        raise Failure("The Nova did not answer")

    def publish(self, path, obj):
        self.sock.sendall(message(self.PUBREQ, path, obj))

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def describe(bypassed):
    return "Calibration BYPASSED (off)" if bypassed else "Calibration ACTIVE (on)"


def run(command):
    nova = Nova(find_nova())
    try:
        current = nova.read_value(BYPASS_PATH)
        if not isinstance(current, bool):
            raise Failure(f"Unexpected answer from the Nova: {current!r}")
        if command == "status":
            return describe(current)
        wanted = {"bypass": True, "engage": False, "toggle": not current}[command]
        if wanted != current:
            nova.publish("/optimizer/volume", {"bypass": wanted})
            time.sleep(0.3)
            after = nova.read_value(BYPASS_PATH)
            if after != wanted:
                raise Failure("The Nova did not accept the change")
            return describe(after)
        return describe(current) + " (already)"
    finally:
        nova.close()


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "toggle"
    aliases = {"on": "bypass", "off": "engage"}  # 'on' = bypass is on
    command = aliases.get(command, command)
    if command not in ("bypass", "engage", "toggle", "status"):
        print("Usage: trinnov_bypass.py bypass|engage|toggle|status")
        sys.exit(2)
    try:
        print(run(command))
    except Failure as e:
        print(f"Trinnov: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
PYEOF
chmod 755 "$SCRIPT"

# --- the four small apps (Stream Deck: System > Open) -------------------------------------
make_app() {  # make_app "<name>" <command>
  local name="$1" cmd="$2" app="$APPS/$1.app" src
  src="$(mktemp -t trinnovapp).applescript"
  cat > "$src" <<'ASEOF'
try
	set r to do shell script "/usr/bin/python3 " & quoted form of "@SCRIPT@" & " @CMD@ 2>&1"
	display notification r with title "Trinnov"
on error e
	display notification e with title "Trinnov" subtitle "Failed"
end try
ASEOF
  sed -i '' -e "s|@SCRIPT@|$SCRIPT|" -e "s|@CMD@|$cmd|" "$src"
  rm -rf "$app"
  osacompile -o "$app" "$src" 2>/dev/null
  defaults write "$app/Contents/Info" LSUIElement -bool true   # no Dock icon flash
  codesign --force --sign - "$app" >/dev/null 2>&1 || true
  rm -f "$src"
}
make_app "Trinnov Bypass Toggle" toggle
make_app "Trinnov Bypass On" bypass
make_app "Trinnov Bypass Off" engage
make_app "Trinnov Bypass Status" status

# --- the four Quick Actions (assign a keyboard shortcut in System Settings) ---------------
/usr/bin/python3 - "$SERVICES" "$SCRIPT" <<'QAEOF'
import os, plistlib, sys, uuid

services, script = sys.argv[1:3]
actions = {"Trinnov Bypass Toggle": "toggle", "Trinnov Bypass On": "bypass",
           "Trinnov Bypass Off": "engage", "Trinnov Bypass Status": "status"}

for name, cmd in actions.items():
    shell = (f'R=$(/usr/bin/python3 "{script}" {cmd} 2>&1)\n'
             '/usr/bin/osascript -e \'on run argv\' -e \'display notification (item 1 of argv) '
             'with title "Trinnov"\' -e \'end run\' "$R"\n')
    action = {
        "AMAccepts": {"Container": "List", "Optional": True, "Types": ["com.apple.cocoa.string"]},
        "AMActionVersion": "2.0.3", "AMApplication": ["Automator"],
        "AMParameterProperties": {k: {} for k in ("COMMAND_STRING", "CheckedForUserDefaultShell",
                                                  "inputMethod", "shell", "source")},
        "AMProvides": {"Container": "List", "Types": ["com.apple.cocoa.string"]},
        "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
        "ActionName": "Run Shell Script",
        "ActionParameters": {"COMMAND_STRING": shell, "CheckedForUserDefaultShell": True,
                             "inputMethod": 1, "shell": "/bin/bash", "source": ""},
        "BundleIdentifier": "com.apple.RunShellScript", "CFBundleVersion": "2.0.3",
        "CanShowSelectedItemsWhenRun": False, "CanShowWhenRun": True,
        "Category": ["AMCategoryUtilities"], "Class Name": "RunShellScriptAction",
        "InputUUID": str(uuid.uuid4()).upper(), "Keywords": ["Shell", "Script"],
        "OutputUUID": str(uuid.uuid4()).upper(), "UUID": str(uuid.uuid4()).upper(),
        "UnlocalizedApplications": ["Automator"], "arguments": {}, "isViewVisible": True,
        "location": "309.000000:253.000000",
        "nibPath": "/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib",
    }
    wflow = {
        "AMApplicationBuild": "523", "AMApplicationVersion": "2.10", "AMDocumentVersion": "2",
        "actions": [{"action": action, "isViewVisible": True}], "connectors": {},
        "workflowMetaData": {
            "serviceInputTypeIdentifier": "com.apple.Automator.nothing",
            "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
            "serviceProcessesInput": 0,
            "workflowTypeIdentifier": "com.apple.Automator.servicesMenu"},
    }
    info = {"NSServices": [{"NSMenuItem": {"default": name}, "NSMessage": "runWorkflowAsService"}]}
    contents = os.path.join(services, name + ".workflow", "Contents")
    os.makedirs(contents, exist_ok=True)
    with open(os.path.join(contents, "document.wflow"), "wb") as f:
        plistlib.dump(wflow, f)
    with open(os.path.join(contents, "Info.plist"), "wb") as f:
        plistlib.dump(info, f)
QAEOF
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true

# --- find the Nova now, so the first button press is instant -------------------------------
/usr/bin/python3 "$SCRIPT" status || true

cat <<'DONE'

Done.

STREAM DECK  Drag a "System > Open" action onto a key, click "App / File" and choose one of the
             apps in  ~/Applications/Trinnov Bypass/ :
               Trinnov Bypass Toggle   flip the calibration on/off
               Trinnov Bypass On       bypass the calibration (off)
               Trinnov Bypass Off      engage the calibration (on)
               Trinnov Bypass Status   just report the current state

KEYBOARD     System Settings > Keyboard > Keyboard Shortcuts > Services > General:
             tick "Trinnov Bypass Toggle" (and the others if you want), click "none" next to
             it and press the key combination you want.
             (a Stream Deck "Hotkey" action can press that same combination.)

The first time, macOS may ask to allow notifications and access to the local network: click Allow.
DONE

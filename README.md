# Trinnov Bypass

Bypass, engage or toggle the **calibration** of your **Trinnov Nova** (the *Optimizer* button) from a **Stream Deck** key or a **keyboard shortcut**, without opening the Trinnov app.

> **Unofficial.** Not affiliated with or endorsed by Trinnov Audio. It sends the same message as the *Optimizer* button of the Nova's own web interface. Use at your own risk.

> **Heads up:** bypassing the calibration changes how your system sounds, and levels can change noticeably. Test with your monitors at a low level.

## Install

1. Download this repository (green **Code** button → **Download ZIP**) and unzip it.
2. Double-click **`Install Trinnov Bypass.command`** (if macOS blocks it: right-click → **Open** → **Open**).
3. No password and no configuration: the Nova is found on your network automatically.

To remove everything, double-click **`Uninstall Trinnov Bypass.command`**.

### Requirements

- macOS with Python 3 (macOS offers to install Apple's developer tools the first time if it is missing; click *Install*, then run the installer again).
- The Mac and the Nova on the same local network.
- A Trinnov **Nova** (see [Compatibility](#compatibility)).

## What you get

The installer creates four small apps in `~/Applications/Trinnov Bypass/` and four matching Quick Actions:

| Name | Does |
|---|---|
| **Trinnov Bypass Toggle** | flips the calibration on / off |
| **Trinnov Bypass On** | bypasses the calibration (calibration **off**) |
| **Trinnov Bypass Off** | engages the calibration (calibration **on**) |
| **Trinnov Bypass Status** | just reports the current state |

Each shows a macOS notification with the result, for example *Calibration BYPASSED (off)*.

## Stream Deck

1. In the Stream Deck app, drag a **System → Open** action onto a key.
2. Under **App / File**, choose one of the apps in `~/Applications/Trinnov Bypass/`.

## Keyboard shortcut

1. Open **System Settings → Keyboard → Keyboard Shortcuts… → Services**.
2. Under **General**, tick **Trinnov Bypass Toggle** (and the others if you like).
3. Click **none** next to it and press the key combination you want.

A Stream Deck **Hotkey** action can press that same combination, if you prefer your shortcut to live on the deck.

The first time you use it, macOS may ask to allow notifications and access to the local network. Click **Allow**.

## Command line

```bash
python3 "$HOME/Library/Application Support/TrinnovBypass/trinnov_bypass.py" toggle   # bypass | engage | toggle | status
```

Prints a one-line result and exits `0` on success, `1` on failure (for example, the Nova is off).

## How it works

The Nova's web interface talks to the unit over a websocket (`ws://<nova>/ws`). The *Optimizer* button reads and sets `/optimizer/volume/bypass`. This tool does the same: it reads the current value, sets the one you asked for, then reads it back to confirm and reports the real state.

The Nova is found by scanning your local `/24` subnet for a web server identifying itself as `TrinnovDisplayServer`; its address is remembered.

The full code is a single file, [`src/trinnov_bypass.py`](src/trinnov_bypass.py). The installer embeds exactly this file (`python3 tools/build_installer.py` regenerates it).

## Compatibility

Tested on one setup: **Nova, firmware 5.3.0pre3**, **macOS 26 (Apple silicon)**. Other Trinnov products (Altitude, etc.) use a different interface and are **untested**. Reports and pull requests are welcome.

## Related

[Trinnov Auto Off](https://github.com/skybrom/TrinnovAutoOff) switches the Nova off when your Mac shuts down.

## License

MIT, see [LICENSE](LICENSE).

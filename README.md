# nightshift-fix

A tiny macOS background helper that fixes a bug where **Night Shift's warm filter disappears after you disconnect an external monitor or the display goes to sleep**. Night Shift still shows as "on" in Control Center, but the screen has lost its warm tint.

🌐 **Project page:** https://hugomach.github.io/nightshift-fix/

---

## Why it happens

Whenever the display configuration changes (a monitor is plugged in or unplugged, the screen sleeps, the Mac wakes), WindowServer resets the displays' color (gamma) tables. CoreBrightness, the system service that drives Night Shift, sometimes fails to re-apply its filter afterwards. The "on" state is kept, but the filter is gone. That's why manually toggling Night Shift off and on usually fixes it.

It's most likely to happen when several changes stack up, for example when you unplug a monitor while the display is asleep.

## What nsfix does

`nsfix` is a single small Objective‑C program (~130 lines) that runs as a LaunchAgent and:

1. listens for display reconfiguration (`CGDisplayRegisterReconfigurationCallback`, `NSApplicationDidChangeScreenParametersNotification`),
2. listens for screen and system wake (`NSWorkspace` notifications),
3. **polls the display list every 10 seconds** as a fallback, because some changes (e.g. unplugging a monitor while the screen is off) don't deliver any event,
4. after a change, if Night Shift was on, **re-sets the schedule mode** so CoreBrightness re-evaluates sunset/sunrise (or your custom schedule) itself,
5. if the schedule says Night Shift should be on, quickly toggles it off and on so the filter is applied again,
6. repeats steps 4–5 at **2, 8 and 20 seconds** after the last event, since displays can take a while to settle.

It never turns Night Shift on if you had it off, and it **never turns it on in daylight**: after the Mac sleeps through sunrise, macOS can still report Night Shift as on at wake, so the helper lets the schedule decide instead of forcing it on. It doesn't touch your schedule or color temperature.

It uses the private `CBBlueLightClient` class from `CoreBrightness.framework`, the same one Control Center uses.

## Requirements

- macOS with Night Shift (tested on macOS 27, Apple Silicon)
- Xcode Command Line Tools (`xcode-select --install`) to compile

## Install

```bash
git clone https://github.com/hugomach/nightshift-fix.git
cd nightshift-fix
./install.sh
```

The script compiles the helper to `~/.local/nightshift-fix/nsfix`, creates `~/Library/LaunchAgents/com.user.nightshift-fix.plist` and starts it. From then on it starts automatically at every login.

## Check that it's running

```bash
launchctl list | grep nightshift-fix   # shows a PID when running
tail -f ~/Library/Logs/nsfix.log       # live log; unplug/replug a monitor
```

Every time it re-applies the filter, the log gets a line `nsfix: re-applying Night Shift (reason)`. During the day you'll see `nsfix: schedule says off (reason)` instead.

### About the log

The log lives at `~/Library/Logs/nsfix.log` (also visible in **Console.app → Log Reports**). It isn't rotated automatically, but it's tiny: one ~80‑byte line per event, roughly 0.5 MB per year even with frequent use. You can delete it at any time with `rm ~/Library/Logs/nsfix.log`. The helper creates it again on next start.

## Uninstall

From the repo folder:

```bash
./uninstall.sh
```

Or manually, without the repo:

```bash
launchctl bootout gui/$(id -u)/com.user.nightshift-fix
rm ~/Library/LaunchAgents/com.user.nightshift-fix.plist
rm -rf ~/.local/nightshift-fix ~/Library/Logs/nsfix.log
```

Nothing else is left behind, and your Night Shift settings are untouched.

## Files

| Path | What it is |
|---|---|
| `src/nsfix.m` | helper source code |
| `install.sh` | compiles and installs the LaunchAgent |
| `uninstall.sh` | removes everything |
| `docs/index.html` | project page (GitHub Pages) |

## Troubleshooting

- **The filter still disappears:** make sure the helper is running (`launchctl list | grep nightshift-fix`) and check the log. If your monitor takes longer to wake, add a longer delay to the `@[@2, @8, @20]` retry list in `src/nsfix.m` and run `./install.sh` again.
- **A brief flicker:** that's expected. The quick off/on toggle is what restores the filter.
- **Stopped working after a macOS update:** `CBBlueLightClient` is a private Apple API and may change. Uninstall and open an issue.

## License

MIT

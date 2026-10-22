# Claude FM

Listen to Claude FM, Anthropic's lo-fi radio, from your shell. It plays audio
only through `mpv`, shows a compact panel with a dancing Clawd, and puts a tiny
equalizer in your bar while it plays.

## Plugin

| Field | Value |
| --- | --- |
| ID | `shadowe1ite/claude-fm` |
| Entries | Bar widget: `widget`; panel: `panel`; control-center shortcut: `shortcut`; service: `service` |

## Requirements

Install these on `PATH`:

- `mpv` plays the stream (audio only, no window).
- `yt-dlp` lets mpv open the YouTube live stream.
- `socat` talks to mpv's IPC socket, so the panel shows mpv's real state.
- `xdg-open` opens the radio's web page from the panel's link button.

This plugin requires Noctalia plugin API 32.

## Usage

Add the `widget` bar widget from the Add-widget picker. It shows a radio glyph
and, while the radio plays, a four-bar equalizer. Click it to open the panel;
right-click it to play or pause.

Add the `shortcut` tile from Settings -> Control Center shortcuts. It shows
whether the radio is playing, and clicking it plays or pauses.

Open the panel from a keybind or a script:

```sh
noctalia msg panel-toggle shadowe1ite/claude-fm:panel
```

The panel has a stop button, a play/pause button, a link to the radio's web
page, a mute button and a volume slider. Clawd idles while the radio is stopped
and dances (idle, headbang, spin) while it plays.

The panel shows what mpv is really doing: Connecting, Live, Paused or Stopped.
Pausing from outside (media keys, `playerctl`) is noticed, and a radio that is
still running when the shell restarts is picked up again.

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `volume` | `int` | `70` | Playback volume, 0 to 100. Changing it here overrides the volume last used in the panel. |
| `autoplay` | `bool` | `false` | Start the radio when the shell loads, unless one is already running. |
| `fps` | `select` | `calm` | Animation rate for the bar equalizer and the panel mascot: `smooth` is 20 fps, `calm` is 10 fps, `off` is static. Lower is lighter on the CPU. |

## IPC

The `service` entry takes these commands, for example from a WM hotkey:

```sh
noctalia msg plugin shadowe1ite/claude-fm:service all toggle
noctalia msg plugin shadowe1ite/claude-fm:service all set-volume 40
```

| Command | Effect |
| --- | --- |
| `toggle` | Pause what plays, resume what is paused, cancel a connection in progress, or start a stopped radio. |
| `play`, `pause`, `stop` | Start or resume, pause, or stop the radio. |
| `volume-up`, `volume-down` | Change the volume by 5. |
| `set-volume <0-100>` | Set the volume. |

## Notes

- **Network:** `mpv` with `yt-dlp` streams one YouTube live stream
  (`https://www.youtube.com/watch?v=tRsQsTMvPNg`). The panel's link button opens
  `https://clau.de/radio` with `xdg-open`. Nothing else touches the network.
- **Processes:** the service starts one `mpv` when you press play and quits it on
  stop. While the radio is active it runs a short `sh` command with `socat` every
  2 seconds (twice a second while connecting) to read mpv's state; while stopped
  it is idle.
- **Files:** the plugin itself reads and writes only `state.json` (the last
  volume) in its data directory; `mpv.sock` (mpv's IPC socket) lives there too.
- **Mascot:** the panel header draws Clawd, the Claude Code mascot, from
  quadrant-block pixel data in `lib/sprite.luau`.

# Lyrics

Synced lyrics for whatever is playing, in the Noctalia bar. Needs Noctalia v5.

It talks to MPRIS directly over D-Bus with `busctl` (comes with systemd), so
there's no playerctl, no polling and nothing to run on the side. Lyrics come
from [LRCLIB](https://lrclib.net) and are cached, so a song you've heard before
loads instantly and works offline.

## Install

Clone it into the local plugins folder and enable it:

```sh
git clone <this repo> ~/.local/share/noctalia/plugins/lyrics
noctalia msg plugins enable shadow/lyrics
```

Then add the **Lyrics** widget to a bar from the widget picker, or by hand:

```toml
[widget.lyrics]
type = "shadow/lyrics:lyrics"
```

## Using it

- Left click opens the lyrics panel.
- Right click plays/pauses the player the widget is showing.
- Middle click opens the widget settings.

The widget only shows lyrics: before the first line, during instrumental
breaks or when a song has no lyrics it hides, since the media widget already
shows the track. Set `mode` to `lyrics_track` to get the track in those gaps.

Lines longer than `max_length` scroll smoothly. A lyric line scrolls once,
paced so its end shows up while it's still being sung; the track loops.

The panel is just the lyrics, Spotify style: the line being sung is lit, the
rest are dimmed and everything glides up as the song goes on. Click a line to
jump to it.

If the player puts a `file://` url in its metadata (mpv, Strawberry, Elisa...),
a `song.lrc` next to `song.flac` is used instead of looking anything up.

When several players are open, the one that's playing wins. If nothing is
playing, the one that played last is shown.

## Settings

Plugin (Settings → Plugins → Lyrics):

| Setting | Default | |
|---|---|---|
| `offset` | `0` | Timing offset in ms. Positive shows lines earlier. |
| `players` | `[]` | Only follow players whose name contains one of these. |
| `ignored_players` | `[]` | Never follow these, e.g. `firefox`. |

Widget:

| Setting | Default | |
|---|---|---|
| `mode` | `lyrics` | `lyrics`, `lyrics_track` (the track when there's no line) or `track` |
| `track_format` | `{title} - {artist}` | Also `{album}` and `{player}` |
| `max_length` | `45` | In characters, `0` for no limit |
| `scroll` | `always` | `none`, `on_hover` or `always` for text over `max_length` |
| `when_paused` | `hide` | `hide`, `lyric` or `track` |
| `hide_when_idle` | `true` | Hide when no player is around |
| `show_glyph` / `glyph` | `true` / `music` | |

## IPC

Handy for keybinds:

```sh
noctalia msg plugin shadow/lyrics:service all refetch      # look the lyrics up again, skipping the cache
noctalia msg plugin shadow/lyrics:service all nudge 0.5    # this track's lyrics 0.5s earlier, remembered
noctalia msg panel-toggle shadow/lyrics:panel
```

## Notes

Smooth scrolling is built from labels and spacers (plugins can't clip or
measure text), so it assumes a monospace bar font, like most Nerd Font setups.
With a proportional font it still scrolls, just less evenly.

The cache and per-track offsets live in
`~/.local/state/noctalia/plugins/data/shadow/lyrics/`. Delete the folder to
start over.

The way lyrics are matched (duration, album and artist scoring) and synced
(interpolating from the last known position, resyncing on seeks) follows
[lrcsnc](https://github.com/Endg4meZer0/lrcsnc).

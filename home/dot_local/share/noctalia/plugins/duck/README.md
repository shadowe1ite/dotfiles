# Duck

DuckDuckGo Email Protection on the bar. Generate a `@duck.com` alias with the
existing `ddg-email` script, then watch Gmail for mail that was actually
addressed to one of those aliases.

## Plugin

| Field | Value |
| --- | --- |
| ID | `shadow/duck` |
| Entries | Service `service`, bar widget `widget`, panel `panel`, shortcut `shortcut` |

## Usage

Add the **Duck** widget from the bar's widget picker. It shows an unread
count, or just the local part of the last alias. Click opens the inbox.
Right-click generates a new alias and copies it.

The inbox lists only mail that arrives after the plugin is enabled. Older
mail stays in Gmail and is not shown. Click a message to read it, copy its
alias, or copy a one-time code. **Delete** removes that message from the plugin. **Clear all**
asks once, then removes every message. Mail stays in Gmail either way.
Back returns to the list.

The control-center tile generates an alias on click and opens the inbox on
right-click.

The inbox lists sender, subject, time, a short preview, the `@duck.com`
address, and a one-time code when the message has one. Copy buttons put that
text on the clipboard. Copying a code marks the message read in the plugin.
That does not change the message in Gmail.

```sh
noctalia msg plugins enable shadow/duck
noctalia msg panel-toggle shadow/duck:panel
noctalia msg plugin shadow/duck:service all generate
```

## Requirements

Noctalia with plugin API 32 or later, plus:

- `~/.local/bin/ddg-email` (the existing generator; it uses `pass` and `wl-copy`)
- `pass` entries, read at runtime and never written into plugin settings:
  - `duckduckgo.com/token` for the generator
  - `duckduckgo.com/mail` for the Gmail address, or `duckduckgo.com/config/mail` if that is where it already lives
  - `duckduckgo.com/pass` for the Gmail app password, or `duckduckgo.com/config/pass`
- Gmail IMAP (`imap.gmail.com:993`) with an app password
- `python3` from the standard library for the watcher

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `notify` | bool | true | Desktop notification for a new matching message. |
| `keep` | int | 30 | How many messages to keep in the plugin data directory. |

## IPC

```sh
noctalia msg plugin shadow/duck:service all generate
noctalia msg plugin shadow/duck:service all read
noctalia msg plugin shadow/duck:service all read 12345
noctalia msg plugin shadow/duck:service all delete 12345
noctalia msg plugin shadow/duck:service all clear
```

`read` with no payload marks every message read in the plugin. A payload is
the IMAP uid of one message. `delete` and `clear` remove messages from this
inbox only. Gmail is left untouched, and a removed message is not fetched again.

## Notes

The service and the Python watcher are separate from the widget and the panel.
The watcher uses IMAP IDLE and reconnects on its own, with the wait doubling
up to a minute. If it goes quiet, the service starts it again.

A message is kept only when a recipient header contains `@duck.com`.
`Delivered-To` is checked first. Gmail often adds its own `Delivered-To` for
the real mailbox, so `To` and the other recipient headers are checked after
that. The Gmail search is `deliveredto:@duck.com OR to:@duck.com`.

The inbox file lives in the plugin data directory and holds subjects and
previews, not passwords. The watcher fetches headers and a short text snippet
with `BODY.PEEK`, so opening the plugin does not mark mail read in Gmail.

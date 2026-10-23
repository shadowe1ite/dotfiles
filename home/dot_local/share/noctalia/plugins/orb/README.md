# Orb

A little companion after [Marea](https://github.com/k4ditano/marea-plm): a ball with two pill
eyes, dark like your bar with eyes in your theme's accent, that blinks, glances around and breathes. It lives in the bar. Bring
it out and it drips out of the bar like a drop; pick it up and it follows your cursor until you
put it down. Click it and its card grows out of it, Marea-style: not a panel beside it, but its own
body stretched out. The card is where you chat with your [Hermes agent](https://hermes-agent.nousresearch.com/docs),
and the orb's face shows what Hermes is doing.

## Plugin

| | |
| --- | --- |
| Id | `shadow/orb` |
| Bar widget | `shadow/orb:orb` |
| Service | `shadow/orb:service` |
| Layer | `shadow/orb:roamer` |
| Plugin API | 36 (Noctalia main branch: `[[layer]]` entries) |

## Usage

1. `noctalia msg plugins enable shadow/orb`
2. Add **Orb** to a bar from the widget picker in Settings.

In the bar:

- **Click**: it drips out and its card grows out of it. Close the card (× or click the ball) and it
  goes back in, or press **Stay out** to leave it out.
- **Right-click**: it comes out and stays below the bar.
- **Click the puddle** it leaves in the bar: call it home.

Out of the bar:

- **Double-click**: pick it up. It follows your cursor; **click** anywhere to put it down. (While it
  follows, that click only puts it down. If the pointer stays still for 30 s it puts itself down.)
- **Click**: its card grows out of it, flipping left or up near the screen edges. Click the ball (or
  ×) again to fold it back in.
- **Call home** on the card, or click the puddle in the bar: it flies back and dives into the bar.

```sh
noctalia msg plugin shadow/orb:service all card    # bring its card out
noctalia msg plugin shadow/orb:service all out     # bring it out
noctalia msg plugin shadow/orb:service all home    # call it back
noctalia msg plugin shadow/orb:service all toggle

noctalia msg plugin shadow/orb:service all hermes-status   # log the link and whether a key is stored
noctalia msg plugin shadow/orb:service all hermes-send "what's on today?"   # /commands work too
noctalia msg plugin shadow/orb:service all hermes-attach ~/report.pdf      # goes with the next message
noctalia msg plugin shadow/orb:service all hermes-approve once   # once | session | always | deny
noctalia msg plugin shadow/orb:service all hermes-stop
noctalia msg plugin shadow/orb:service all hermes-new
noctalia msg plugin shadow/orb:roamer all tab chats       # chat | chats
```

## Hermes

The card has two tabs:

- **Chat**: the orb's conversation with Hermes, streamed, with tool lines and Allow / Deny when
  Hermes asks to run something. It carries on until the new-chat button starts another; **■**
  stops a run. The chip next to 📎 shows the model in use; tap it to pick another for this
  chat (or go back to Hermes' default). It lists the providers you set up (your Hermes
  config's providers and the ones you signed in to through Hermes); providers Hermes only
  lists because a key happens to be around (Copilot through a GitHub token, say) wait behind
  **Show all providers**. A turn that failed and a model switch show as small lines in the
  history. A reply that came with the model's reasoning gets a **Show thinking** line;
  tap it to read the reasoning. While Hermes works, tap the status line to see the latest
  text it has passed along.
- **Chats**: the orb's past chats. Tap one to carry it on in Chat; the trash button deletes
  it (it asks first: Hermes drops the chat and its transcript for good). (Chats from Telegram, the CLI
  or Desktop are not listed: Hermes only lets the API continue the sessions it created.)

The card takes the keyboard like a window does: the click that opens it (or the orb coming
out of the bar for it) hands it the keys, so you can type straight away; clicking a window,
or with focus-follows-mouse moving onto one, takes them back, and coming back to the card
returns them.

### Commands

Hermes' API runs every message through the agent as plain text (its own slash commands live in
the CLI and messaging surfaces), so the orb handles these itself. Typing `/` lists them as you go;
`//` at the start sends a `/` as text.

| | |
| --- | --- |
| `/new` | start a new chat |
| `/chats` | your past chats |
| `/attach` | attach files |
| `/model [model]` | open the model picker, or switch this chat directly (`/model claude-opus-5-5`, `/model anthropic/claude-opus-5-5`, `/model default`) |
| `/retry` | send your last message again |
| `/stop` | stop the reply |
| `/title <name>` | rename this chat |
| `/fork [title]` | copy this chat and carry on in the copy |
| `/skill <name> [request]` | ask Hermes to use one of its skills |
| `/approve [once\|session\|always]`, `/deny` | answer what Hermes asked to run |
| `/help` | the list |

### Files

- **To Hermes** (📎 or `/attach`, a file chooser): images go inline (Hermes' API takes images up
  to 5 MB); text files up to 256 KB go into the message; anything else is copied over SSH to
  `~/orb-inbox` on the server and the message tells Hermes where it is. While the chooser is
  open the card steps aside (it would cover the dialog) and comes back after.
- **From Hermes**: images it sends show in the chat (click to open). Any other file it hands you
  (a `MEDIA:` path on the server) gets **Save**, which copies it into `~/Downloads` over SSH,
  then **Open**.
- SSH uses the **SSH login** setting and must work without a password (Tailscale SSH or a key).
  Paths travel over stdin, never into the remote command line, so a path in a reply cannot run
  anything on either machine.

Without an API key the card shows only "Connect Hermes first"; it unlocks by itself within a few
seconds of the key landing in the keyring.

The orb itself shows how Hermes is doing, on the bar and out of it, with no status dots:

| | |
| --- | --- |
| asleep, a "z" drifting up | Hermes is out of reach, or there is no key |
| drowsy, eyes half shut | Hermes answers but says it is not all right |
| awake, a little hop now and then | connected, nothing going on |
| eyes up, drifting side to side | thinking |
| squinting down | running a tool (or other agents are busy) |
| round eyes, hopping | Hermes needs you: an approval |
| happy eyes, pulsing | a reply is waiting |
| a happy hop | a reply just landed |
| startled | a run failed |

Out of the bar it also says what it is doing in a bubble. Touch a sleeping orb and it peeks.

### Setup

The orb talks to Hermes' API server, which needs a key (Hermes requires one even on loopback).
This sets it up on the server over SSH and stores the key in your keyring, without the key ever
showing on screen or in shell history:

```sh
ssh 0cto@server.tailf72995.ts.net 'bash -l -s' < scripts/connect-remote.sh \
  | sed -n 's/^ORBKEY=//p' | tr -d '\r\n' \
  | secret-tool store --label='Orb: Hermes API key' service orb-hermes kind api-key
```

`scripts/connect-remote.sh` turns on the API server bound to the server's Tailscale address,
adds a key unless one is set, restarts the gateway if anything changed, and prints the key.

## Settings

Colors

- **Body color** / **Eye color**: your theme's `primary` body with `surface` eyes by default; any
  palette role or hex works (Marea's own are `#161717` and `#f5f7f5`).
- **Card color**: the card's background, `surface_variant` by default. Keep it a surface color:
  the card's text and Hermes' replies use your theme's text colors.
- **Outline**, **Outline color**, **Outline opacity (%)**: the thin line around the orb, and around
  ball and card together when the card is out. On, in `surface` at 10%, by default.
- **Reset everything to defaults**: turn it on and every Orb setting goes back to its default; the
  plugin reloads and the switch turns itself back off. (Noctalia has no reset for plugin settings,
  so the service removes the plugin's table from `settings.toml` itself.)

Sizes

- **Size in the bar** (16-36 px, default 26) and **Size out of the bar** (24-96 px, default 46).
- **Card width** / **Card height** (default 420 x 540).

Card and placement

- **Card opens toward** (auto / right / left) and **Card opens up or down** (auto / down / up).
  Auto picks the side with room; a fixed side moves the orb over if the card would not fit.
- **Remember where it was put**: when it comes out, it floats back to where you last put it down
  (forgotten if the screen size changes). Saved in the plugin's data directory as `position.json`.
- **Home position (%)** (advanced): plugins cannot read a widget's pixel position, so the orb guesses
  where it sits from its section and index in the bar. Set a percentage of the bar length to pin it.

Motion

- **Follow** (loose / normal / tight): how closely it trails the cursor while it follows.
- **Animation speed** (slow / normal / fast): dripping out, diving in, the card opening and closing.
- **Double-click speed (ms)** (advanced, default 320): how quickly two clicks must follow to pick
  it up; a single click on the orb waits this long before it opens the card.

Hermes

- **Hermes address** (default `http://server.tailf72995.ts.net`), **API server port** (8642),
  **Dashboard port** (9119, where Hermes' public `/api/status` lives), **SSH login**
  (`0cto@server.tailf72995.ts.net`, for files).

## Notes

- **Following.** Plugins get no press/release events, so there is no drag. Instead, while the orb
  follows, its surface covers the screen with a transparent `ui.graph` whose pointer tracking gives
  the cursor position; the next click anywhere lands on that surface and puts the orb down.
- Out of the bar, a single click waits out the double-click window (320 ms) before it opens the
  card.
- Out of the bar the orb is one layer surface on the `top` layer that moves itself by its margins
  and grows into the card. It goes under fullscreen windows; there it keeps its state moving on a
  slow timer, since the compositor stops sending it frames.
- The card is not a Noctalia panel, so Esc and clicking outside do not close it: use × or the ball.
- What it cannot copy from Marea: the curved neck where ball and card melt together (the UI has no
  shape blending, so they simply overlap in one color), and the glass skins.
- Network: only to your Hermes address. It polls `/api/status` every 5 s while the card is open
  and every 20 s otherwise (60 s while offline), and refreshes the Chats list every minute while
  it shows. Processes: `secret-tool` (key lookups), `zenity` (file chooser), `base64`, `ssh`
  (through `scripts/fetch.sh` and `scripts/upload.sh`, for files), `xdg-open` (Open).
- Files it writes: `position.json`, `hermes.json` (the orb chat's session id and model), `media/`
  (images from replies), and what you Save into `~/Downloads`.
- `tests/run.sh` runs the unit tests for the pure modules (`lib/motion`, `lib/life`, `lib/face`,
  `lib/reset`, `lib/hermes/*`); it needs the `luau` CLI.

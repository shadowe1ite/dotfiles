#!/usr/bin/env python3
"""Watch Gmail over IMAP IDLE for mail to @duck.com aliases.

Credentials are read from `pass` on each connection and never written, logged,
or printed. Stdout is one JSON object per line for the Noctalia service.
"""

from __future__ import annotations

import atexit
import email
import html
import imaplib
import json
import os
import re
import signal
import socket
import subprocess
import sys
import time
from email.header import decode_header, make_header
from email.message import Message
from email.utils import parsedate_to_datetime, parseaddr
from pathlib import Path

HOST = "imap.gmail.com"
PORT = 993
# The names you asked for, then the entries that already exist in this password store.
PASS_MAIL = ("duckduckgo.com/mail", "duckduckgo.com/config/mail")
PASS_APP = ("duckduckgo.com/pass", "duckduckgo.com/config/pass")
# Delivered-To first: that is the DuckDuckGo forwarding signal. Gmail often
# appends its own Delivered-To with the real mailbox, so the other recipient
# headers are checked only after it.
RECIPIENT_HEADERS = (
    "Delivered-To",
    "X-Original-To",
    "Original-Recipient",
    "Envelope-To",
    "X-Forwarded-To",
    "Resent-To",
    "To",
    "Cc",
)
DUCK_ADDRESS = re.compile(r"[A-Z0-9._%+\-]+@duck\.com", re.IGNORECASE)
LABELED_CODE = re.compile(
    r"(?i)\b(?:otp|one[-\s]?time(?:\s+(?:password|code|pin))?|"
    r"verification\s+code|security\s+code|login\s+code|passcode|"
    r"confirmation\s+code|auth(?:entication)?\s+code|code)\b"
    r"(?:\s+is|\s*[:=\-])?\s*([A-Z0-9]{4,8})"
)
BARE_SIX = re.compile(r"(?<!\d)(\d{6})(?!\d)")
YEAR = re.compile(r"(?:19|20)\d{2}")
ADDRESS_IN_TEXT = re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}")
SECRET_ASSIGNMENT = re.compile(r"(?i)(password|token|bearer|authorization)\s*[:=]\s*\S+")
IDLE_SECONDS = 90
KEEP_DEFAULT = 30

# imaplib speaks IMAP in bytes. These tags are the ones this process issued.
_idle_tag = b""


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def public_error(exc: BaseException) -> str:
    text = str(exc).replace("\n", " ").strip()
    text = ADDRESS_IN_TEXT.sub("[address]", text)
    text = SECRET_ASSIGNMENT.sub(r"\1=[redacted]", text)
    if len(text) > 160:
        text = text[:160]
    return text or "connection failed"


def pass_show(entry: str) -> str:
    try:
        out = subprocess.check_output(["pass", "show", entry], text=True, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"password store has no {entry}") from exc
    line = out.strip().splitlines()[0].strip() if out.strip() else ""
    if not line:
        raise RuntimeError(f"password store entry {entry} is empty")
    return line


def pass_first(entries: tuple[str, ...]) -> str:
    last = "password store entry is missing"
    for entry in entries:
        try:
            return pass_show(entry)
        except RuntimeError as exc:
            last = str(exc)
    raise RuntimeError(last)


def decode_mime(value: str | None) -> str:
    if not value:
        return ""
    try:
        return str(make_header(decode_header(value)))
    except (ValueError, IndexError, LookupError):
        return value


def duck_recipient(msg: Message) -> tuple[str, str] | None:
    """Return (address, header), preferring Delivered-To over the other recipient headers."""
    for header in RECIPIENT_HEADERS:
        for raw in msg.get_all(header, []):
            match = DUCK_ADDRESS.search(decode_mime(raw))
            if match:
                return match.group(0).lower(), header
    return None


def duck_alias(msg: Message) -> str | None:
    found = duck_recipient(msg)
    return found[0] if found else None


def unseen(flags: str) -> bool:
    parts = {part.lstrip("\\").upper() for part in flags.replace("(", " ").replace(")", " ").split()}
    return "SEEN" not in parts


def _good_code(token: str) -> bool:
    if not 4 <= len(token) <= 8:
        return False
    if not re.fullmatch(r"[A-Z0-9]+", token, re.IGNORECASE):
        return False
    if not re.search(r"\d", token):
        return False
    if token.isdigit() and YEAR.fullmatch(token):
        return False
    return True


def extract_otp(text: str) -> str:
    if not text:
        return ""
    for match in LABELED_CODE.finditer(text):
        token = match.group(1)
        if _good_code(token):
            return token
    match = BARE_SIX.search(text)
    if match and _good_code(match.group(1)):
        return match.group(1)
    return ""


_MIME_LEAK = re.compile(
    r"(?i)^(content-type|content-transfer-encoding|content-disposition|mime-version)\s*:|"
    r"^--[0-9a-f]{8,}"
)


def _part_text(part: Message) -> str:
    try:
        payload = part.get_payload(decode=True)
    except (TypeError, LookupError):
        payload = None
    if not payload:
        raw = part.get_payload()
        return raw if isinstance(raw, str) else ""
    charset = part.get_content_charset() or "utf-8"
    try:
        return payload.decode(charset, "replace")
    except LookupError:
        return payload.decode("utf-8", "replace")


def body_text(header: bytes, body: bytes) -> str:
    """Decode the text of a message, ignoring MIME framing and HTML."""
    raw = header or b""
    if body:
        if not raw.endswith(b"\n"):
            raw += b"\r\n"
        if not raw.endswith(b"\r\n\r\n") and not raw.endswith(b"\n\n"):
            raw += b"\r\n"
        raw += body
    msg = email.message_from_bytes(raw)
    plain: list[str] = []
    html_parts: list[str] = []
    parts = msg.walk() if msg.is_multipart() else [msg]
    for part in parts:
        if part.get_content_maintype() == "multipart":
            continue
        disposition = (part.get("Content-Disposition") or "").lower()
        if "attachment" in disposition:
            continue
        text = _part_text(part)
        if not text.strip():
            continue
        if part.get_content_type() == "text/html":
            html_parts.append(text)
        else:
            plain.append(text)
    plain_text = "\n".join(plain).strip()
    html_text = "\n".join(html_parts).strip()
    # A tiny text/plain part is often just "Hi" or a boundary leftover.
    # The HTML part is the letter in that case.
    if len(plain_text) >= 40:
        return plain_text
    if len(html_text) > len(plain_text):
        return html_text
    return plain_text or html_text


def _plain_inner(fragment: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"(?s)<[^>]+>", "", fragment))).strip()


def html_to_markdown(text: str) -> str:
    """Turn the tags mail actually uses into markdown the panel can draw."""
    text = re.sub(r"(?is)<(script|style)\b[^>]*>.*?</\1>", "", text)

    def pre_block(match: re.Match[str]) -> str:
        inner = html.unescape(re.sub(r"(?s)<[^>]+>", "", match.group(1))).strip("\n")
        return f"\n```\n{inner}\n```\n"

    def code_span(match: re.Match[str]) -> str:
        inner = _plain_inner(match.group(1))
        if not inner:
            return ""
        if "\n" in match.group(1) or len(inner) > 60:
            return f"\n```\n{inner}\n```\n"
        return f"`{inner}`"

    def anchor(match: re.Match[str]) -> str:
        href = html.unescape(match.group(1)).strip()
        label = _plain_inner(match.group(2)) or href
        return f"[{label}]({href})"

    text = re.sub(r"(?is)<pre\b[^>]*>(.*?)</pre>", pre_block, text)
    text = re.sub(r"(?is)<code\b[^>]*>(.*?)</code>", code_span, text)
    text = re.sub(r'(?is)<a\b[^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a>', anchor, text)
    text = re.sub(r"(?is)<(strong|b)\b[^>]*>(.*?)</\1>", lambda m: f"**{_plain_inner(m.group(2))}**", text)
    text = re.sub(r"(?is)<(em|i)\b[^>]*>(.*?)</\1>", lambda m: f"*{_plain_inner(m.group(2))}*", text)
    text = re.sub(r"(?i)<h1\b[^>]*>", "\n# ", text)
    text = re.sub(r"(?i)<h2\b[^>]*>", "\n## ", text)
    text = re.sub(r"(?i)<h3\b[^>]*>", "\n### ", text)
    text = re.sub(r"(?i)<li\b[^>]*>", "\n- ", text)
    text = re.sub(r"(?i)<br\s*/?>", "\n", text)
    text = re.sub(r"(?i)</p\s*>", "\n\n", text)
    text = re.sub(r"(?i)</div\s*>", "\n", text)
    text = re.sub(r"(?i)</h[1-6]\s*>", "\n\n", text)
    text = re.sub(r"(?s)<[^>]+>", "", text)
    return html.unescape(text).replace("\xa0", " ")


def _linkify(text: str) -> str:
    def repl(match: re.Match[str]) -> str:
        url = match.group(0).rstrip(".,;:")
        return f"[{url}]({url}){match.group(0)[len(url):]}"

    parts = re.split(r"(```.*?```|`[^`\n]+`)", text, flags=re.S)
    out: list[str] = []
    for index, part in enumerate(parts):
        if index % 2 == 1:
            out.append(part)
        else:
            out.append(re.sub(r"(?<!\]\()https?://[^\s<>)\]]+", repl, part))
    return "".join(out)


def plain_preview(text: str, limit: int = 180) -> str:
    if re.search(r"<(?:a|p|div|br|pre|code|html|body|table|span|strong|b|em|i|h[1-6]|ul|ol|li)\b", text, re.I):
        text = html_to_markdown(text)
    else:
        text = text.replace("\xa0", " ")
    lines: list[str] = []
    in_fence = False
    blank = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            lines.append(stripped)
            blank = False
            continue
        if in_fence:
            lines.append(line.rstrip())
            continue
        if not stripped or stripped == "--" or _MIME_LEAK.match(stripped):
            if lines and not blank:
                lines.append("")
                blank = True
            continue
        lines.append(stripped)
        blank = False
    cleaned = _linkify(re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip())
    if len(cleaned) <= limit:
        return cleaned
    return cleaned[: limit - 1].rstrip() + "…"


def _sender(value: str) -> str:
    name, addr = parseaddr(decode_mime(value))
    name = re.sub(r"\s+", " ", name).strip()
    return name or addr or decode_mime(value)


def _unix_time(value: str) -> int:
    if not value:
        return 0
    try:
        return int(parsedate_to_datetime(decode_mime(value)).timestamp())
    except (TypeError, ValueError, OverflowError, IndexError):
        return 0


def message_record(uid: str, header: bytes, body: bytes, flags: str) -> dict | None:
    msg = email.message_from_bytes(header or b"")
    alias = duck_alias(msg)
    if alias is None:
        return None
    preview = plain_preview(body_text(header, body), 1200)
    subject = re.sub(r"\s+", " ", decode_mime(msg.get("Subject"))).strip()
    return {
        "uid": str(uid),
        "alias": alias,
        "sender": _sender(msg.get("From", ""))[:80],
        "subject": subject[:140],
        "preview": preview,
        "otp": extract_otp(preview),
        "at": _unix_time(msg.get("Date", "")),
        "unread": unseen(flags),
    }


def _meta_text(item: object) -> str:
    if isinstance(item, tuple) and item:
        head = item[0]
        if isinstance(head, bytes):
            return head.decode("latin1", "replace")
        return str(head)
    if isinstance(item, bytes):
        return item.decode("latin1", "replace")
    return str(item)


def parse_fetch(data: list) -> tuple[str, str, bytes, bytes]:
    """Pull UID, flags, header bytes, and a text snippet out of one FETCH."""
    uid = ""
    flags = ""
    header = b""
    body = b""
    for item in data or []:
        meta = _meta_text(item)
        uid_match = re.search(r"\bUID (\d+)", meta)
        if uid_match:
            uid = uid_match.group(1)
        flag_match = re.search(r"FLAGS \(([^)]*)\)", meta)
        if flag_match:
            flags = flag_match.group(1)
        if not isinstance(item, tuple) or len(item) < 2 or not isinstance(item[1], (bytes, bytearray)):
            continue
        payload = bytes(item[1])
        upper = meta.upper()
        if "BODY[HEADER" in upper:
            header = payload
        elif "BODY[TEXT" in upper or "BODY[1" in upper:
            body = payload
    return uid, flags, header, body


def _uids(data: list) -> list[str]:
    if not data or not data[0]:
        return []
    raw = data[0]
    if isinstance(raw, bytes):
        raw = raw.decode("ascii", "replace")
    return [part for part in str(raw).split() if part.isdigit()]


def _quoted(query: str) -> str:
    return '"' + query.replace("\\", "\\\\").replace('"', '\\"') + '"'


def junk_box(conn: imaplib.IMAP4_SSL) -> str | None:
    typ, data = conn.list()
    if typ != "OK":
        return None
    for item in data or []:
        if not item:
            continue
        text = item.decode("utf-8", "replace") if isinstance(item, bytes) else str(item)
        if "\\Junk" not in text:
            continue
        if text.count('"') >= 2:
            return text.rsplit('"', 2)[-2]
    return None


def select_box(conn: imaplib.IMAP4_SSL, name: str) -> None:
    typ, _ = conn.select(f'"{name}"', readonly=True)
    if typ != "OK":
        raise imaplib.IMAP4.abort("could not open mailbox")


def internal_unix(conn: imaplib.IMAP4_SSL, uid: str) -> int:
    typ, data = conn.uid("FETCH", uid, "(INTERNALDATE)")
    if typ != "OK":
        return 0
    raw = b" ".join(part if isinstance(part, bytes) else b"" for part in data or [])
    match = re.search(br'INTERNALDATE "([^"]+)"', raw)
    if not match:
        return 0
    try:
        return int(parsedate_to_datetime(match.group(1).decode()).timestamp())
    except (TypeError, ValueError, OverflowError):
        return 0


def search_duck(conn: imaplib.IMAP4_SSL, limit: int) -> list[str]:
    queries = (
        "(to:@duck.com OR deliveredto:@duck.com) newer_than:21d",
        "to:@duck.com OR deliveredto:@duck.com",
    )
    uids: list[str] = []
    for query in queries:
        try:
            typ, data = conn.uid("SEARCH", "X-GM-RAW", _quoted(query))
        except imaplib.IMAP4.error:
            continue
        if typ == "OK":
            uids = _uids(data)
            # An empty recent window still tries the wider query. A wider
            # empty result is real and falls through to the header search.
            if uids or "newer_than" not in query:
                break
    if not uids:
        typ, data = conn.uid(
            "SEARCH",
            "OR",
            "HEADER",
            "Delivered-To",
            "@duck.com",
            "HEADER",
            "To",
            "@duck.com",
        )
        if typ == "OK":
            uids = _uids(data)
    if len(uids) > limit:
        return uids[-limit:]
    return uids


def fetch_record(conn: imaplib.IMAP4_SSL, uid: str) -> dict | None:
    typ, data = conn.uid("FETCH", uid, "(UID FLAGS BODY.PEEK[HEADER] BODY.PEEK[TEXT]<0.16384>)")
    if typ != "OK":
        return None
    found, flags, header, body = parse_fetch(data)
    return message_record(found or uid, header, body, flags)


def _socket(conn: imaplib.IMAP4_SSL) -> socket.socket:
    sock = getattr(conn, "socket", None)
    if callable(sock):
        return sock()
    if sock is not None:
        return sock
    return conn.sock


_wake = False


def _on_wake(_signum, _frame) -> None:
    global _wake
    _wake = True


signal.signal(signal.SIGUSR1, _on_wake)


def idle_until_mail(conn: imaplib.IMAP4_SSL, timeout: int) -> bool:
    """Wait until the server reports new mail, or until `timeout` seconds pass.

    Gmail drops an IDLE after roughly half an hour, so the caller refreshes
    it well inside that window. Returns True when EXISTS/RECENT arrived.
    """
    global _idle_tag
    tag = conn._new_tag()
    _idle_tag = tag if isinstance(tag, bytes) else str(tag).encode()
    conn.send(b"%s IDLE\r\n" % _idle_tag)
    greeting = conn.readline()
    if not greeting.startswith(b"+"):
        raise imaplib.IMAP4.abort("IDLE was rejected")

    saw = False
    deadline = time.time() + timeout
    try:
        while time.time() < deadline:
            if _wake:
                break
            _socket(conn).settimeout(min(5, max(deadline - time.time(), 0.1)))
            try:
                line = conn.readline()
            except (TimeoutError, socket.timeout, InterruptedError):
                continue
            if line == b"":
                raise imaplib.IMAP4.abort("connection closed during IDLE")
            if b"EXISTS" in line or b"RECENT" in line:
                saw = True
                break
            if b"BYE" in line:
                raise imaplib.IMAP4.abort("server closed the connection")
    finally:
        try:
            _socket(conn).settimeout(None)
        except OSError:
            pass

    conn.send(b"DONE\r\n")
    _socket(conn).settimeout(10)
    try:
        while True:
            line = conn.readline()
            if line.startswith(_idle_tag):
                break
            if line == b"":
                raise imaplib.IMAP4.abort("connection closed after IDLE")
    finally:
        try:
            _socket(conn).settimeout(None)
        except OSError:
            pass
    return saw


def claim_pid(path: Path) -> None:
    if path.exists():
        _stop_previous(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(str(os.getpid()))

    def cleanup() -> None:
        try:
            if path.read_text().strip() == str(os.getpid()):
                path.unlink()
        except OSError:
            pass

    atexit.register(cleanup)


def _stop_previous(path: Path) -> None:
    try:
        pid = int(path.read_text().strip())
    except (OSError, ValueError):
        return
    if pid <= 1 or pid == os.getpid():
        return
    try:
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return
    if b"watch.py" not in cmdline:
        return
    os.kill(pid, signal.SIGTERM)
    for _ in range(20):
        try:
            os.kill(pid, 0)
        except OSError:
            return
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass


def _login(user: str, password: str) -> imaplib.IMAP4_SSL:
    # Gmail app passwords are often stored in the four groups pass shows.
    # The server accepts them with or without the spaces; try the stored
    # form first, then the compacted form, on a fresh connection each time.
    secrets = [password]
    compact = password.replace(" ", "")
    if compact and compact != password:
        secrets.append(compact)
    last: BaseException | None = None
    for secret in secrets:
        conn = imaplib.IMAP4_SSL(HOST, PORT)
        try:
            conn.login(user, secret)
            return conn
        except imaplib.IMAP4.error as exc:
            last = exc
            try:
                conn.logout()
            except Exception:
                pass
    raise last or imaplib.IMAP4.error("login failed")


def _connect() -> imaplib.IMAP4_SSL:
    user = pass_first(PASS_MAIL)
    password = pass_first(PASS_APP)
    try:
        conn = _login(user, password)
    finally:
        # The socket keeps the session. Drop the local copy of the password.
        del password
    typ, _ = conn.select("INBOX")
    if typ != "OK":
        raise imaplib.IMAP4.abort("could not open the inbox")
    return conn


CATCHUP_SECONDS = 12 * 3600


def _emit_uid(conn: imaplib.IMAP4_SSL, box: str, uid: str, known: set[str]) -> None:
    key = box + ":" + uid
    if key in known:
        return
    record = fetch_record(conn, uid)
    known.add(key)
    if record is None:
        return
    record["uid"] = key
    emit({"type": "message", "message": record})


def publish_box(conn: imaplib.IMAP4_SSL, box: str, known: set[str], limit: int, baseline: str | None) -> str:
    """Publish duck.com mail in one mailbox that arrived after its baseline.

    Inbox keeps the high-water mark from when the plugin was enabled, so the
    old backlog stays hidden. Spam is watched too: Gmail files some forwards
    there, and the first look still picks up mail from the last 12 hours.
    """
    select_box(conn, box)
    found = search_duck(conn, limit)
    top = found[-1] if found else "0"
    if baseline is None and box != "INBOX":
        cutoff = time.time() - CATCHUP_SECONDS
        for uid in found:
            if internal_unix(conn, uid) >= cutoff:
                _emit_uid(conn, box, uid, known)
        emit({"type": "baseline", "box": box, "uid": top})
        known.update(box + ":" + uid for uid in found)
        return top

    floor = int(baseline or top)
    if baseline is None:
        emit({"type": "baseline", "box": box, "uid": top})
        known.update(box + ":" + uid for uid in found)
        return top

    for uid in found:
        if int(uid) > floor:
            _emit_uid(conn, box, uid, known)
    known.update(box + ":" + uid for uid in found)
    if int(top) > floor:
        emit({"type": "baseline", "box": box, "uid": top})
        return top
    return baseline


def watched_boxes(conn: imaplib.IMAP4_SSL) -> list[str]:
    boxes = ["INBOX"]
    junk = junk_box(conn)
    if junk and junk not in boxes:
        boxes.append(junk)
    return boxes


def publish_all(conn: imaplib.IMAP4_SSL, known: set[str], limit: int, baselines: dict[str, str]) -> None:
    for box in watched_boxes(conn):
        baselines[box] = publish_box(conn, box, known, limit, baselines.get(box))
    select_box(conn, "INBOX")


def summarize(conn: imaplib.IMAP4_SSL, limit: int) -> None:
    """One-shot check that prints counts and header names, never message contents."""
    found = search_duck(conn, limit)
    via: dict[str, int] = {}
    kept = 0
    headers_fetched = 0
    for uid in found:
        typ, data = conn.uid("FETCH", uid, "(UID FLAGS BODY.PEEK[HEADER] BODY.PEEK[TEXT]<0.16384>)")
        if typ != "OK":
            continue
        _uid, _flags, header, _body = parse_fetch(data)
        if header:
            headers_fetched += 1
        msg = email.message_from_bytes(header or b"")
        found_alias = duck_recipient(msg)
        if found_alias is None:
            continue
        kept += 1
        via[found_alias[1]] = via.get(found_alias[1], 0) + 1
    emit({
        "type": "summary",
        "searched": len(found),
        "headers_fetched": headers_fetched,
        "kept": kept,
        "via": via,
    })


def parse_baselines(text: str | None) -> dict[str, str]:
    if not text:
        return {}
    if "=" not in text:
        return {"INBOX": text}
    out = {}
    for part in text.split(","):
        box, _, uid = part.partition("=")
        if box and uid:
            out[box] = uid
    return out


def watch(limit: int, once: bool, baseline: str | None) -> None:
    global _wake
    socket.setdefaulttimeout(30)
    known: set[str] = set()
    baselines = parse_baselines(baseline)
    backoff = 2
    while True:
        conn: imaplib.IMAP4_SSL | None = None
        try:
            emit({"type": "status", "state": "connecting"})
            conn = _connect()
            emit({"type": "status", "state": "connected"})
            backoff = 2
            if once:
                summarize(conn, limit)
                return
            while True:
                publish_all(conn, known, limit, baselines)
                if _wake:
                    _wake = False
                    continue
                emit({"type": "heartbeat"})
                idle_until_mail(conn, IDLE_SECONDS)
                emit({"type": "status", "state": "idle"})
        except Exception as exc:  # noqa: BLE001 - reconnect on any IMAP/pass failure
            emit({"type": "status", "state": "reconnecting", "message": public_error(exc)})
            if once:
                raise SystemExit(1)
            time.sleep(backoff)
            backoff = min(backoff * 2, 60)
        finally:
            if conn is not None:
                try:
                    conn.logout()
                except Exception:
                    try:
                        conn.shutdown()
                    except Exception:
                        pass


def main(argv: list[str]) -> None:
    pid_file = ""
    limit = KEEP_DEFAULT
    once = False
    baseline = None
    args = argv[1:]
    while args:
        item = args.pop(0)
        if item == "--pid-file":
            pid_file = args.pop(0)
        elif item == "--limit":
            limit = max(1, int(args.pop(0)))
        elif item == "--baseline":
            baseline = args.pop(0)
        elif item == "--once":
            once = True
        elif item in ("-h", "--help"):
            sys.stderr.write("usage: watch.py [--pid-file PATH] [--limit N] [--baseline UID] [--once]\n")
            return
        else:
            raise SystemExit(f"unknown argument: {item}")
    if pid_file:
        claim_pid(Path(pid_file))
    watch(limit, once, baseline)


if __name__ == "__main__":
    main(sys.argv)

#!/usr/bin/env python3
"""Parser tests for the IMAP watcher. No network and no password store."""

import importlib.util
import unittest
from email.message import EmailMessage
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("duck_watch", ROOT / "scripts" / "watch.py")
watch = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(watch)


def message_with(**headers) -> EmailMessage:
    msg = EmailMessage()
    for key, value in headers.items():
        msg[key] = value
    return msg


class AliasTests(unittest.TestCase):
    def test_prefers_delivered_to(self):
        msg = message_with(
            **{
                "Delivered-To": "fox@duck.com",
                "To": "other@duck.com",
            }
        )
        self.assertEqual(watch.duck_alias(msg), "fox@duck.com")

    def test_falls_through_when_gmail_rewrites_delivered_to(self):
        msg = message_with(
            **{
                "Delivered-To": "person@gmail.com",
                "To": "Private <Fox.Alias@duck.com>",
            }
        )
        self.assertEqual(watch.duck_alias(msg), "fox.alias@duck.com")

    def test_ignores_mail_that_never_mentions_duck(self):
        msg = message_with(**{"Delivered-To": "person@gmail.com", "To": "person@gmail.com"})
        self.assertIsNone(watch.duck_alias(msg))


class OtpTests(unittest.TestCase):
    def test_labeled_code(self):
        self.assertEqual(watch.extract_otp("Your verification code is 482913"), "482913")
        self.assertEqual(watch.extract_otp("OTP: ABC123"), "ABC123")
        self.assertEqual(watch.extract_otp("Use code 8291 to sign in"), "8291")

    def test_bare_six_digits(self):
        self.assertEqual(watch.extract_otp("Enter 123456 on the next screen"), "123456")

    def test_rejects_years_and_words(self):
        self.assertEqual(watch.extract_otp("Copyright 2024"), "")
        self.assertEqual(watch.extract_otp("the code below"), "")

    def test_html_preview_and_code(self):
        raw = "<p>Your code is <b>111222</b></p>"
        preview = watch.plain_preview(raw)
        self.assertIn("Your code is", preview)
        self.assertIn("111222", preview)
        self.assertEqual(watch.extract_otp(preview), "111222")

    def test_links_and_code_blocks_become_markdown(self):
        raw = (
            "<p>Open <a href=\"https://example.com/inbox\">the inbox</a>.</p>"
            "<pre><code>code = 123456</code></pre>"
            "<p>Or visit https://example.com/raw</p>"
        )
        preview = watch.plain_preview(raw)
        self.assertIn("[the inbox](https://example.com/inbox)", preview)
        self.assertIn("```", preview)
        self.assertIn("code = 123456", preview)
        self.assertIn("[https://example.com/raw](https://example.com/raw)", preview)


class RecordTests(unittest.TestCase):
    def test_record_keeps_duck_mail_and_unread_flag(self):
        header = (
            b"Delivered-To: person@gmail.com\r\n"
            b"To: alias@duck.com\r\n"
            b"From: Ada Lovelace <ada@example.com>\r\n"
            b"Subject: Sign in\r\n"
            b"Date: Tue, 10 Nov 2026 12:00:00 +0000\r\n"
            b"\r\n"
        )
        record = watch.message_record("15", header, b"Your verification code is 654321", "")
        self.assertIsNotNone(record)
        self.assertEqual(record["uid"], "15")
        self.assertEqual(record["alias"], "alias@duck.com")
        self.assertEqual(record["sender"], "Ada Lovelace")
        self.assertEqual(record["subject"], "Sign in")
        self.assertEqual(record["otp"], "654321")
        self.assertTrue(record["unread"])
        self.assertGreater(record["at"], 0)

    def test_seen_flag_is_read(self):
        header = b"Delivered-To: alias@duck.com\r\nFrom: a@b.c\r\nSubject: Hi\r\n\r\n"
        record = watch.message_record("9", header, b"hello", r"\Seen")
        self.assertFalse(record["unread"])

    def test_quoted_printable_multipart_is_plain_text(self):
        header = (
            b"To: alias@duck.com\r\n"
            b"From: Venice AI <hello@venice.ai>\r\n"
            b"Subject: Need more credits & higher limits?\r\n"
            b"MIME-Version: 1.0\r\n"
            b"Content-Type: multipart/alternative; boundary=b2f47b6202153c16\r\n"
            b"\r\n"
        )
        body = (
            b"--b2f47b6202153c16\r\n"
            b"Content-Transfer-Encoding: quoted-printable\r\n"
            b"Content-Type: text/plain; charset=us-ascii\r\n"
            b"\r\n"
            b"Upgrade to Venice Pro today. Do more with Venice Pro.\r\n"
            b"We hope you've been enjoying it.\r\n"
            b"--b2f47b6202153c16\r\n"
            b"Content-Type: text/html\r\n"
            b"\r\n"
            b"<p>ignore this</p>\r\n"
            b"--b2f47b6202153c16--\r\n"
        )
        record = watch.message_record("20", header, body, "")
        self.assertNotIn("Content-Transfer-Encoding", record["preview"])
        self.assertNotIn("b2f47b", record["preview"])
        self.assertIn("Upgrade to Venice Pro today.", record["preview"])
        self.assertNotIn("ignore this", record["preview"])

    def test_html_letter_when_plain_part_is_tiny(self):
        header = (
            b"To: a@duck.com\r\nFrom: Ada <ada@example.com>\r\nSubject: Hi\r\n"
            b"MIME-Version: 1.0\r\nContent-Type: multipart/alternative; boundary=x\r\n\r\n"
        )
        body = (
            b"--x\r\nContent-Type: text/plain\r\n\r\nHi\r\n"
            b"--x\r\nContent-Type: text/html\r\n\r\n<p>Hello there.</p><p>Second line.</p>\r\n"
            b"--x--\r\n"
        )
        record = watch.message_record("3", header, body, "")
        self.assertIn("Hello there.", record["preview"])
        self.assertIn("Second line.", record["preview"])
        self.assertNotIn("<p>", record["preview"])
        self.assertIn("\n", record["preview"])

    def test_drops_unrelated_mail(self):
        header = b"Delivered-To: person@gmail.com\r\nTo: person@gmail.com\r\nSubject: Hi\r\n\r\n"
        self.assertIsNone(watch.message_record("1", header, b"hello", ""))

    def test_fetch_parser(self):
        data = [
            (
                b"1 (UID 44 FLAGS (\\Seen) BODY[HEADER] {12}",
                b"To: a@duck.com",
            ),
            (b" BODY[TEXT]<0> {5}", b"hello"),
            b")",
        ]
        uid, flags, header, body = watch.parse_fetch(data)
        self.assertEqual(uid, "44")
        self.assertIn("Seen", flags)
        self.assertEqual(header, b"To: a@duck.com")
        self.assertEqual(body, b"hello")


class RedactionTests(unittest.TestCase):
    def test_public_error_strips_addresses_and_secrets(self):
        text = watch.public_error(RuntimeError("login person@gmail.com password=hunter2 failed"))
        self.assertNotIn("person@gmail.com", text)
        self.assertNotIn("hunter2", text)
        self.assertIn("[address]", text)
        self.assertIn("[redacted]", text)


if __name__ == "__main__":
    unittest.main()

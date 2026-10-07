#!/usr/bin/env python3
import os
import smtplib
from email.message import EmailMessage
from pathlib import Path

recipient = os.environ.get("APK_EMAIL_RECIPIENT", "backcountrysignal@gmail.com")
username = os.environ.get("APK_EMAIL_USERNAME", "").strip()
password = os.environ.get("APK_EMAIL_APP_PASSWORD", "").strip()
apk = Path(os.environ.get("APK_PATH", "build/app/outputs/flutter-apk/app-release.apk"))
run_url = os.environ.get("BUILD_URL", "")
sha = os.environ.get("BUILD_SHA", "")[:7]

if not username or not password:
    print("APK email credentials are not configured; artifact remains available in GitHub Actions.")
    raise SystemExit(0)

message = EmailMessage()
message["From"] = username
message["To"] = recipient
message["Subject"] = f"Bastion Meshtastic APK {sha}" if sha else "Bastion Meshtastic APK"
message.set_content(
    "Bastion Meshtastic built successfully.\n\n"
    f"Build: {run_url}\n"
    "The APK is attached when it is small enough for email."
)

max_attachment_bytes = 24 * 1024 * 1024
if apk.exists() and apk.stat().st_size <= max_attachment_bytes:
    message.add_attachment(
        apk.read_bytes(),
        maintype="application",
        subtype="vnd.android.package-archive",
        filename="Bastion-Meshtastic.apk",
    )
else:
    message.set_content(
        message.get_content()
        + "\nThe APK was too large to attach (or was missing); use the GitHub build artifact link above.\n"
    )

with smtplib.SMTP_SSL("smtp.gmail.com", 465, timeout=30) as smtp:
    smtp.login(username, password)
    smtp.send_message(message)

print(f"Sent successful-build notification to {recipient}.")

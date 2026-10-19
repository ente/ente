import base64
import hashlib
import hmac
import json
import os
import pty
import re
import select
import signal
import subprocess
import sys
import termios
import time

binary, origin, email = sys.argv[1:]


def run(args, replies):
    pid, fd = pty.fork()
    if pid == 0:
        os.execv(binary, args)
    output = b""
    deadline = time.monotonic() + 90

    def expect(text):
        nonlocal output
        while text not in output:
            assert time.monotonic() < deadline, output.decode(errors="replace")
            if select.select([fd], [], [], 0.1)[0]:
                output += os.read(fd, 65536)
        before, output = output.split(text, 1)
        return before

    def send(value, secure=False):
        while secure and termios.tcgetattr(fd)[3] & termios.ECHO:
            assert time.monotonic() < deadline, output.decode(errors="replace")
            time.sleep(0.01)
        os.write(fd, value + b"\r")

    try:
        replies(expect, send)
        while time.monotonic() < deadline:
            done, status = os.waitpid(pid, os.WNOHANG)
            if done:
                assert os.waitstatus_to_exitcode(status) == 0, output.decode(errors="replace")
                return
            if select.select([fd], [], [], 0.1)[0]:
                try:
                    output += os.read(fd, 65536)
                except OSError:
                    pass
        raise AssertionError(output.decode(errors="replace"))
    finally:
        os.close(fd)
        try:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        except ProcessLookupError:
            pass


def create(expect, send):
    for prompt, answer, secure in [
        (b"Email:", email.encode(), False),
        (b"privacy policy?", b"y", False),
        (b"Email verification code:", b"123456", True),
        (b"Password:", b"disposable-password", True),
        (b"Confirm password:", b"disposable-password", True),
    ]:
        expect(prompt)
        send(answer, secure)
    expect(b"Created ")


def enable(expect, send):
    text = expect(b"Authenticator code:")
    secret = re.search(rb"authenticator: ([A-Z2-7]+)", text)[1]
    send(b"invalid", True)
    expect(b"Code not accepted. Check the code and your computer's date and time, then try again.")
    expect(b"Authenticator code:")
    key = base64.b32decode(secret + b"=" * (-len(secret) % 8))
    digest = hmac.new(key, (int(time.time()) // 30).to_bytes(8, "big"), hashlib.sha1).digest()
    offset = digest[-1] & 15
    code = (int.from_bytes(digest[offset:offset + 4], "big") & 0x7fffffff) % 1000000
    send(f"{code:06d}".encode(), True)


def login(expect, send, email_mfa):
    expect(b"Password:")
    send(b"wrong-password", True)
    if email_mfa:
        expect(b"Email verification code:")
        send(b"123456", True)
    expect(b"Incorrect password. Try again.")
    expect(b"Password:")
    send(b"disposable-password", True)
    expect(b"Logged in")


run([binary, "account", "create", "--host", origin], create)
for email_mfa in [True, False]:
    subprocess.run(
        [binary, "photos", "api", "/users/email-mfa", "--method", "PUT", "--body", "-"],
        input=json.dumps({"isEnabled": email_mfa}).encode(), check=True, capture_output=True,
    )
    run([binary, "account", "login", "--app", "photos", "--email", email],
        lambda expect, send: login(expect, send, email_mfa))
run([binary, "account", "totp", "enable"], enable)

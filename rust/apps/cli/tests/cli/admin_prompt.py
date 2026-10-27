import os
import pty
import select
import signal
import sys
import time

binary, email, mode = sys.argv[1:]
args = [binary, "admin", "user", "update-subscription", email]
if mode == "decline":
    args += ["--storage", "2GB"]
pid, fd = pty.fork()
if pid == 0:
    os.execv(binary, args)
output = b""
cursor = 0
deadline = time.monotonic() + 20


def read_output():
    global output
    if select.select([fd], [], [], 0.1)[0]:
        try:
            output += os.read(fd, 65536)
        except OSError:
            pass


def expect(text):
    global cursor
    expected = text.encode()
    while expected not in output[cursor:]:
        assert time.monotonic() < deadline, output.decode(errors="replace")
        read_output()
    cursor = output.index(expected, cursor) + len(expected)


try:
    if mode != "decline":
        expect("Subscription limits")
        os.write(fd, b"\x1b[B\r" if mode == "preset" else b"\x1b[B\x1b[B\r")
    if mode in ("storage", "expiry", "empty"):
        expect("Storage (")
        os.write(fd, b"1.5MB\r" if mode == "storage" else b"\r")
        expect("Expiry (")
        os.write(fd, b"2035-01-01\r" if mode == "expiry" else b"\r")
    if mode == "empty":
        expect("no subscription changes supplied")
    else:
        expect("Update subscription for")
        assert b"Storage:" in output and b"Expires:" in output
        os.write(fd, b"\r" if mode == "decline" else b"y\r")
    while time.monotonic() < deadline:
        done, status = os.waitpid(pid, os.WNOHANG)
        if done:
            assert os.waitstatus_to_exitcode(status) == (
                1 if mode in ("decline", "empty") else 0
            ), output.decode(errors="replace")
            break
        read_output()
    else:
        raise AssertionError(output.decode(errors="replace"))
finally:
    os.close(fd)
    try:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    except ProcessLookupError:
        pass

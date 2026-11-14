#!/usr/bin/env python3
"""Import, validate the demo protocol, and run real host/two-client Iroh sessions."""
import argparse
from contextlib import ExitStack
import subprocess
import time
from bootstrap import ROOT, engine
from godot import run


def smoke(relay_only=False, codes=False):
    work = ROOT / "build" / ("smoke-codes" if codes else "smoke-relay" if relay_only else "smoke")
    work.mkdir(parents=True, exist_ok=True)
    ticket = work / "ticket.txt"
    ticket.unlink(missing_ok=True)
    processes = []
    with ExitStack() as stack:
        def start(role, index):
            path = work / (role + str(index) + ".log")
            stream = stack.enter_context(path.open("w"))
            command = [str(engine()), "--headless", "--path", str(ROOT), "--script", "res://tests/smoke_peer.gd", "--", role, str(ticket)]
            if relay_only:
                command.append("--relay-only")
            if codes:
                command.append("--codes")
            process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT)
            processes.append((process, path, role.upper() + "_PASS"))
            return process
        try:
            host = start("host", 0)
            deadline = time.monotonic() + 25
            while not ticket.exists() and time.monotonic() < deadline and host.poll() is None:
                time.sleep(0.1)
            if not ticket.exists():
                raise RuntimeError("Host did not publish a ticket")
            start("client", 1)
            start("client", 2)
            for process, path, marker in processes:
                process.wait(timeout=70)
                text = path.read_text()
                if process.returncode or marker not in text or "ERROR:" in text:
                    raise RuntimeError(text)
            print("IROH_CODE_SMOKE_PASS" if codes else "IROH_RELAY_SMOKE_PASS" if relay_only else "IROH_SMOKE_PASS")
        finally:
            for process, _, _ in processes:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
            ticket.unlink(missing_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--relay-only", action="store_true", help="require public Iroh relay connectivity")
    parser.add_argument("--codes", action="store_true", help="exercise the configured live short-code service, including revocation")
    args = parser.parse_args()
    run(["--headless", "--editor", "--import"], timeout=180)
    output = run(["--headless", "--script", "res://tests/protocol.gd"], timeout=30)
    if "PROTOCOL_PASS" not in output:
        raise RuntimeError("Protocol assertions did not finish")
    output = run(["--headless", "--script", "res://tests/sim_test.gd"], timeout=120)
    if "SIM_PASS" not in output:
        raise RuntimeError("Simulation rule tests failed")
    smoke(args.relay_only, args.codes)

#!/opt/homebrew/bin/python3
"""Minimal Assuan pinentry that answers YubiKey OpenPGP PIN prompts from the macOS login Keychain.

It answers only "PIN" and "Admin PIN" prompts. It cancels instead of answering when gpg-agent
reports a previous wrong PIN (SETERROR), so a bad Keychain value never burns more than one try,
and it cancels any prompt for a new PIN or Reset Code, which this setup never asks for.
"""
import subprocess
import sys
import urllib.parse

KEYCHAIN_SERVICE_PIN = "muertos-yubikey-pin"
KEYCHAIN_SERVICE_ADMIN_PIN = "muertos-yubikey-admin-pin"
ERR_CANCELED = "ERR 83886179 Operation cancelled"


class PinentryRefused(Exception):
    """Raised when a prompt must not be answered from the Keychain."""


def read_keychain(service: str) -> str:
    result = subprocess.run(
        ["/usr/bin/security", "find-generic-password", "-s", service, "-w"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise PinentryRefused(f"keychain lookup failed service={service} rc={result.returncode} stderr={result.stderr.strip()}")
    return result.stdout.strip()


def service_for_prompt(prompt_text: str) -> str:
    lowered = prompt_text.lower()
    if "reset code" in lowered or "new" in lowered:
        raise PinentryRefused(f"refusing prompt for a new PIN or reset code: {prompt_text!r}")
    if "admin pin" in lowered:
        return KEYCHAIN_SERVICE_ADMIN_PIN
    if "pin" in lowered or "unlock the card" in lowered:
        return KEYCHAIN_SERVICE_PIN
    raise PinentryRefused(f"unrecognised prompt: {prompt_text!r}")


def reply(line: str) -> None:
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def main() -> None:
    texts: dict[str, str] = {"SETDESC": "", "SETPROMPT": "", "SETTITLE": ""}
    had_error = False
    reply("OK keychain-pinentry ready")
    for raw in sys.stdin:
        command, _, arg = raw.rstrip("\n").partition(" ")
        command = command.upper()
        if command in texts:
            texts[command] = urllib.parse.unquote(arg)
            reply("OK")
        elif command == "SETERROR":
            had_error = True
            reply("OK")
        elif command == "GETPIN":
            prompt_text = " ".join(texts.values())
            try:
                if had_error:
                    raise PinentryRefused(f"previous PIN was rejected, not retrying: {prompt_text!r}")
                pin = read_keychain(service_for_prompt(prompt_text))
            except PinentryRefused as error:
                print(f"keychain-pinentry: {error}", file=sys.stderr)
                reply(ERR_CANCELED)
                continue
            reply("D " + urllib.parse.quote(pin, safe=""))
            reply("OK")
        elif command == "BYE":
            reply("OK closing connection")
            return
        else:
            reply("OK")


if __name__ == "__main__":
    main()

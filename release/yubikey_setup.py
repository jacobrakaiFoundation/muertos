#!/opt/homebrew/bin/python3
"""Set up a factory-reset YubiKey OpenPGP card for the muertos signing key, with PINs in the Keychain.

Steps: generate random PINs, save them to the macOS login Keychain, change the card PINs from the
factory defaults, point the muertos GnuPG home at keychain_pinentry.py, generate the key on the card
(RSA 4096 signature slot) and require a touch for every signature.
Run only on a card that was just reset with `ykman openpgp reset`.
"""
import os
import re
import secrets
import shutil
import subprocess
from pathlib import Path

from keychain_pinentry import KEYCHAIN_SERVICE_ADMIN_PIN, KEYCHAIN_SERVICE_PIN

GNUPG_HOME = Path.home() / ".muertos-gnupg"
PINENTRY_SOURCE = Path(__file__).resolve().parent / "keychain_pinentry.py"
DEFAULT_PIN = "123456"
DEFAULT_ADMIN_PIN = "12345678"
KEY_NAME = "muertos signing key"
KEY_EMAIL = "jacob.e.durham@gmail.com"
KEY_EXPIRY = "5y"
# key-attr asks for the signature, encryption and authentication slots in that order
SLOT_RSA_SIZES = ["4096", "2048", "2048"]


class SetupError(Exception):
    """Raised when a setup step fails; the message names the step and the tool output."""


def run(args: list[str], step: str) -> str:
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        safe_args = [args[0], *args[1:3]]
        raise SetupError(f"{step} failed cmd={safe_args} rc={result.returncode} stderr={result.stderr.strip()}")
    return result.stdout


def random_digits(length: int) -> str:
    return "".join(secrets.choice("0123456789") for _ in range(length))


def assert_factory_card() -> None:
    info = run(["ykman", "openpgp", "info"], "read card info")
    pin_tries = re.search(r"PIN tries remaining:\s+(\d+)", info)
    admin_tries = re.search(r"Admin PIN tries remaining:\s+(\d+)", info)
    if pin_tries is None or admin_tries is None:
        raise SetupError(f"could not parse retry counters from ykman output: {info!r}")
    if pin_tries.group(1) != "3" or admin_tries.group(1) != "3":
        raise SetupError(f"card is not freshly reset pin_tries={pin_tries.group(1)} admin_tries={admin_tries.group(1)}")


def save_to_keychain(service: str, secret: str) -> None:
    run(
        ["/usr/bin/security", "add-generic-password", "-U", "-s", service, "-a", os.environ["USER"],
         "-T", "/usr/bin/security", "-w", secret],
        f"save {service} to keychain",
    )


def install_pinentry() -> None:
    target = GNUPG_HOME / "keychain_pinentry.py"
    shutil.copyfile(PINENTRY_SOURCE, target)
    target.chmod(0o700)
    (GNUPG_HOME / "gpg-agent.conf").write_text(f"pinentry-program {target}\n")
    run(["gpgconf", "--homedir", str(GNUPG_HOME), "--kill", "gpg-agent"], "restart gpg-agent")


def card_edit_answers() -> dict[str, list[str]]:
    return {
        "cardedit.prompt": ["admin", "key-attr", "generate", "quit"],
        "cardedit.genkeys.algo": ["1", "1", "1"],
        "cardedit.genkeys.size": list(SLOT_RSA_SIZES),
        "cardedit.genkeys.backup_enc": ["n"],
        "keygen.valid": [KEY_EXPIRY],
        "keygen.valid.okay": ["y"],
        "keygen.name": [KEY_NAME],
        "keygen.email": [KEY_EMAIL],
        "keygen.comment": [""],
        "keygen.userid.cmd": ["O"],
    }


def generate_on_card() -> None:
    answers = card_edit_answers()
    process = subprocess.Popen(
        ["gpg", "--homedir", str(GNUPG_HOME), "--no-tty", "--status-fd", "1", "--command-fd", "0", "--card-edit"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    transcript: list[str] = []
    for line in process.stdout:
        transcript.append(line.rstrip())
        match = re.match(r"\[GNUPG:\] GET_(LINE|BOOL|HIDDEN) (\S+)", line)
        if match is None:
            continue
        keyword = match.group(2)
        queue = answers.get(keyword)
        if not queue:
            process.kill()
            raise SetupError(f"unexpected gpg prompt keyword={keyword} transcript={transcript[-15:]}")
        process.stdin.write(queue.pop(0) + "\n")
        process.stdin.flush()
    stderr = process.stderr.read()
    if process.wait() != 0 or "KEY_CREATED" not in "\n".join(transcript):
        raise SetupError(f"card key generation failed rc={process.returncode} stderr={stderr.strip()} transcript={transcript[-15:]}")


def main() -> None:
    assert_factory_card()
    pin = random_digits(8)
    admin_pin = random_digits(12)
    # Keychain first, so a PIN is never set on the card without a saved copy
    save_to_keychain(KEYCHAIN_SERVICE_PIN, pin)
    save_to_keychain(KEYCHAIN_SERVICE_ADMIN_PIN, admin_pin)
    run(["ykman", "openpgp", "access", "change-admin-pin", "-a", DEFAULT_ADMIN_PIN, "-n", admin_pin], "change Admin PIN")
    run(["ykman", "openpgp", "access", "change-pin", "-P", DEFAULT_PIN, "-n", pin], "change PIN")
    install_pinentry()
    generate_on_card()
    run(["ykman", "openpgp", "keys", "set-touch", "sig", "on", "-a", admin_pin, "-f"], "set touch policy")
    print(run(["gpg", "--homedir", str(GNUPG_HOME), "--list-keys", KEY_EMAIL], "list new key"))


if __name__ == "__main__":
    main()

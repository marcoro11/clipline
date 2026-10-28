#!/usr/bin/env python3
"""Sign local builds with a persistent, project-private development identity.

The identity is not added to system trust or the login keychain. A private
keychain is passed directly to codesign, and its search-list entry is removed
immediately after creation. No Accessibility permissions are changed here.
"""
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import sys
import tempfile


def run(arguments):
    result = subprocess.run(arguments, text=True, capture_output=True)
    if result.returncode:
        # Do not include command arguments: keychain commands contain a password.
        raise RuntimeError(f"{Path(arguments[0]).name}: {result.stderr.strip() or 'command failed'}")
    return result.stdout


def sign(app):
    external_identity = os.environ.get("CLIPLINE_SIGNING_IDENTITY")
    if external_identity:
        run(["/usr/bin/codesign", "--force", "--sign", external_identity,
             "--identifier", "app.clipline.mac", "--timestamp=none", str(app)])
        print("Signed with the configured code-signing identity.")
        return

    root = Path(__file__).resolve().parent.parent / ".local-signing"
    os.umask(0o077)
    root.mkdir(mode=0o700, exist_ok=True)
    keychain = root / "clipline.keychain-db"
    password_file = root / "keychain-password"
    identity_file = root / "identity"
    certificate = root / "certificate.pem"

    if not (keychain.exists() and password_file.exists() and identity_file.exists()):
        password = password_file.read_text().strip() if password_file.exists() else secrets.token_hex(32)
        password_file.write_text(password)
        if not keychain.exists():
            search_list = shlex.split(run(["/usr/bin/security", "list-keychains", "-d", "user"]))
            try:
                run(["/usr/bin/security", "create-keychain", "-p", password, str(keychain)])
            finally:
                run(["/usr/bin/security", "list-keychains", "-d", "user", "-s", *search_list])

        run(["/usr/bin/security", "unlock-keychain", "-p", password, str(keychain)])
        with tempfile.TemporaryDirectory(dir=root) as temporary:
            directory = Path(temporary)
            config = directory / "certificate.cnf"
            config.write_text("""[req]
prompt = no
distinguished_name = subject
x509_extensions = codesign
[subject]
CN = Clipline Local Development
[codesign]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
""")
            key = directory / "private-key.pem"
            archive = directory / "identity.p12"
            run(["openssl", "req", "-new", "-x509", "-newkey", "rsa:2048", "-sha256", "-nodes",
                 "-days", "3650", "-config", str(config), "-keyout", str(key), "-out", str(certificate)])
            # macOS Security imports the legacy PKCS#12 encryption formats.
            run(["openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(certificate),
                 "-name", "Clipline Local Development", "-out", str(archive),
                 "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES", "-macalg", "sha1",
                 "-passout", f"file:{password_file}"])
            run(["/usr/bin/security", "import", str(archive), "-k", str(keychain),
                 "-P", password, "-T", "/usr/bin/codesign"])
            run(["/usr/bin/security", "set-key-partition-list", "-S", "apple-tool:,codesign:",
                 "-s", "-k", password, str(keychain)])
        fingerprint = run(["openssl", "x509", "-in", str(certificate), "-noout", "-fingerprint", "-sha1"])
        identity_file.write_text(fingerprint.strip().split("=", 1)[1].replace(":", ""))
        print("Created a persistent local development identity for Clipline.")

    password = password_file.read_text().strip()
    identity = identity_file.read_text().strip()
    try:
        run(["/usr/bin/security", "unlock-keychain", "-p", password, str(keychain)])
        run(["/usr/bin/codesign", "--force", "--sign", identity, "--keychain", str(keychain),
             "--identifier", "app.clipline.mac", "--timestamp=none", str(app)])
        run(["/usr/bin/codesign", "--verify", "--verbose", str(app)])
    finally:
        run(["/usr/bin/security", "lock-keychain", str(keychain)])
    print("Signed Clipline with its persistent local development identity.")


if __name__ == "__main__":
    try:
        sign(Path(sys.argv[1]).resolve())
    except (RuntimeError, OSError, IndexError) as error:
        print(f"Signing failed: {error}", file=sys.stderr)
        sys.exit(1)

"""
Make a self-signed HTTPS certificate for the office network (certs/server.crt + server.key).

run.bat calls this before starting the network server, so HR's browsers and phones talk to it
over HTTPS. It only makes a new certificate when there is none yet, or when this PC's network
address has changed since. Browsers will warn once that the certificate is self-signed
("not from a known authority") — that is expected for a PC on a local network.

    python scripts/make_cert.py          # make one if needed
    python scripts/make_cert.py --force  # always make a new one
"""
import argparse
import datetime as dt
import ipaddress
import os
import socket
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CERT_DIR = os.path.join(ROOT, "certs")
CERT, KEY = os.path.join(CERT_DIR, "server.crt"), os.path.join(CERT_DIR, "server.key")


def lan_ip() -> str | None:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.254.254.254", 1))  # no packets are sent
            return s.getsockname()[0]
    except OSError:
        return None


def wanted_names() -> tuple[list[str], list[str]]:
    hosts = ["localhost", socket.gethostname()]
    ips = ["127.0.0.1"] + ([lan_ip()] if lan_ip() else [])
    return hosts, ips


def up_to_date() -> bool:
    if not (os.path.exists(CERT) and os.path.exists(KEY)):
        return False
    cert = x509.load_pem_x509_certificate(open(CERT, "rb").read())
    if cert.not_valid_after_utc < dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=30):
        return False
    san = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
    have = {str(ip) for ip in san.get_values_for_type(x509.IPAddress)}
    return set(wanted_names()[1]) <= have


def make() -> None:
    hosts, ips = wanted_names()
    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "NanoNino attendance server")])
    now = dt.datetime.now(dt.timezone.utc)
    cert = (x509.CertificateBuilder()
            .subject_name(name).issuer_name(name)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - dt.timedelta(minutes=5))
            .not_valid_after(now + dt.timedelta(days=825))
            .add_extension(x509.SubjectAlternativeName(
                [x509.DNSName(h) for h in hosts] + [x509.IPAddress(ipaddress.ip_address(i)) for i in ips]),
                critical=False)
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .add_extension(x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
            .sign(key, hashes.SHA256()))
    os.makedirs(CERT_DIR, exist_ok=True)
    with open(KEY, "wb") as f:
        f.write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                  serialization.NoEncryption()))
    with open(CERT, "wb") as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))
    print(f"New certificate for {', '.join(hosts + ips)} in {CERT_DIR}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    if args.force or not up_to_date():
        make()
    else:
        print("Certificate is up to date.")
    sys.exit(0)

"""
Document signing service.

Replaces Cloud KMS from the GCP design. The private key is generated once,
PEM-encoded, and stored as a Vercel encrypted environment variable
(DOCUMENT_SIGNING_PRIVATE_KEY) -- never committed to the repo, never logged.

This mirrors the ECDSA-P256 signing pattern already used in the SIH project,
adapted here to single-tenant use: every uploaded document's SHA-256 hash is
signed, and the signature is stored alongside the document row so tampering
with a stored file (or its recorded hash) after the fact is detectable.

Compensating-control note: Cloud KMS keeps the private key in hardware and
never exposes it to application code, even to the app itself. Storing the
key as an environment variable is a weaker guarantee -- anyone with access
to the Vercel project's environment variables can technically export it.
This tradeoff should be stated explicitly in the security write-up rather
than left implicit.
"""

import base64

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils as asym_utils

from app.core.config import get_settings


def _load_private_key() -> ec.EllipticCurvePrivateKey:
    settings = get_settings()
    pem = settings.document_signing_private_key.replace("\\n", "\n").encode()
    key = serialization.load_pem_private_key(pem, password=None)
    if not isinstance(key, ec.EllipticCurvePrivateKey):
        raise RuntimeError("DOCUMENT_SIGNING_PRIVATE_KEY is not an EC private key")
    return key


def sign_hash(sha256_hex: str) -> str:
    """
    Signs a hex-encoded SHA-256 digest with ECDSA-P256, returns a
    base64-encoded DER signature suitable for storage in documents.kms_signature.
    """
    private_key = _load_private_key()
    digest_bytes = bytes.fromhex(sha256_hex)
    signature = private_key.sign(
        digest_bytes,
        ec.ECDSA(asym_utils.Prehashed(hashes.SHA256())),
    )
    return base64.b64encode(signature).decode()


def verify_signature(sha256_hex: str, signature_b64: str, public_key_pem: str) -> bool:
    """
    Verifies a stored signature against a hash, using the corresponding
    public key. Used by the audit/verification endpoint to prove a document
    hasn't been tampered with since upload.
    """
    public_key = serialization.load_pem_public_key(public_key_pem.encode())
    digest_bytes = bytes.fromhex(sha256_hex)
    signature = base64.b64decode(signature_b64)
    try:
        public_key.verify(
            signature,
            digest_bytes,
            ec.ECDSA(asym_utils.Prehashed(hashes.SHA256())),
        )
        return True
    except Exception:
        return False


def generate_key_pair_pem() -> tuple[str, str]:
    """
    One-time setup helper: generates a new ECDSA-P256 key pair and returns
    (private_key_pem, public_key_pem). Run this once locally, put the private
    key into Vercel's DOCUMENT_SIGNING_PRIVATE_KEY env var, and keep the
    public key in the repo (it's safe to be public -- it only verifies,
    never signs).
    """
    private_key = ec.generate_private_key(ec.SECP256R1())
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode()
    public_pem = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode()
    return private_pem, public_pem


if __name__ == "__main__":
    priv, pub = generate_key_pair_pem()
    print("=== PRIVATE KEY (put in Vercel env var DOCUMENT_SIGNING_PRIVATE_KEY) ===")
    print(priv)
    print("=== PUBLIC KEY (safe to commit to repo, e.g. docs/signing_public_key.pem) ===")
    print(pub)

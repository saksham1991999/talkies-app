"""The access-token matrix. Keys are made here: no network, no Supabase."""

import base64
import hashlib
import hmac
import json
import time
from uuid import uuid4

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa

from app.auth.jwt import Verifier
from app.errors import Unauthorized, Upstream
from tests.helpers import JWT_SECRET, SUPABASE_URL, FakeClock, make_settings, make_token


def _jwk(public_key, kid: str, alg: str) -> dict:
    algorithm = jwt.algorithms.ECAlgorithm if alg == "ES256" else jwt.algorithms.RSAAlgorithm
    jwk = json.loads(algorithm.to_jwk(public_key))
    return {**jwk, "kid": kid, "alg": alg, "use": "sig"}


@pytest.fixture(scope="module")
def ec_key():
    return ec.generate_private_key(ec.SECP256R1())


@pytest.fixture(scope="module")
def other_ec_key():
    return ec.generate_private_key(ec.SECP256R1())


@pytest.fixture(scope="module")
def rsa_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


class Jwks:
    """A fake JWKS endpoint that counts its calls."""

    def __init__(self, keys: list[dict]):
        self.keys = keys
        self.calls = 0
        self.fail = False

    def __call__(self, request: httpx.Request) -> httpx.Response:
        assert str(request.url) == f"{SUPABASE_URL}/auth/v1/.well-known/jwks.json"
        self.calls += 1
        if self.fail:
            return httpx.Response(500)
        return httpx.Response(200, json={"keys": self.keys})


def make_verifier(jwks: Jwks, clock: FakeClock | None = None, **settings) -> Verifier:
    http = httpx.AsyncClient(transport=httpx.MockTransport(jwks))
    return Verifier(make_settings(**settings), http, clock or FakeClock())


@pytest.fixture
def jwks(ec_key, rsa_key):
    return Jwks(
        [_jwk(ec_key.public_key(), "ec1", "ES256"), _jwk(rsa_key.public_key(), "rsa1", "RS256")]
    )


async def test_es256_valid(jwks, ec_key):
    user = uuid4()
    token = make_token(user, ec_key, "ES256", kid="ec1")
    assert await make_verifier(jwks).verify(token) == user


async def test_rs256_valid(jwks, rsa_key):
    user = uuid4()
    token = make_token(user, rsa_key, "RS256", kid="rsa1")
    assert await make_verifier(jwks).verify(token) == user


async def test_hs256_valid_only_with_a_secret(jwks):
    user = uuid4()
    token = make_token(user)
    assert await make_verifier(jwks).verify(token) == user
    with pytest.raises(Unauthorized):
        await make_verifier(jwks, supabase_jwt_secret="").verify(token)


async def test_none_algorithm_is_refused(jwks):
    now = int(time.time())
    claims = {
        "iss": f"{SUPABASE_URL}/auth/v1",
        "aud": "authenticated",
        "sub": str(uuid4()),
        "role": "authenticated",
        "exp": now + 3600,
    }
    token = jwt.encode(claims, key=None, algorithm="none")
    with pytest.raises(Unauthorized):
        await make_verifier(jwks).verify(token)


async def test_other_algorithms_are_refused(jwks):
    token = make_token(alg="HS512", key=JWT_SECRET * 2)
    with pytest.raises(Unauthorized):
        await make_verifier(jwks).verify(token)


def _forge_hs256(secret: bytes, claims: dict, kid: str) -> str:
    """Sign by hand: PyJWT itself refuses a PEM key as an HMAC secret."""

    def b64(data: bytes) -> bytes:
        return base64.urlsafe_b64encode(data).rstrip(b"=")

    header = {"alg": "HS256", "typ": "JWT", "kid": kid}
    signing = b64(json.dumps(header).encode()) + b"." + b64(json.dumps(claims).encode())
    signature = b64(hmac.new(secret, signing, hashlib.sha256).digest())
    return (signing + b"." + signature).decode()


async def test_hs256_signed_with_the_public_key_is_refused(jwks, ec_key):
    """Algorithm confusion: the public JWKS key must never work as an HMAC secret."""
    public_pem = ec_key.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    claims = {
        "iss": f"{SUPABASE_URL}/auth/v1",
        "aud": "authenticated",
        "sub": str(uuid4()),
        "role": "authenticated",
        "exp": int(time.time()) + 3600,
    }
    token = _forge_hs256(public_pem, claims, "ec1")
    with pytest.raises(Unauthorized):
        await make_verifier(jwks, supabase_jwt_secret="").verify(token)
    with pytest.raises(Unauthorized):
        await make_verifier(jwks).verify(token)  # a secret is set: the signature is wrong


async def test_key_type_must_match_the_algorithm(jwks, ec_key):
    """An ES256 token that names the RSA key is refused."""
    token = make_token(key=ec_key, alg="ES256", kid="rsa1")
    with pytest.raises(Unauthorized):
        await make_verifier(jwks).verify(token)


async def test_wrong_signature(jwks, other_ec_key):
    token = make_token(key=other_ec_key, alg="ES256", kid="ec1")
    with pytest.raises(Unauthorized):
        await make_verifier(jwks).verify(token)


async def test_tampered_token(jwks):
    token = make_token()
    head, body, signature = token.split(".")
    forged = ".".join([head, body[:-2] + ("AA" if not body.endswith("AA") else "BB"), signature])
    with pytest.raises(Unauthorized):
        await make_verifier(jwks).verify(forged)


@pytest.mark.parametrize(
    "claims",
    [
        {"aud": "anon"},
        {"aud": None},
        {"iss": "https://evil.example/auth/v1"},
        {"iss": None},
        {"exp": int(time.time()) - 3600},
        {"exp": None},
        {"role": "anon"},
        {"role": "service_role"},
        {"role": None},
        {"is_anonymous": True},
        {"sub": "not-a-uuid"},
        {"sub": None},
    ],
)
async def test_bad_claims(jwks, claims):
    with pytest.raises(Unauthorized):
        await make_verifier(jwks).verify(make_token(**claims))


async def test_garbage_is_refused(jwks):
    for token in ("", "abc", "a.b.c", "Bearer x"):
        with pytest.raises(Unauthorized):
            await make_verifier(jwks).verify(token)


async def test_asymmetric_token_needs_a_kid(jwks, ec_key):
    with pytest.raises(Unauthorized):
        await make_verifier(jwks).verify(make_token(key=ec_key, alg="ES256"))


async def test_unknown_kid_refetches_at_most_once_a_minute(jwks, ec_key):
    clock = FakeClock()
    verifier = make_verifier(jwks, clock)
    stranger = make_token(key=ec_key, alg="ES256", kid="new-key")
    with pytest.raises(Unauthorized):
        await verifier.verify(stranger)
    assert jwks.calls == 1
    # A known key needs no fetch. An unknown one within the minute does not refetch.
    await verifier.verify(make_token(key=ec_key, alg="ES256", kid="ec1"))
    with pytest.raises(Unauthorized):
        await verifier.verify(stranger)
    assert jwks.calls == 1
    # After a minute the new key can appear.
    jwks.keys.append(_jwk(ec_key.public_key(), "new-key", "ES256"))
    clock.advance(61)
    await verifier.verify(stranger)
    assert jwks.calls == 2


async def test_unreachable_jwks_is_502_not_401(jwks, ec_key):
    jwks.fail = True
    clock = FakeClock()
    verifier = make_verifier(jwks, clock)
    token = make_token(key=ec_key, alg="ES256", kid="ec1")
    with pytest.raises(Upstream):
        await verifier.verify(token)
    jwks.fail = False
    clock.advance(61)
    assert await verifier.verify(token)


async def test_a_cached_key_survives_a_failing_jwks(jwks, ec_key):
    clock = FakeClock()
    verifier = make_verifier(jwks, clock)
    token = make_token(key=ec_key, alg="ES256", kid="ec1")
    await verifier.verify(token)
    jwks.fail = True
    clock.advance(3600)
    assert await verifier.verify(token)


async def test_the_secret_and_jwks_paths_never_mix(jwks, ec_key):
    """An empty JWKS cannot fall back to the shared secret, and the reverse."""
    user = uuid4()
    hs_token = make_token(user)
    es_token = make_token(user, ec_key, "ES256", kid="ec1")
    no_keys = Jwks([])
    # HS256 verifies through the secret alone.
    assert await make_verifier(no_keys).verify(hs_token) == user
    # ES256 must come from the JWKS, even though a secret is configured.
    with pytest.raises(Unauthorized):
        await make_verifier(no_keys).verify(es_token)


async def test_an_hs512_header_is_refused_even_with_a_secret(jwks):
    with pytest.raises(Unauthorized):
        await make_verifier(jwks).verify(make_token(alg="HS512", key=JWT_SECRET * 2))

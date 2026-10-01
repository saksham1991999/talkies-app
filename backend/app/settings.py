"""Settings from environment variables (and a local .env file)."""

from functools import lru_cache
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from pydantic_settings import BaseSettings, SettingsConfigDict

KNOWN_PROVIDERS = ("email", "google", "apple")

# Query parameters some tools add to a pooler URL. asyncpg would send them to
# the server as settings, and the server rejects them.
_DROP_QUERY = {"pgbouncer", "connection_limit"}


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", env_ignore_empty=True)

    supabase_url: str = ""
    supabase_anon_key: str = ""
    supabase_service_role_key: str = ""
    # Only for projects that still sign tokens with the shared HS256 secret.
    supabase_jwt_secret: str = ""
    database_url: str = ""
    public_base_url: str = ""
    # Comma list of sign-in methods to offer: email, google, apple.
    auth_providers: str = "email"
    # Sign in with Apple revocation (App Store rule 4.8). The secret is the
    # ES256 client-secret JWT minted from the Apple team key. Both must be set
    # for the backend to exchange sign-in codes and revoke on account deletion.
    apple_client_id: str = ""
    apple_client_secret: str = ""
    db_pool_max: int = 10

    @property
    def base_url(self) -> str:
        return self.supabase_url.rstrip("/")

    @property
    def issuer(self) -> str:
        return f"{self.base_url}/auth/v1"

    @property
    def providers(self) -> list[str]:
        names = [p.strip().lower() for p in self.auth_providers.split(",")]
        listed = [p for p in KNOWN_PROVIDERS if p in names]
        return listed or ["email"]

    @property
    def dsn(self) -> str:
        return clean_dsn(self.database_url)


def clean_dsn(url: str) -> str:
    """Remove query parameters that only a pooler client understands."""
    if not url:
        return ""
    parts = urlsplit(url)
    keep = [(k, v) for k, v in parse_qsl(parts.query) if k.lower() not in _DROP_QUERY]
    return urlunsplit(parts._replace(query=urlencode(keep)))


@lru_cache
def get_settings() -> Settings:
    return Settings()

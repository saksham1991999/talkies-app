"""Settings from the environment, and the rules for a transaction pooler."""

import ast
import re
from pathlib import Path

from app.settings import Settings, clean_dsn

APP = Path(__file__).resolve().parents[2] / "app"


def test_the_pooler_suffix_is_removed_and_the_rest_is_kept():
    url = "postgresql://postgres.ref:p%40ss@aws-0-eu.pooler.supabase.com:6543/postgres"
    assert clean_dsn(url + "?pgbouncer=true") == url
    assert clean_dsn(url + "?pgbouncer=true&connection_limit=1") == url
    assert clean_dsn(url + "?sslmode=require&pgbouncer=true") == url + "?sslmode=require"
    assert clean_dsn(url) == url
    assert clean_dsn("") == ""


def test_settings_read_the_environment(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", "https://abc.supabase.co/")
    monkeypatch.setenv("DATABASE_URL", "postgres://u:p@h:6543/db?pgbouncer=true")
    monkeypatch.setenv("AUTH_PROVIDERS", "Google, apple,nonsense")
    monkeypatch.setenv("SUPABASE_JWT_SECRET", "")  # an empty value counts as not set
    settings = Settings(_env_file=None)
    assert settings.issuer == "https://abc.supabase.co/auth/v1"
    assert settings.dsn == "postgres://u:p@h:6543/db"
    assert settings.providers == ["google", "apple"]
    assert settings.supabase_jwt_secret == ""
    assert Settings(_env_file=None, auth_providers="").providers == ["email"]


def test_defaults_boot_with_nothing_set(monkeypatch):
    for name in ("SUPABASE_URL", "DATABASE_URL", "AUTH_PROVIDERS", "PUBLIC_BASE_URL"):
        monkeypatch.delenv(name, raising=False)
    settings = Settings(_env_file=None)
    assert (settings.dsn, settings.providers, settings.db_pool_max) == ("", ["email"], 10)


def test_nothing_the_pooler_breaks():
    """No prepare, SET, LISTEN, session advisory lock, or temp table in the app."""
    statement = re.compile(
        r"^\s*(set\s+\w|reset\s+\w|listen\s|unlisten\s|notify\s|prepare\s|deallocate\s|discard\s|create\s+temp\w*)|"
        r"\bpg_(try_)?advisory_lock\s*\(|\bpg_advisory_unlock",
        re.I,
    )
    calls = {"prepare", "add_listener", "remove_listener", "set_builtin_type_codec"}
    for path in APP.rglob("*.py"):
        tree = ast.parse(path.read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.Constant) and isinstance(node.value, str):
                assert not statement.search(node.value), f"{path.name}:{node.lineno}"
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
                assert node.func.attr not in calls, f"{path.name}:{node.lineno}"


def test_locks_are_transaction_locks_and_use_the_same_key_as_delete_account():
    migration = (
        APP.parents[1] / "supabase" / "migrations" / "20261001000001_phase1_accounts_sync.sql"
    ).read_text()
    key = "hashtextextended(p_user::text, 0)"
    assert key in migration and "pg_advisory_xact_lock" in migration
    db = (APP / "db.py").read_text()
    assert "pg_advisory_xact_lock(hashtextextended($1::text, 0))" in db

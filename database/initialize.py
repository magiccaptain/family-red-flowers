"""Initialize the application's schema and a restricted family login, never print secrets."""
from __future__ import annotations

import json
import os
from pathlib import Path
import secrets
from uuid import UUID, uuid4

import psycopg
from psycopg import sql
from dotenv import dotenv_values

ROOT = Path(__file__).resolve().parent.parent


def admin_parameters(env: dict) -> dict:
    return {
        "host": env["PG_HOST"],
        "port": int(env.get("PG_PORT") or 5432),
        "dbname": env.get("PG_DATABASE") or env.get("PG_DBNAME") or "postgres",
        "user": env["PG_USERNAME"],
        "password": env["PG_PASSWORD"],
        "connect_timeout": 10,
        "sslmode": env.get("PG_SSLMODE") or "prefer",
        "application_name": "red-flowers-database-setup",
    }


def initialize() -> None:
    env_path = ROOT / ".env"
    if not env_path.is_file():
        raise RuntimeError("在项目 .env 文件中填写 PG_HOST、PG_PORT、PG_USERNAME、PG_PASSWORD")
    env = dict(dotenv_values(env_path))
    role = env.get("RF_APP_USERNAME") or "red_flowers_app"
    password = env.get("RF_APP_PASSWORD") or secrets.token_urlsafe(36)
    family_id = str(UUID(env["RF_FAMILY_ID"])) if env.get("RF_FAMILY_ID") else str(uuid4())
    params = admin_parameters(env)
    if role == params["user"] or not role.startswith("red_flowers_"):
        raise RuntimeError("应用账号必须是独立的 red_flowers_ 前缀账号")
    with psycopg.connect(**params) as db:
        db.execute("SELECT pg_advisory_xact_lock(732048198726)")
        db.execute((ROOT / "database/schema.sql").read_text())
        existing = db.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (role,)).fetchone()
        known = db.execute("SELECT id::text FROM red_flowers.families WHERE login_role = %s", (role,)).fetchone()
        if existing and (not known or known[0] != family_id or not env.get("RF_APP_PASSWORD")):
            raise RuntimeError("该应用账号已存在，请恢复原 RF_APP_* 配置；不会重置已有账号")
        if not existing:
            db.execute(sql.SQL("CREATE ROLE {} LOGIN PASSWORD {} NOSUPERUSER NOCREATEDB "
                               "NOCREATEROLE NOINHERIT NOREPLICATION CONNECTION LIMIT 16")
                       .format(sql.Identifier(role), sql.Literal(password)))
        db.execute(sql.SQL("GRANT CONNECT ON DATABASE {} TO {}")
                   .format(sql.Identifier(params["dbname"]), sql.Identifier(role)))
        db.execute(sql.SQL("GRANT USAGE ON SCHEMA red_flowers TO {}").format(sql.Identifier(role)))
        db.execute(sql.SQL("REVOKE ALL ON ALL TABLES IN SCHEMA red_flowers FROM {}").format(sql.Identifier(role)))
        db.execute(sql.SQL("REVOKE ALL ON ALL SEQUENCES IN SCHEMA red_flowers FROM {}").format(sql.Identifier(role)))
        db.execute(sql.SQL("REVOKE ALL ON ALL FUNCTIONS IN SCHEMA red_flowers FROM {}").format(sql.Identifier(role)))
        db.execute(sql.SQL("GRANT EXECUTE ON FUNCTION red_flowers.get_garden(), "
                           "red_flowers.apply_command(jsonb) TO {}").format(sql.Identifier(role)))
        for setting, value in [("statement_timeout", "15s"), ("lock_timeout", "10s"),
                               ("idle_in_transaction_session_timeout", "20s")]:
            db.execute(sql.SQL("ALTER ROLE {} SET {} = {}").format(
                sql.Identifier(role), sql.Identifier(setting), sql.Literal(value)))
        db.execute("INSERT INTO red_flowers.families(id, name, login_role) VALUES (%s, %s, %s) "
                   "ON CONFLICT (id) DO NOTHING", (family_id, "我们的小花园", role))
        tls_enabled = db.execute("SHOW ssl").fetchone()[0] == "on"
        counts = db.execute("SELECT (SELECT count(*) FROM red_flowers.children WHERE family_id=%s), "
                            "(SELECT count(*) FROM red_flowers.flower_entries WHERE family_id=%s)",
                            (family_id, family_id)).fetchone()
        # Save the generated credentials before committing so a failed setup never
        # leaves behind a login whose password is unknown to the household.
        additions = {"RF_APP_USERNAME": role, "RF_APP_PASSWORD": password, "RF_FAMILY_ID": family_id,
                     "PG_DATABASE": params["dbname"]}
        text = env_path.read_text()
        for key, value in additions.items():
            if not env.get(key):
                text = text.rstrip("\n") + f"\n{key}='{value}'\n"
        tmp = env_path.with_name(".env.setup-tmp")
        tmp.write_text(text)
        tmp.chmod(0o600)
        os.replace(tmp, env_path)
    config = {
        "host": params["host"], "port": params["port"], "database": params["dbname"],
        "username": role, "password": password,
        "sslMode": "require" if tls_enabled else "disable",
        "familyId": family_id,
    }
    private = ROOT / "artifacts/pg-connection.json"
    private.parent.mkdir(parents=True, exist_ok=True)
    private.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n")
    private.chmod(0o600)
    print(json.dumps({"initialized": True, "schema": "red_flowers", "database": params["dbname"],
                      "tables": ["schema_versions", "families", "children", "flower_entries", "commands"],
                      "existing_children": counts[0], "existing_entries": counts[1],
                      "tls_enabled": tls_enabled, "private_connection_file": "artifacts/pg-connection.json"},
                     ensure_ascii=False))


if __name__ == "__main__":
    try:
        initialize()
    except Exception as error:
        # No DSN, hostname, username, password, or full driver traceback in output.
        state = getattr(error, "sqlstate", None)
        if isinstance(error, RuntimeError):
            print(str(error))
        else:
            print(f"数据库初始化失败：{type(error).__name__}，SQLSTATE={state or 'connection'}")
        raise SystemExit(1)

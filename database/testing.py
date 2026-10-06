"""Temporary, isolated families used by database and Dart integration tests."""
from __future__ import annotations

import json
from pathlib import Path
import secrets
from uuid import uuid4

from dotenv import dotenv_values
import psycopg
from psycopg import sql

from initialize import ROOT, admin_parameters


class TemporaryFamily:
    def __init__(self):
        self.params = admin_parameters(dict(dotenv_values(ROOT / ".env")))
        self.role = "red_flowers_test_" + uuid4().hex[:16]
        self.password = secrets.token_urlsafe(36)
        self.family_id = str(uuid4())
        self.config = {
            "host": self.params["host"], "port": self.params["port"],
            "database": self.params["dbname"], "username": self.role,
            "password": self.password, "familyId": self.family_id, "sslMode": "disable",
        }

    def __enter__(self):
        with psycopg.connect(**self.params) as db:
            db.execute(sql.SQL("CREATE ROLE {} LOGIN PASSWORD {} NOSUPERUSER NOCREATEDB "
                               "NOCREATEROLE NOINHERIT NOREPLICATION CONNECTION LIMIT 16")
                       .format(sql.Identifier(self.role), sql.Literal(self.password)))
            db.execute(sql.SQL("GRANT CONNECT ON DATABASE {} TO {}")
                       .format(sql.Identifier(self.params["dbname"]), sql.Identifier(self.role)))
            db.execute(sql.SQL("GRANT USAGE ON SCHEMA red_flowers TO {}").format(sql.Identifier(self.role)))
            db.execute(sql.SQL("GRANT EXECUTE ON FUNCTION red_flowers.get_garden(), "
                               "red_flowers.apply_command(jsonb) TO {}").format(sql.Identifier(self.role)))
            db.execute("INSERT INTO red_flowers.families(id, name, login_role) VALUES (%s,%s,%s)",
                       (self.family_id, "自动化验证临时家庭", self.role))
            self.config["sslMode"] = "require" if db.execute("SHOW ssl").fetchone()[0] == "on" else "disable"
        return self

    def connect(self):
        return psycopg.connect(**{**self.params, "user": self.role, "password": self.password,
                                  "application_name": "red-flowers-integration-test"})

    def read(self):
        with self.connect() as db:
            return db.execute("SELECT red_flowers.get_garden()").fetchone()[0]

    def apply(self, command):
        with self.connect() as db:
            return db.execute("SELECT red_flowers.apply_command(%s::jsonb)",
                              (json.dumps(command, ensure_ascii=False),)).fetchone()[0]

    def __exit__(self, *_):
        with psycopg.connect(**self.params) as db:
            db.execute("DELETE FROM red_flowers.families WHERE id=%s AND login_role=%s",
                       (self.family_id, self.role))
            db.execute(sql.SQL("DROP OWNED BY {}").format(sql.Identifier(self.role)))
            db.execute(sql.SQL("DROP ROLE {}").format(sql.Identifier(self.role)))


def command(kind, **payload):
    return {"id": str(uuid4()), "kind": kind, "payload": payload}

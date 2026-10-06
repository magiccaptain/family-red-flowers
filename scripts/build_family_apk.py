"""Build the private family APK from the restricted connection configuration."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from uuid import UUID

ROOT = Path(__file__).resolve().parent.parent


def read_preset() -> dict:
    config_file = Path(os.environ.get("RF_PG_CONFIG_FILE") or ROOT / "artifacts/pg-connection.json")
    if not config_file.is_file():
        raise ValueError("缺少家庭连接配置，请先运行 scripts/init-database.sh")
    raw = json.loads(config_file.read_text())
    config = {key: raw[key] for key in (
        "host", "port", "database", "username", "password", "sslMode", "familyId")}
    if (not isinstance(config["port"], int) or not 1 <= config["port"] <= 65535
            or any(not isinstance(config[key], str) or not config[key].strip()
                   for key in ("host", "database", "username", "password", "familyId"))
            or re.search(r"[\s/]", config["host"])
            or config["sslMode"] not in ("disable", "require", "verifyFull")):
        raise ValueError("家庭连接配置不完整，请重新初始化配置")
    if (not config["username"].startswith("red_flowers_")
            or config["username"].startswith("red_flowers_test_")):
        raise ValueError("安装包只能预置初始化生成的家庭应用账号")
    UUID(config["familyId"])
    return config


def main() -> int:
    try:
        config = read_preset()
        version = re.search(r"^version:\s*(\d+\.\d+\.\d+)",
                            (ROOT / "pubspec.yaml").read_text(), re.MULTILINE).group(1)
    except ValueError as error:
        # Validation messages contain no connection values.
        if str(error).startswith(("缺少", "家庭", "安装包")):
            print(str(error))
        else:
            print("家庭连接配置不正确，请重新初始化配置")
        return 1
    except Exception:
        print("家庭连接配置无法读取，请先运行 scripts/init-database.sh")
        return 1

    # Only the filename goes into the public command line. Flutter consumes the
    # private build definitions; the temporary plaintext file is then removed.
    with tempfile.TemporaryDirectory(prefix="red-flowers-family-build-") as folder:
        defines = Path(folder) / "family.json"
        defines.write_text(json.dumps({"RF_PG_PRESET": json.dumps(config)}))
        defines.chmod(0o600)
        result = subprocess.run([
            "flutter", "build", "apk", "--release",
            f"--dart-define-from-file={defines}", *sys.argv[1:],
        ], cwd=ROOT)
        if result.returncode:
            return result.returncode

    source = ROOT / "build/app/outputs/flutter-apk/app-release.apk"
    if not source.is_file():
        print("构建没有生成通用安装包，请使用默认 APK 构建参数")
        return 1
    destination = ROOT / f"artifacts/android/red-flowers-v{version}-family.apk"
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    print(f"家庭专用安装包已生成：{destination.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

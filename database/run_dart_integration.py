import json
import os
from pathlib import Path
import subprocess
import tempfile

from testing import TemporaryFamily, ROOT


def main():
    with TemporaryFamily() as family, tempfile.TemporaryDirectory(prefix="red-flowers-pg-test-") as directory:
        config = Path(directory) / "connection.json"
        config.write_text(json.dumps(family.config))
        config.chmod(0o600)
        defines = Path(directory) / "family-defines.json"
        defines.write_text(json.dumps({"RF_PG_PRESET": json.dumps(family.config)}))
        defines.chmod(0o600)
        test_env = {**os.environ, "RF_PG_TEST_CONFIG": str(config)}
        test_env.pop("RF_PG_CONFIG_FILE", None)
        result = subprocess.run(["flutter", "test", "test/pg_native_integration_test.dart",
                                 "--reporter", "expanded", f"--dart-define-from-file={defines}"],
                                cwd=ROOT, env=test_env)
        status = result.returncode
    raise SystemExit(status)


if __name__ == "__main__":
    main()

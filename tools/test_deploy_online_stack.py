#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
import sys
from pathlib import Path

SCRIPT = Path(__file__).with_name("deploy_online_stack.py")
spec = importlib.util.spec_from_file_location("deploy_online_stack", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


def project(ref: str, name: str):
    return module.SupabaseProject(ref=ref, name=name, region="eu-central-1", status="ACTIVE_HEALTHY")


def main() -> int:
    projects = [project("a" * 20, "Other"), project("b" * 20, "Colony.IO")]
    selected = module.select_project(projects, "colony.io")
    assert selected.ref == "b" * 20
    assert module.normalize_name("Colony.IO") == "colonyio"
    assert module.redact("abcdefghijklmnop") == "abcd…mnop"

    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "config").mkdir()
        config_path = root / "config" / "backend_config.json"
        config_path.write_text(json.dumps({"build_id": "PHASE-05.3-ONLINE-PRODUCTION-COMPLETION", "protocol_version": 3}))
        module.update_client_config(
            root,
            supabase_url="https://example.supabase.co/",
            publishable_key="sb_publishable_test",
            rivet_control_url="https://control.example/",
        )
        config = json.loads(config_path.read_text())
        assert config["supabase_url"] == "https://example.supabase.co"
        assert config["rivet_control_base_url"] == "https://control.example"
        assert "secret" not in json.dumps(config).casefold()


    deploy_source = SCRIPT.read_text(encoding="utf-8")
    assert '"rivet-cli@latest", "deploy"' in deploy_source
    for unsupported in ['"--dockerfile"', '"--build-context"', '"--env"']:
        assert unsupported not in deploy_source

    output = "Deployment ready: https://colony-abc.rivet.run\n"
    assert module.extract_public_url(output) == "https://colony-abc.rivet.run"
    print("DEPLOY_BOOTSTRAP_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

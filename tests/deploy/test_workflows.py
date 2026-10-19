"""CI/CD 워크플로 확인 — 설치 프로그램은 한 스크립트로, CD 는 기본 꺼짐."""

from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

WORKFLOWS = Path(__file__).resolve().parents[2] / ".github" / "workflows"


def load(name: str) -> dict:
    return yaml.safe_load((WORKFLOWS / name).read_text(encoding="utf-8"))


def steps(workflow: dict, job: str) -> str:
    return "\n".join(str(s.get("run", "")) for s in workflow["jobs"][job]["steps"])


def test_ci_and_release_build_installer_with_same_script():
    """CI 와 릴리스가 같은 scripts/build-installer.ps1 로 설치 프로그램을 만든다."""
    assert "scripts/build-installer.ps1" in steps(load("ci.yml"), "installer")
    assert "scripts/build-installer.ps1" in steps(load("release.yml"), "desktop")


def test_ci_checks_powershell_and_deploy_compose():
    """CI 가 PowerShell 구문과 배포용 compose 를 검사하고, 이전 실행을 취소한다."""
    ci = load("ci.yml")
    assert "check-powershell.ps1" in steps(ci, "installer")
    assert "deploy/docker-compose.yml" in steps(ci, "deploy-compose")
    assert ci["concurrency"]["cancel-in-progress"] is True


def test_deploy_is_off_by_default_and_runs_on_self_hosted_server():
    """CD 는 DEPLOY_ENABLED 일 때만, self-hosted 서버에서, production 환경으로 돈다."""
    deploy = load("deploy.yml")
    job = deploy["jobs"]["deploy"]
    assert "vars.DEPLOY_ENABLED == 'true'" in job["if"]
    assert "edgevoice-server" in job["runs-on"]
    assert "self-hosted" in job["runs-on"]
    assert job["environment"] == "production"
    assert "update-server.ps1" in steps(deploy, "deploy")
    # yaml 1.1 은 'on' 을 True 로 읽는다
    triggers = deploy.get("on", deploy.get(True))
    assert {"release", "workflow_run", "workflow_dispatch"} <= set(triggers)

"""deploy/update-server.ps1 이 만드는 명령 확인.

설치 프로그램·CD 가 함께 쓰는 서버 업데이트 스크립트다.
실제 docker 는 부르지 않는다(-DryRun). PowerShell 이 없으면 건너뛴다.
"""

import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SHELL = shutil.which("pwsh") or shutil.which("powershell")
needs_powershell = pytest.mark.skipif(SHELL is None, reason="PowerShell 이 없다")


def run(tmp_path: Path, *args: str) -> tuple[int, list[str]]:
    for script in (ROOT / "deploy").glob("*.ps1"):
        shutil.copy(script, tmp_path)
    (tmp_path / ".env").write_text(
        "EDGEVOICE_VERSION=v1.0.0\nPOSTGRES_PASSWORD=x\n", encoding="utf-8"
    )
    result = subprocess.run(
        [SHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]
        + [str(tmp_path / "update-server.ps1"), "-DryRun", *args],
        capture_output=True,
        timeout=120,
    )
    lines = result.stdout.decode("utf-8", "replace").splitlines()
    # 한국어 안내는 콘솔 코드 페이지에 따라 깨지므로 명령 줄만 본다
    commands = [
        line.strip()
        for line in lines
        if line.startswith(("docker ", "EDGEVOICE_VERSION=", "copy "))
    ]
    return result.returncode, commands


@needs_powershell
def test_pull_then_up_with_new_tag(tmp_path):
    """새 태그로 바꾸고 pull → up -d."""
    code, commands = run(tmp_path, "-Version", "v1.1.0")

    assert code == 0
    assert commands == [
        "EDGEVOICE_VERSION=v1.1.0",
        "docker compose pull",
        "docker compose up -d",
    ]
    # DryRun 은 .env 를 바꾸지 않는다
    assert "v1.0.0" in (tmp_path / ".env").read_text(encoding="utf-8")


@needs_powershell
def test_rolls_back_to_previous_tag_when_unhealthy(tmp_path):
    """healthy 가 되지 않으면 이전 태그로 되돌려 up -d 하고 실패로 끝낸다."""
    code, commands = run(tmp_path, "-Version", "v1.1.0", "-SimulateUnhealthy")

    assert code == 1
    assert commands == [
        "EDGEVOICE_VERSION=v1.1.0",
        "docker compose pull",
        "docker compose up -d",
        "EDGEVOICE_VERSION=v1.0.0",
        "docker compose up -d",
    ]


@needs_powershell
def test_source_dir_copies_server_files_first(tmp_path):
    """-SourceDir 이면 서버 파일을 먼저 새 것으로 바꾼다 (설치 프로그램과 같은 목록)."""
    code, commands = run(tmp_path, "-Version", "v1.1.0", "-SourceDir", str(ROOT))

    assert code == 0
    copied = [c for c in commands if c.startswith("copy ")]
    assert "copy deploy\\docker-compose.yml -> ." in copied
    assert "copy shared -> shared" in copied
    assert commands.index(copied[-1]) < commands.index("docker compose pull")


def test_installer_ships_the_same_server_files():
    """설치 프로그램의 [AI 서버] 파일과 update-server.ps1 의 복사 목록이 같다."""
    iss = (ROOT / "clients" / "dotnet" / "installer" / "EdgeVoice.iss").read_text(
        encoding="utf-8"
    )
    script = (ROOT / "deploy" / "update-server.ps1").read_text(encoding="utf-8-sig")
    for source in (
        r"deploy\docker-compose.yml",
        r"deploy\.env.example",
        r"deploy\*.ps1",
        "shared",
        r"services\llm\edgevoice_guard",
        r"services\backend\static",
        r"config\mcp",
        r"config\postgres\init.sql",
        r"config\searxng\settings.yml",
    ):
        assert source in iss, source
        assert f'"{source}"' in script, source


@needs_powershell
def test_setup_server_fills_random_secrets_once(tmp_path):
    """change-me 비밀 값을 무작위로 채우고, 다시 돌려도 바꾸지 않는다."""
    for script in (ROOT / "deploy").glob("*.ps1"):
        shutil.copy(script, tmp_path)
    shutil.copy(ROOT / "deploy" / ".env.example", tmp_path)

    def setup(*args: str) -> str:
        subprocess.run(
            [SHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]
            + [str(tmp_path / "setup-server.ps1"), "-EnvOnly", *args],
            capture_output=True,
            timeout=120,
            check=True,
        )
        return (tmp_path / ".env").read_text(encoding="utf-8")

    first = setup("-HfToken", "hf_test")
    assert "=change-me" not in first
    assert "HF_TOKEN=hf_test" in first
    assert not first.startswith("\ufeff")
    assert setup() == first

"""배포용 compose(deploy/docker-compose.yml) 확인.

개발용 compose 와 같은 구성인지, 공개해도 안전한지 본다.
"""

import re
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

ROOT = Path(__file__).resolve().parents[2]
DEV = yaml.safe_load((ROOT / "docker-compose.dev.yml").read_text(encoding="utf-8"))
DEPLOY = yaml.safe_load(
    (ROOT / "deploy" / "docker-compose.yml").read_text(encoding="utf-8")
)
RELEASED = {
    "backend",
    "rag",
    "orchestrator",
    "wake-word",
    "audio-gateway",
    "embedding",
    "stt",
    "tts",
}


def env_names(service: dict) -> set[str]:
    return {e.split("=", 1)[0] for e in service.get("environment", [])}


def test_same_services_env_and_volumes_as_dev():
    """서비스·환경변수·볼륨이 개발용과 같다."""
    assert DEPLOY["services"].keys() == DEV["services"].keys()
    assert DEPLOY["volumes"] == DEV["volumes"]
    for name, dev in DEV["services"].items():
        deploy = DEPLOY["services"][name]
        assert env_names(deploy) == env_names(dev), name
        assert deploy.get("volumes") == dev.get("volumes"), name
        assert deploy.get("command") == dev.get("command"), name


def test_uses_release_images_without_build():
    """소스에서 빌드하지 않고 릴리스 이미지를 받는다."""
    for name, service in DEPLOY["services"].items():
        assert "build" not in service, name
        assert "container_name" not in service, name
        if name in RELEASED:
            assert service["image"] == (
                "${EDGEVOICE_REGISTRY:-ghcr.io/ghlee0786}/edgevoice-"
                + name
                + ":${EDGEVOICE_VERSION:-latest}"
            )


def test_image_names_match_release_workflow():
    """릴리스가 올리는 이미지 이름과 같다."""
    release = (ROOT / ".github" / "workflows" / "release.yml").read_text(
        encoding="utf-8"
    )
    matrix = re.search(r"service: \[(.*?)\]", release).group(1)
    assert {s.strip().replace("_", "-") for s in matrix.split(",")} == RELEASED


def test_no_default_password_and_no_db_ports():
    """기본 비밀번호를 쓰지 않고 DB·Redis 포트를 열지 않는다."""
    text = (ROOT / "deploy" / "docker-compose.yml").read_text(encoding="utf-8")
    assert "edgevoice:edgevoice@" not in text
    assert "POSTGRES_PASSWORD=edgevoice" not in text
    assert "change-me" not in text
    assert "ports" not in DEPLOY["services"]["postgres"]
    assert "ports" not in DEPLOY["services"]["redis"]


def test_env_example_leaves_secrets_to_fill():
    """.env 예시는 비밀 값을 change-me 로 비워 둔다."""
    example = (ROOT / "deploy" / ".env.example").read_text(encoding="utf-8")
    for key in ("POSTGRES_PASSWORD", "SEARXNG_SECRET", "SESSION_SECRET"):
        assert re.search(rf"^{key}=change-me$", example, re.M), key

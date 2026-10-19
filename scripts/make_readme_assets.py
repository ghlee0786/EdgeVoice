"""README·설치 마법사 그림을 만든다.

1. 데스크톱 앱 화면을 가짜 백엔드 데이터로 찍는다
   (ReadmeScreenshotTests, 개인 데이터 없음)
   → assets/screenshots/*.png, 파형 창 프레임은 임시 폴더
2. 파형 창 프레임을 묶어 assets/orb.gif (듣기 → 생각 → 말하기)
3. 인포그래픽 SVG 를 Edge(헤드리스, 움직임 줄이기 모드)로 정지 PNG 로
   → assets/infographics/*.png
4. 스크린샷·인포그래픽 PNG 를 설치 마법사 특징 페이지용 BMP 로 → assets/installer/*.bmp

    python scripts/make_readme_assets.py            # 1~3 모두
    python scripts/make_readme_assets.py --no-capture  # 화면은 다시 찍지 않고 3~4 만

필요: dotnet 8 SDK, Pillow, Microsoft Edge.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
SHOTS = ASSETS / "screenshots"
INSTALLER = ASSETS / "installer"
TESTS = ROOT / "clients" / "dotnet" / "tests" / "EdgeVoice.Agent.Desktop.Tests"

EDGE = Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")

# 설치 마법사 특징 페이지 그림: (BMP 이름, 원본 PNG)
FEATURES = [
    ("feature-voice", ASSETS / "infographics" / "voice-flow.png"),
    ("feature-chat", SHOTS / "chat.png"),
    ("feature-control", ASSETS / "infographics" / "computer-control.png"),
    ("feature-knowledge", SHOTS / "knowledge.png"),
    ("feature-dashboard", SHOTS / "dashboard.png"),
    ("feature-settings", SHOTS / "settings-update.png"),
]

# 마법사 그림 칸(WizardSizePercent=120 기준 대략 500×300)
# 24비트 BMP 하나가 0.5MB 를 넘지 않게
BMP_SIZE = (500, 300)


def capture(frames_dir: Path) -> None:
    env = dict(os.environ, EDGEVOICE_SCREENSHOT_DIR=str(SHOTS))
    subprocess.run(
        [
            "dotnet",
            "test",
            str(TESTS),
            "--filter",
            "FullyQualifiedName~ReadmeScreenshotTests",
        ],
        check=True,
        env=env,
    )
    shutil.move(str(SHOTS / "orb-frames"), frames_dir)


def make_gif(frames_dir: Path) -> None:
    frames = []
    for png in sorted(frames_dir.glob("*.png")):
        orb = Image.open(png).convert("RGB")
        # 1.5배로 키우고 어두운 카드 위에 올린다 (창 바깥의 투명 부분은 검게 찍힌다)
        orb = orb.resize((orb.width * 3 // 2, orb.height * 3 // 2), Image.LANCZOS)
        card = Image.new("RGB", (orb.width + 40, orb.height + 40), (17, 19, 24))
        card.paste(orb, (20, 20))
        frames.append(card.quantize(colors=64, method=Image.Quantize.MEDIANCUT))
    frames[0].save(
        ASSETS / "orb.gif",
        save_all=True,
        append_images=frames[1:],
        duration=60,
        loop=0,
        optimize=True,
    )


def render_svgs(tmp: Path) -> None:
    # Edge 는 공백이 든 경로의 file:// 을 못 여는 일이 있어 임시 폴더로 옮겨 찍는다
    for svg in sorted((ASSETS / "infographics").glob("*.svg")):
        width, height = (
            svg.read_text(encoding="utf-8")
            .split('viewBox="0 0 ', 1)[1]
            .split('"', 1)[0]
            .split()
        )
        shutil.copy(svg, tmp / svg.name)
        png = tmp / (svg.stem + ".png")
        subprocess.run(
            [
                str(EDGE),
                "--headless=new",
                "--disable-gpu",
                "--hide-scrollbars",
                "--force-prefers-reduced-motion",
                f"--user-data-dir={tmp / 'edge'}",
                f"--window-size={width},{height}",
                f"--screenshot={png.as_posix()}",
                (tmp / svg.name).as_uri(),
            ],
            check=True,
            capture_output=True,
        )
        shutil.copy(png, svg.with_suffix(".png"))


def make_bmps() -> None:
    INSTALLER.mkdir(parents=True, exist_ok=True)
    for name, source in FEATURES:
        if not source.exists():
            print(f"건너뜀: {source} 이(가) 없습니다", file=sys.stderr)
            continue
        image = Image.open(source).convert("RGB")
        image.thumbnail(BMP_SIZE, Image.LANCZOS)
        canvas = Image.new("RGB", BMP_SIZE, (255, 255, 255))
        canvas.paste(
            image, ((BMP_SIZE[0] - image.width) // 2, (BMP_SIZE[1] - image.height) // 2)
        )
        ImageDraw.Draw(canvas).rectangle(
            [0, 0, BMP_SIZE[0] - 1, BMP_SIZE[1] - 1], outline=(200, 200, 200)
        )
        canvas.save(INSTALLER / f"{name}.bmp")


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--no-capture", action="store_true", help="화면을 다시 찍지 않는다"
    )
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        frames_dir = Path(tmp) / "orb-frames"
        if not args.no_capture:
            capture(frames_dir)
            make_gif(frames_dir)
        render_svgs(Path(tmp))
    make_bmps()


if __name__ == "__main__":
    main()

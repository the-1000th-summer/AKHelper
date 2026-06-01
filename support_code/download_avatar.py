from __future__ import annotations

import json
import urllib.error
import urllib.request
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_FILE = PROJECT_ROOT / "AKHelper" / "AKHelper" / "recruitment.json"
OUTPUT_DIR = PROJECT_ROOT / "data" / "avatar"

BASE_URL = (
    "https://raw.githubusercontent.com/"
    "fexli/ArknightsResource/main/avatar/ASSISTANT"
)


def download_file(url: str, destination: Path) -> None:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "ArknightsRecruitmentApp-ResourceDownloader"},
    )

    with urllib.request.urlopen(request, timeout=20) as response:
        destination.write_bytes(response.read())


def main() -> None:
    if not DATA_FILE.exists():
        raise FileNotFoundError(
            f"没有找到 recruitment.json：{DATA_FILE}"
        )

    data = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    operators = data["operators"]

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    downloaded_count = 0
    skipped_count = 0
    missing_ids: list[str] = []

    for operator_info in operators:
        operator_id = operator_info["id"]
        operator_name = operator_info["name"]

        destination = OUTPUT_DIR / f"{operator_id}.png"

        if destination.exists():
            print(f"跳过：{operator_name}，图片已经存在")
            skipped_count += 1
            continue

        url = f"{BASE_URL}/{operator_id}.png"

        try:
            download_file(url, destination)
            print(f"已下载：{operator_name} -> {destination.name}")
            downloaded_count += 1
        except urllib.error.HTTPError as error:
            print(
                f"未找到：{operator_name} "
                f"({operator_id})，HTTP {error.code}"
            )
            missing_ids.append(operator_id)
        except urllib.error.URLError as error:
            print(f"下载失败：{operator_name}，原因：{error.reason}")
            missing_ids.append(operator_id)

    print()
    print(f"新下载：{downloaded_count}")
    print(f"已存在：{skipped_count}")
    print(f"未找到：{len(missing_ids)}")

    if missing_ids:
        print("以下头像需要人工检查：")
        for operator_id in missing_ids:
            print(f"  - {operator_id}")


if __name__ == "__main__":
    main()

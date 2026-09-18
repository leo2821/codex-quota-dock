import json
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
tables = {}
for language in ("en", "zh-Hans"):
    path = root / "Sources" / "AccountCore" / "Resources" / f"{language}.lproj" / "Localizable.strings"
    result = subprocess.run(
        ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(path)],
        check=True, capture_output=True, text=True,
    )
    tables[language] = json.loads(result.stdout)

assert tables["en"].keys() == tables["zh-Hans"].keys(), "中英文条目需要一致"
for key, value in tables["en"].items():
    assert key == value, f"英文资源需要与原文一致：{key}"
    translated = tables["zh-Hans"][key]
    assert translated.strip(), f"中文翻译为空：{key}"
    assert key.count("%@") == translated.count("%@"), f"格式参数数量不一致：{key}"
print(f"中英文资源检查通过：{len(tables['en'])} 个条目，格式参数数量一致。")

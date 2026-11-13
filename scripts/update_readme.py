#!/usr/bin/env python3
"""更新 README.md 的版本号与「版本记录」表格。

用法:
    python3 scripts/update_readme.py --version V2.12 --date 2026-11-20 [--notes notes/v2.12.md]
    python3 scripts/update_readme.py --version V2.12 --date 2026-11-20 --summary "自定义摘要" [--dry-run]

表格里已存在同版本行时做替换，不会重复插入。
"""
from __future__ import annotations

import argparse
import re
import sys

README = "README.md"
MAX_SUMMARY = 120


def summarize(notes_path: str | None) -> str:
    if not notes_path:
        return "原型内容更新，详见 Release 说明"
    try:
        with open(notes_path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return "原型内容更新，详见 Release 说明"

    for raw in lines:
        line = raw.strip()
        if not line or line.startswith(("#", ">", "|", "```", "**在线预览**")):
            continue
        line = re.sub(r"^[-*+]\s+", "", line)          # 列表符
        line = re.sub(r"^\d+[.、)]\s*", "", line)       # 有序列表
        line = re.sub(r"^\[[ xX]\]\s*", "", line)       # 任务列表
        line = line.replace("|", "/").replace("\n", " ")
        if line:
            return line[:MAX_SUMMARY] + ("…" if len(line) > MAX_SUMMARY else "")
    return "原型内容更新，详见 Release 说明"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True, help="展示用版本号，如 V2.12")
    ap.add_argument("--date", required=True, help="日期 YYYY-MM-DD")
    ap.add_argument("--notes", default="", help="变更说明 markdown 文件")
    ap.add_argument("--summary", default="", help="直接指定表格摘要")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    version = args.version.lstrip("Vv")
    display = f"V{version}"
    try:
        with open(README, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        print(f"读取 {README} 失败: {exc}", file=sys.stderr)
        return 1

    summary = args.summary or summarize(args.notes or None)

    # 1) 顶部版本行
    text, n_head = re.subn(
        r"^> 版本 \*\*V[\d.]+\*\* ｜ [^\n]*$",
        f"> 版本 **{display}** ｜ {args.date} ｜ 需求分析阶段",
        text,
        count=1,
        flags=re.M,
    )

    # 2) 版本记录表格
    header_re = re.compile(r"^\| 版本 \| 日期 \| 主要变更 \|\s*$", re.M)
    m = header_re.search(text)
    row_added = False
    if not m:
        print("警告：README 里没找到「版本记录」表头，跳过表格更新", file=sys.stderr)
    else:
        sep_re = re.compile(r"^\|[\s:|-]+\|\s*$", re.M)
        sep = sep_re.search(text, m.end())
        if not sep:
            print("警告：版本记录表格缺少分隔行，跳过", file=sys.stderr)
        else:
            insert_at = sep.end()
            new_row = f"\n| {display} | {args.date} | {summary} |"
            # 同版本已存在则替换该行
            existing = re.compile(r"^\| " + re.escape(display) + r" \| [^|]* \| [^|]* \|$", re.M)
            if existing.search(text):
                text = existing.sub(f"| {display} | {args.date} | {summary} |", text, count=1)
                row_added = True
            else:
                text = text[:insert_at] + new_row + text[insert_at:]
                row_added = True

    if args.dry_run:
        print(text)
        return 0

    with open(README, "w", encoding="utf-8") as fh:
        fh.write(text)

    print(f"README 已更新：{display} {args.date}（顶部版本行 {n_head} 处，表格行 {'已写入' if row_added else '跳过'}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

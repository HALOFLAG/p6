"""
One-off: rewrite markdown links in all .md files after the 2026-05-16 docs
reorganization that moved 33 files into A__/B__/C__/D__/E__/F__ subdirectories.

Usage:
    python tools/rewrite_doc_links.py [--dry-run]

The MOVE_MAP below encodes every git mv that was performed. The script:
1. For each .md (and CLAUDE.md / CONTEXT.md), find all `[text](url)` links.
2. Resolve url against the file's OLD location.
3. Look up target's NEW location.
4. Compute new relative URL from file's NEW location.
5. Rewrite if changed.

Skips external URLs (http://, https://, mailto:, #fragment, res://).
URL-decodes %20 etc. for matching, re-encodes spaces in output.
"""

import os
import re
import sys
import urllib.parse

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# old_relative_to_repo → new_relative_to_repo
MOVE_MAP = {
    # A__Index_and_meta/
    "docs/文件目錄.md": "docs/A__Index_and_meta/文件目錄.md",
    "docs/文件維護規則.md": "docs/A__Index_and_meta/文件維護規則.md",
    "docs/skills_使用指南.md": "docs/A__Index_and_meta/skills_使用指南.md",
    "docs/參考作品分析.md": "docs/A__Index_and_meta/參考作品分析.md",
    "docs/agents/issue-tracker.md": "docs/A__Index_and_meta/agents/issue-tracker.md",
    "docs/agents/triage-labels.md": "docs/A__Index_and_meta/agents/triage-labels.md",
    "docs/agents/domain.md": "docs/A__Index_and_meta/agents/domain.md",
    "docs/adr/README.md": "docs/A__Index_and_meta/adr/README.md",
    "docs/adr/0001-resource-library-autoload.md": "docs/A__Index_and_meta/adr/0001-resource-library-autoload.md",
    # B__Design_specifications/
    "docs/遊戲設計概念.md": "docs/B__Design_specifications/遊戲設計概念.md",
    "docs/卡牌設計原則.md": "docs/B__Design_specifications/卡牌設計原則.md",
    "docs/敵人設計原則.md": "docs/B__Design_specifications/敵人設計原則.md",
    "docs/UI 設計指引.md": "docs/B__Design_specifications/UI 設計指引.md",
    # C__Implementation_benchmarks/
    "docs/遊戲核心系統機制.md": "docs/C__Implementation_benchmarks/遊戲核心系統機制.md",
    "docs/卡牌資料庫.md": "docs/C__Implementation_benchmarks/卡牌資料庫.md",
    "docs/敵人資料庫.md": "docs/C__Implementation_benchmarks/敵人資料庫.md",
    "docs/第一期開發Scope.md": "docs/C__Implementation_benchmarks/第一期開發Scope.md",
    "docs/戰鬥紀錄系統設計.md": "docs/C__Implementation_benchmarks/戰鬥紀錄系統設計.md",
    "docs/第一期 UI 線框圖.md": "docs/C__Implementation_benchmarks/第一期 UI 線框圖.md",
    "docs/程式規格書.md": "docs/C__Implementation_benchmarks/程式規格書.md",
    "docs/開發里程碑.md": "docs/C__Implementation_benchmarks/開發里程碑.md",
    # D__In_progress/
    "docs/戰役結構與節奏設計.md": "docs/D__In_progress/戰役結構與節奏設計.md",
    # E__Pending_decision/
    "docs/卡包系統設計.md": "docs/E__Pending_decision/卡包系統設計.md",
    "docs/開頭劇情提案.md": "docs/E__Pending_decision/開頭劇情提案.md",
    "docs/雙列戰鬥提案.md": "docs/E__Pending_decision/雙列戰鬥提案.md",
    "docs/敵人主動行為提案.md": "docs/E__Pending_decision/敵人主動行為提案.md",
    "docs/本擊上限討論.md": "docs/E__Pending_decision/本擊上限討論.md",
    # F__History/
    "docs/old_docs/設計概念.md": "docs/F__History/設計概念.md",
    "docs/old_docs/戰鬥階段構思.md": "docs/F__History/戰鬥階段構思.md",
    "docs/old_docs/卡牌構思.md": "docs/F__History/卡牌構思.md",
    "docs/old_docs/卡牌構思UI處理方案.md": "docs/F__History/卡牌構思UI處理方案.md",
    "docs/old_docs/卡牌資料結構.md": "docs/F__History/卡牌資料結構.md",
    "docs/old_docs/卡牌規格.md": "docs/F__History/卡牌規格.md",
    "docs/old_docs/敵人模板.md": "docs/F__History/敵人模板.md",
    "docs/old_docs/視覺線索詞彙表.md": "docs/F__History/視覺線索詞彙表.md",
    "docs/old_docs/失敗代價與精英機制.md": "docs/F__History/失敗代價與精英機制.md",
    "docs/old_docs/結算機制演化討論.md": "docs/F__History/結算機制演化討論.md",
    "docs/old_docs/戰役章節式架構討論.md": "docs/F__History/戰役章節式架構討論.md",
}

# Build inverse: new_path → old_path (for files that were moved)
INV_MAP = {v: k for k, v in MOVE_MAP.items()}

LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")
EXTERNAL_PREFIXES = ("http://", "https://", "mailto:", "res://", "#")


def norm(path: str) -> str:
    """Normalize path to forward slashes, no trailing dot."""
    return os.path.normpath(path).replace("\\", "/")


def link_file_old_location(link_file_rel: str) -> str:
    """Get the OLD location of a file that's currently at link_file_rel."""
    return INV_MAP.get(link_file_rel, link_file_rel)


def resolve_url_to_repo_abs(link_file_old_rel: str, url_path: str) -> str:
    """Given a link file's OLD location and a relative url path, resolve to repo-relative path."""
    link_dir_old = os.path.dirname(link_file_old_rel)
    target = os.path.normpath(os.path.join(link_dir_old, url_path)).replace("\\", "/")
    return target


def repo_abs_to_new(target_old_rel: str) -> str:
    """Look up target's new location (or return unchanged if not moved)."""
    return MOVE_MAP.get(target_old_rel, target_old_rel)


def compute_rel_url(link_file_new_rel: str, target_new_rel: str) -> str:
    """Compute relative URL from link_file (new location) to target (new location)."""
    link_dir_new = os.path.dirname(link_file_new_rel)
    rel = os.path.relpath(target_new_rel, link_dir_new).replace("\\", "/")
    # Encode spaces only; preserve everything else
    rel_encoded = rel.replace(" ", "%20")
    return rel_encoded


def rewrite_link(link_file_rel: str, url: str) -> str:
    """Return rewritten url, or original if no change needed."""
    if url.startswith(EXTERNAL_PREFIXES):
        return url

    # Split fragment
    if "#" in url:
        path_part, fragment = url.split("#", 1)
    else:
        path_part, fragment = url, None

    if not path_part:
        return url  # pure fragment

    # URL decode
    path_decoded = urllib.parse.unquote(path_part)

    # link file's old location
    link_old = link_file_old_location(link_file_rel)
    # target's old absolute (repo-relative)
    target_old = resolve_url_to_repo_abs(link_old, path_decoded)
    # target's new absolute
    target_new = repo_abs_to_new(target_old)
    # new relative
    new_rel = compute_rel_url(link_file_rel, target_new)

    new_url = new_rel + ("#" + fragment if fragment else "")

    if new_url == url:
        return url
    return new_url


def process_file(file_path_abs: str, dry_run: bool = False):
    link_file_rel = norm(os.path.relpath(file_path_abs, REPO_ROOT))

    with open(file_path_abs, "r", encoding="utf-8") as f:
        content = f.read()

    changes = []

    def replace(m):
        text = m.group(1)
        url = m.group(2)
        new_url = rewrite_link(link_file_rel, url)
        if new_url != url:
            changes.append((url, new_url))
            return f"[{text}]({new_url})"
        return m.group(0)

    new_content = LINK_RE.sub(replace, content)

    if changes:
        if not dry_run:
            with open(file_path_abs, "w", encoding="utf-8", newline="\n") as f:
                f.write(new_content)
        return changes
    return []


def main():
    dry_run = "--dry-run" in sys.argv

    targets = []
    # All .md under docs/
    docs_root = os.path.join(REPO_ROOT, "docs")
    for root, _, files in os.walk(docs_root):
        for f in files:
            if f.endswith(".md"):
                targets.append(os.path.join(root, f))
    # Root-level extras
    for extra in ("CLAUDE.md", "CONTEXT.md"):
        p = os.path.join(REPO_ROOT, extra)
        if os.path.exists(p):
            targets.append(p)

    total_files = 0
    total_links = 0
    for t in targets:
        changes = process_file(t, dry_run=dry_run)
        if changes:
            total_files += 1
            total_links += len(changes)
            rel = norm(os.path.relpath(t, REPO_ROOT))
            print(f"\n{rel}:")
            for old, new in changes:
                print(f"  - {old}")
                print(f"    {new}")

    print(
        f"\n{'[DRY RUN] ' if dry_run else ''}"
        f"Changed {total_links} links across {total_files} files."
    )


if __name__ == "__main__":
    main()

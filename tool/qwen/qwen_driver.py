#!/usr/bin/env python3
"""Feed behaviour-neutral analyzer cleanups to a local model (LM Studio or Ollama),
verify every edit with the analyzer and tests, commit on success, revert on failure.

Per file, the driver:
  1. runs `flutter analyze` and keeps only issues on the SAFE list (unreferenced
     private declarations, never-given optional parameters, unused fields,
     underscore-prefixed locals, and three alias-only deprecations);
  2. sends the model the issues plus the relevant source (whole file if small,
     otherwise windows around each issue) and asks for SEARCH/REPLACE blocks;
  3. applies each block only if its SEARCH text occurs exactly once;
  4. re-analyzes: every targeted issue gone, no new issue; bounds the diff size;
     runs every test file that mentions the file;
  5. commits under the repo author on success, reverts on failure, retries once
     with the rejection as feedback.
Nothing is pushed. A Markdown report is written next to this script.

LM Studio: load a model, start the server (Developer tab), set its context
length to 32768 or more in the load settings. Then:
  python qwen_driver.py --worktree C:\\Users\\hunth\\source\\debrify-qwen
Options: --host http://localhost:1234 (LM Studio default; use http://localhost:11434
for Ollama), --model <id> (default: first model the server lists), --dry-run,
--only <lib path> (repeatable).
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import shutil
import sys
import urllib.request

# Flutter: FLUTTER_BIN env var, else whatever is on PATH, else the laptop's install.
FLUTTER = (os.environ.get("FLUTTER_BIN") or shutil.which("flutter")
           or shutil.which("flutter.bat") or r"C:\Users\hunth\flutter\bin\flutter.bat")
AUTHOR = ["-c", "user.name=Ghbarker", "-c", "user.email=granthbarker@gmail.com"]

# Files no refactor lane owns. Keep in sync with the board registration.
TASK_FILES = [
    "lib/theme/app_theme_adapter.dart",
    "lib/services/android_tv_player_bridge.dart",
    "lib/widgets/pikpak_folder_picker_dialog.dart",
    "lib/widgets/adaptive_playlist_section.dart",
    "lib/services/download_service.dart",
]

SAFE_RULES = {
    "unused_element",
    "unused_element_parameter",
    "unused_field",
    "unnecessary_getters_setters",
    "no_leading_underscores_for_local_identifiers",
    "deprecated_member_use",  # alias pairs only, see below
}
# ColorScheme.background / onBackground are dead arguments once nothing in lib
# reads the deprecated getters (the driver checks that before enabling them).
# cacheExtent -> scrollCacheExtent changes the parameter type, so it is NOT an alias.
ALIAS_DEPRECATIONS = ("'background' is deprecated", "'onBackground' is deprecated")
DEPRECATED_GETTER_READS = re.compile(r"(colorScheme|scheme)\.(background|onBackground)\b")

SYSTEM_PROMPT = """You are a careful Dart/Flutter maintenance worker. You remove exactly the
analyzer issues listed from ONE file and change nothing else. Behaviour must
not change. Allowed edits, and only these:
  a. Unreferenced private declaration or getter/setter pair: delete it.
  b. Never-given optional constructor parameter (`this.x = default` that no
     caller passes): delete the parameter from the constructor. Then look at
     the field `x`. If nothing else in the file reads or assigns it, delete the
     field too. If the field IS read or assigned elsewhere, KEEP it and give it
     the parameter's former default as an inline initialiser, for example
     `bool isExpanded = false;` or `List<T> children = const [];`, so that no
     non-nullable field is left without a value.
  c. Unused field (assigned but never read): if its only assignment is
     `_field = <expression>;`, delete the field declaration and replace that
     statement with `<expression>;` so the expression (for example a `.listen(`
     call) still runs exactly as before. If the field is assigned in more than
     one place, answer SKIP.
  d. Deprecated `background:` / `onBackground:` arguments to a ColorScheme
     constructor: delete the whole argument line. Do NOT rename it to `surface`
     or `onSurface`; the constructor already receives those.
  e. Local variable starting with an underscore: rename it to the same name
     without the underscore, updating its uses inside that one function only.
Never: rename or reorder anything else, change any string, add comments,
reformat lines you did not have to touch, change other signatures, touch
imports unless a deleted declaration was their only user.

Answer ONLY with one or more edit blocks in exactly this form:

<<<<<<< SEARCH
(verbatim lines copied from the source, enough to be unique)
=======
(the replacement lines; leave empty to delete)
>>>>>>> REPLACE

Copy SEARCH text character-for-character from the source, including
indentation. Keep each block as small as possible. If an issue cannot be fixed
under these rules, answer with the single word SKIP and one sentence why."""

ISSUE_RE = re.compile(r"^\s*(info|warning|error) - (.*?) - (.+?\.dart):(\d+):(\d+) - (\w+)\s*$")
BLOCK_RE = re.compile(r"<<<<<<< SEARCH\n(.*?)\n=======\n(.*?)>>>>>>> REPLACE", re.S)


def run(cmd, cwd, timeout=1800):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=timeout)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def git(worktree, *args):
    return run(["git", *args], worktree)


def analyze(worktree, rel):
    _, out = run([FLUTTER, "analyze", "--no-pub", rel], worktree)
    issues = []
    for line in out.splitlines():
        m = ISSUE_RE.match(line.replace("\\", "/"))
        if m:
            sev, msg, _path, ln, _col, rule = m.groups()
            issues.append({"sev": sev, "msg": msg, "line": int(ln), "rule": rule})
    return issues


def lib_reads_deprecated_scheme_getters(worktree):
    """True if any lib file reads ColorScheme.background / onBackground, in which
    case deleting the constructor arguments would change what those reads return."""
    for root, _, names in os.walk(os.path.join(worktree, "lib")):
        for n in names:
            if n.endswith(".dart"):
                try:
                    text = open(os.path.join(root, n), encoding="utf-8", errors="replace").read()
                except OSError:
                    continue
                if DEPRECATED_GETTER_READS.search(text):
                    return True
    return False


def is_safe(issue, scheme_getters_read):
    if issue["rule"] not in SAFE_RULES:
        return False
    if issue["rule"] == "deprecated_member_use":
        return issue["msg"].startswith(ALIAS_DEPRECATIONS) and not scheme_getters_read
    return True


def key(issue):
    return (issue["rule"], issue["msg"])


def chat(host, model, messages):
    body = json.dumps({"model": model, "messages": messages, "temperature": 0.0,
                       "max_tokens": 8000, "stream": False}).encode("utf-8")
    req = urllib.request.Request(f"{host}/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json",
                                          "Authorization": "Bearer local"})
    with urllib.request.urlopen(req, timeout=3600) as r:
        data = json.loads(r.read().decode("utf-8"))
    return data["choices"][0]["message"]["content"]


def first_model(host):
    with urllib.request.urlopen(f"{host}/v1/models", timeout=10) as r:
        data = json.loads(r.read().decode("utf-8"))
    ids = [m["id"] for m in data.get("data", [])]
    if not ids:
        raise RuntimeError("the server lists no loaded model")
    return ids[0]


def source_context(text, targets, full_limit=600, radius=200):
    lines = text.split("\n")
    if len(lines) <= full_limit:
        return f"FULL FILE ({len(lines)} lines):\n```dart\n{text}\n```"
    spans = []
    for t in sorted(targets, key=lambda t: t["line"]):
        a, b = max(1, t["line"] - radius), min(len(lines), t["line"] + radius)
        if spans and a <= spans[-1][1] + 1:
            spans[-1][1] = max(spans[-1][1], b)
        else:
            spans.append([a, b])
    parts = [f"FILE EXCERPTS ({len(lines)} lines total; only these windows are shown):"]
    for a, b in spans:
        parts.append(f"// ---- lines {a}-{b} ----\n```dart\n" + "\n".join(lines[a - 1:b]) + "\n```")
    return "\n".join(parts)


def apply_blocks(text, reply):
    blocks = BLOCK_RE.findall(reply)
    if not blocks:
        return None, "reply contained no SEARCH/REPLACE block"
    for search, replace in blocks:
        search = search.rstrip("\n")
        replace = replace.rstrip("\n")
        n = text.count(search)
        if n == 0:
            return None, "SEARCH text not found verbatim:\n" + search[:400]
        if n > 1:
            return None, f"SEARCH text occurs {n} times, not unique:\n" + search[:200]
        text = text.replace(search, replace, 1)
    # collapse a blank line left by a deleted declaration surrounded by blanks
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text, f"{len(blocks)} block(s)"


def related_tests(worktree, rel):
    base = os.path.basename(rel).replace(".dart", "")
    found = []
    for root, _, names in os.walk(os.path.join(worktree, "test")):
        for n in names:
            if n.endswith("_test.dart"):
                p = os.path.join(root, n)
                try:
                    if base in open(p, encoding="utf-8", errors="replace").read():
                        found.append(os.path.relpath(p, worktree).replace("\\", "/"))
                except OSError:
                    pass
    return sorted(found)


GENERATED = ["pubspec.lock", "analysis_options.yaml", "linux", "macos", "windows"]


def revert(worktree, rel):
    git(worktree, "checkout", "--", rel, *GENERATED)


def attempt(worktree, rel, targets, before, host, model, feedback, log):
    path = os.path.join(worktree, rel)
    raw = open(path, "rb").read()
    crlf = b"\r\n" in raw
    original = raw.decode("utf-8").replace("\r\n", "\n")
    issue_text = "\n".join(f"  line {t['line']}: [{t['rule']}] {t['msg']}" for t in targets)
    user = (f"FILE: {rel}\n\nANALYZER ISSUES TO REMOVE (nothing else may change):\n{issue_text}\n"
            + (f"\nYOUR PREVIOUS ANSWER WAS REJECTED BECAUSE:\n{feedback}\nFix that.\n" if feedback else "")
            + "\n" + source_context(original, targets))
    log(f"  -> asking {model} ({len(user)} chars of prompt, {len(targets)} issue(s))")
    reply = chat(host, model, [{"role": "system", "content": SYSTEM_PROMPT},
                               {"role": "user", "content": user}])
    if reply.strip().upper().startswith("SKIP"):
        return False, "model skipped: " + reply.strip()[:300]
    new, info = apply_blocks(original, reply)
    if new is None:
        return False, info
    if new == original:
        return False, "edits produced no change"
    open(path, "wb").write(new.replace("\n", "\r\n" if crlf else "\n").encode("utf-8"))

    after = analyze(worktree, rel)
    after_keys = [key(i) for i in after]
    before_keys = [key(i) for i in before]
    still = [t for t in targets if after_keys.count(key(t)) >= before_keys.count(key(t))]
    new_issues = [i for i in after if key(i) not in before_keys]
    if still:
        return False, "these issues are still reported: " + "; ".join(f"{t['rule']} (was line {t['line']})" for t in still)
    if new_issues:
        return False, "new analyzer issues appeared: " + "; ".join(f"{i['rule']}: {i['msg'][:90]}" for i in new_issues)

    _, all_stat = git(worktree, "diff", "--numstat")
    changed = [l for l in all_stat.splitlines() if l.strip()]
    if len(changed) != 1:
        return False, f"expected exactly one changed file, git sees: {changed}"
    added, deleted = (int(x) for x in changed[0].split()[:2])
    limit = 6 * len(targets) + 12  # a deleted private method can be a few dozen lines
    if added + deleted > limit + 60:
        return False, f"diff too large: +{added}/-{deleted} for {len(targets)} issue(s); you changed more than asked"

    tests = related_tests(worktree, rel)
    if tests:
        _, out = run([FLUTTER, "test", "--no-pub", *tests], worktree)
        if "All tests passed" not in out:
            return False, "tests failed (" + " ".join(tests) + "):\n" + "\n".join(out.splitlines()[-12:])
        log(f"  tests: {len(tests)} file(s) passed")
    else:
        log("  tests: no test file references this file")
    return True, f"{info}, +{added}/-{deleted}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--worktree", required=True)
    ap.add_argument("--host", default="http://localhost:1234")
    ap.add_argument("--model", default=None)
    ap.add_argument("--only", action="append", default=[])
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    wt = os.path.abspath(args.worktree)
    # Report lives OUTSIDE the repository so it never dirties the tree.
    report = os.path.join(os.path.dirname(wt), "qwen_report.md")
    lines = [f"# Local-model cleanup run {dt.datetime.now():%Y-%m-%d %H:%M}", ""]

    def log(s):
        print(s, flush=True)
        lines.append(s)

    _, status = git(wt, "status", "--short", "--untracked-files=no")
    if status.strip():
        log("ABORT: worktree is dirty:\n" + status)
        return 2
    _, head = git(wt, "rev-parse", "--short", "HEAD")
    model = args.model
    if not args.dry_run:
        try:
            model = model or first_model(args.host)
        except Exception as e:
            log(f"ABORT: cannot reach the model server at {args.host}: {e}")
            return 2
    log(f"worktree `{wt}` HEAD {head.strip()} model `{model}` host {args.host}")
    scheme_getters_read = lib_reads_deprecated_scheme_getters(wt)
    if scheme_getters_read:
        log("note: lib reads ColorScheme.background/onBackground; those deprecations are left alone")

    for rel in TASK_FILES:
        if args.only and rel not in args.only:
            continue
        log(f"\n## {rel}")
        before = analyze(wt, rel)
        targets = [i for i in before if is_safe(i, scheme_getters_read)]
        log(f"  analyzer: {len(before)} issue(s), {len(targets)} in scope, {len(before) - len(targets)} left alone")
        for t in targets:
            log(f"    - line {t['line']} [{t['rule']}] {t['msg'][:90]}")
        if not targets or args.dry_run:
            continue
        feedback, ok = None, False
        for n in (1, 2):
            try:
                ok, info = attempt(wt, rel, targets, before, args.host, model, feedback, log)
            except Exception as e:
                ok, info = False, f"driver error: {e}"
            if ok:
                git(wt, "checkout", "--", *GENERATED)
                msg = f"Cleanup: remove {len(targets)} analyzer item(s) in {os.path.basename(rel)}"
                git(wt, *AUTHOR, "commit", "-q", "-m", msg, "--", rel)
                _, h = git(wt, "rev-parse", "--short", "HEAD")
                log(f"  COMMITTED {h.strip()} ({info}) on attempt {n}")
                break
            log(f"  attempt {n} rejected: {info}")
            revert(wt, rel)
            feedback = info
        if not ok:
            log("  gave up on this file; left unchanged")

    _, final = git(wt, "log", "--oneline", f"{head.strip()}..HEAD")
    log("\n## commits\n" + (final.strip() or "(none)"))
    open(report, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print(f"\nreport: {report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

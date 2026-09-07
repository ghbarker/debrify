#!/usr/bin/env python3
"""Feed behaviour-neutral analyzer cleanups to a local model (LM Studio or Ollama),
verify every edit with the analyzer and tests, commit on success, revert on failure.

Per file the driver:
  1. runs `flutter analyze` and keeps only issues on the SAFE list;
  2. records a BASELINE of the related tests on the clean tree, so a test that
     already fails on this machine (goldens rendered elsewhere) never blocks;
  3. works ONE issue per model call. Each accepted edit must remove that issue,
     add no analyzer issue outside the SAFE list, keep the diff small, and add
     no NEW test failure versus the baseline. A follow-on issue that the edit
     exposes (an orphaned private helper) becomes the next target;
  4. a rejected edit is reverted to the last accepted state and retried once
     with the rejection text; progress already accepted is kept;
  5. one commit per file with the list of fixed items, under the repo author.
Nothing is pushed. The report is written in the folder ABOVE the worktree.

Usage:
  python qwen_driver.py --worktree <clone>            (LM Studio on :1234)
  python qwen_driver.py --worktree <clone> --dry-run
  python qwen_driver.py --worktree <clone> --only lib/theme/app_theme_adapter.dart
  --host http://localhost:11434 for Ollama, --model <id> to pick a model.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request

FLUTTER = (os.environ.get("FLUTTER_BIN") or shutil.which("flutter")
           or shutil.which("flutter.bat") or r"C:\Users\hunth\flutter\bin\flutter.bat")
AUTHOR = ["-c", "user.name=Ghbarker", "-c", "user.email=granthbarker@gmail.com"]
GENERATED = ["pubspec.lock", "analysis_options.yaml", "linux", "macos", "windows"]

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
    "unused_import",
    "duplicate_import",
    "unnecessary_import",
    "prefer_final_fields",          # analyzer proves the field is never reassigned
    "deprecated_member_use",        # alias pairs only, see below
}

# Files/directories owned by refactor lanes or frozen by the board. --discover
# skips every file under these prefixes. Keep in sync with the board.
OWNED_PREFIXES = (
    "lib/screens/search_screen.dart", "lib/screens/video_player_screen.dart",
    "lib/screens/magic_tv_screen.dart", "lib/services/storage_service.dart",
    "lib/screens/settings_screen.dart", "lib/main.dart",
    "lib/screens/torbox/", "lib/screens/debrid_downloads_screen.dart",
    "lib/widgets/iptv/iptv_results_view.dart", "lib/widgets/iptv/stage/",
    "lib/screens/merged_series_detail_screen.dart", "lib/screens/merged_detail/",
    "lib/screens/catalog_item_detail_screen.dart", "lib/widgets/detail/",
    "lib/services/remote_control/", "lib/services/torrent_playback",
    "lib/services/video_player_launcher.dart", "lib/services/launcher/",
    "lib/services/profiles/", "lib/screens/video_player/", "lib/services/playback/",
    "lib/services/cloud/", "lib/services/storage/", "lib/screens/search/",
    "lib/screens/debrify_tv/", "lib/services/debrify_tv/", "lib/widgets/cloud/",
    "lib/screens/cloud_files/", "lib/screens/pikpak/", "lib/screens/premiumize/",
    "lib/screens/alldebrid/", "lib/screens/playlist_content_view_screen.dart",
    "lib/widgets/remote/", "lib/widgets/sources/", "lib/services/transfer/",
    "lib/services/home/", "lib/services/tracking/",
)
# ColorScheme.background / onBackground are dead arguments once nothing in lib
# reads the deprecated getters (checked at start). cacheExtent is NOT an alias.
ALIAS_DEPRECATIONS = ("'background' is deprecated", "'onBackground' is deprecated")
DEPRECATED_GETTER_READS = re.compile(r"(colorScheme|scheme)\.(background|onBackground)\b")

SYSTEM_PROMPT = """You are a careful Dart/Flutter maintenance worker. You remove exactly ONE
analyzer issue from ONE file and change nothing else. Behaviour must not
change. Allowed edits, and only these:
  a. Unreferenced private declaration or getter/setter pair: delete it whole,
     including its doc comment and the blank line after it.
  b. Never-given optional constructor parameter (`this.x = default` that no
     caller passes): delete the parameter from the constructor. Then look at
     the field `x`. If nothing else in the file reads or assigns it, delete the
     field too. If the field IS read or assigned elsewhere, KEEP it and give it
     the parameter's former default as an inline initialiser, for example
     `bool isExpanded = false;` or `List<T> children = const [];`.
  c. Unused field (assigned but never read): if its only assignment is
     `_field = <expression>;`, delete the field declaration and replace that
     statement with `<expression>;` so the expression still runs. If it is
     assigned in more than one place, answer SKIP.
  d. Deprecated `background:` / `onBackground:` argument to a ColorScheme
     constructor: delete that whole argument line. Do NOT rename it.
  e. Local variable starting with an underscore: rename it to the same name
     without the underscore, updating its uses inside that one function only.
  f. Unused, duplicate or unnecessary import: delete that import line.
  g. Private field the analyzer says could be final: add `final` to its
     declaration and change nothing else.
Never: rename or reorder anything else, change any string, add comments,
reformat lines you did not have to touch, change other signatures, touch
imports unless a deleted declaration was their only user. Do not fix other
issues you notice; they will be sent separately.

Answer ONLY with one or more edit blocks in exactly this form:

<<<<<<< SEARCH
(lines copied character-for-character from the source shown, enough to be unique)
=======
(the replacement lines; leave empty to delete)
>>>>>>> REPLACE

The SEARCH text must be an exact copy of contiguous lines from the source,
including indentation. Keep blocks as small as possible. If the issue cannot
be fixed under these rules, answer with the single word SKIP and one sentence why."""

ISSUE_RE = re.compile(r"^\s*(info|warning|error) - (.*?) - (.+?\.dart):(\d+):(\d+) - (\w+)\s*$")
BLOCK_RE = re.compile(r"<<<<<<< SEARCH\n(.*?)\n=======\n(.*?)>>>>>>> REPLACE", re.S)
FAIL_RE = re.compile(r"^\d\d:\d\d \+\d+(?: ~\d+)? -\d+: (.*?) \[E\]\s*$")


def run(cmd, cwd, timeout=3600):
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
            sev, msg, _p, ln, _c, rule = m.groups()
            issues.append({"sev": sev, "msg": msg, "line": int(ln), "rule": rule})
    return issues


def lib_reads_deprecated_scheme_getters(worktree):
    for root, _, names in os.walk(os.path.join(worktree, "lib")):
        for n in names:
            if n.endswith(".dart"):
                try:
                    if DEPRECATED_GETTER_READS.search(open(os.path.join(root, n), encoding="utf-8", errors="replace").read()):
                        return True
                except OSError:
                    pass
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
                       "max_tokens": 6000, "stream": False}).encode("utf-8")
    req = urllib.request.Request(f"{host}/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json",
                                          "Authorization": "Bearer local"})
    with urllib.request.urlopen(req, timeout=3600) as r:
        return json.loads(r.read().decode("utf-8"))["choices"][0]["message"]["content"]


def first_model(host):
    with urllib.request.urlopen(f"{host}/v1/models", timeout=10) as r:
        ids = [m["id"] for m in json.loads(r.read().decode("utf-8")).get("data", [])]
    if not ids:
        raise RuntimeError("the server lists no loaded model")
    return ids[0]


def source_context(text, issue, full_limit=600, radius=220):
    lines = text.split("\n")
    if len(lines) <= full_limit:
        return f"FULL FILE ({len(lines)} lines):\n```dart\n{text}\n```"
    a, b = max(1, issue["line"] - radius), min(len(lines), issue["line"] + radius)
    return (f"FILE EXCERPT (lines {a}-{b} of {len(lines)}; the issue is at line {issue['line']}):\n"
            f"```dart\n" + "\n".join(lines[a - 1:b]) + "\n```")


def find_once(text, search):
    """Exact match first; then a match that ignores trailing whitespace per line."""
    n = text.count(search)
    if n == 1:
        return search
    if n > 1:
        return None
    pattern = r"\n".join(re.escape(l.rstrip()) + r"[ \t]*" for l in search.split("\n"))
    hits = list(re.finditer(pattern, text))
    return hits[0].group(0) if len(hits) == 1 else None


def apply_blocks(text, reply):
    blocks = BLOCK_RE.findall(reply)
    if not blocks:
        return None, "the reply contained no SEARCH/REPLACE block"
    for search, replace in blocks:
        search = search.rstrip("\n")
        replace = replace.rstrip("\n")
        found = find_once(text, search)
        if found is None:
            n = text.count(search)
            why = "occurs more than once" if n > 1 else "is not a verbatim copy of the source"
            return None, f"a SEARCH block {why}; copy the lines exactly as shown:\n{search[:400]}"
        text = text.replace(found, replace, 1)
    return re.sub(r"\n{3,}", "\n\n", text), f"{len(blocks)} block(s)"


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


def failing_tests(worktree, tests):
    """Names of failing tests in these files on the current tree."""
    if not tests:
        return set()
    _, out = run([FLUTTER, "test", "--no-pub", "--reporter", "expanded", *tests], worktree)
    fails = set()
    for line in out.splitlines():
        m = FAIL_RE.match(line.replace("\\", "/"))
        if m:
            fails.add(m.group(1))
    return fails


def write_text(path, text, crlf):
    open(path, "wb").write(text.replace("\n", "\r\n" if crlf else "\n").encode("utf-8"))


def read_text(path):
    raw = open(path, "rb").read()
    return raw.decode("utf-8").replace("\r\n", "\n"), b"\r\n" in raw


def deterministic_fix(text, issue):
    """Mechanical edits the driver performs itself; returns (new_text, description) or None.
    Only unambiguous, single-site patterns; anything else goes to the model."""
    lines = text.split("\n")
    idx = issue["line"] - 1
    if idx < 0 or idx >= len(lines):
        return None
    line = lines[idx]
    rule = issue["rule"]

    if rule in ("unused_import", "duplicate_import", "unnecessary_import") and line.strip().startswith("import "):
        del lines[idx]
        return "\n".join(lines), "deleted the import line"

    if rule == "unused_element_parameter":
        # `this.x = default,` inside a constructor, never passed by any caller.
        m = re.match(r"^(\s*)this\.(\w+)\s*=\s*(.+?),\s*$", line)
        if m:
            name, default = m.group(2), m.group(3)
            del lines[idx]
            body = "\n".join(lines)
            # Field declaration: `Type name;` (mutable) or `final Type name;`
            decl = re.compile(r"^(\s*)((?:final\s+)?[\w<>?, ]+?)\s+" + re.escape(name) + r";[ \t]*$", re.M)
            hits = list(decl.finditer(body))
            if len(hits) != 1:
                return None
            other_uses = len(re.findall(r"\b" + re.escape(name) + r"\b", body)) - 1  # minus the declaration
            h = hits[0]
            if other_uses == 0:
                end = h.end() + 1 if body[h.end():h.end() + 1] == "\n" else h.end()
                return body[:h.start()] + body[end:], f"removed parameter `{name}` and its unused field"
            body = body[:h.start()] + f"{h.group(1)}{h.group(2)} {name} = {default};" + body[h.end():]
            return body, f"removed parameter `{name}`; field keeps its default `{default}` as an initialiser"
        return None

    if rule == "prefer_final_fields":
        m = re.match(r"^(\s*)(static\s+)?(?!final\b)([\w<>?, ]+?\s+_\w+\s*(?:=.*)?;)\s*$", line)
        if m:
            lines[idx] = f"{m.group(1)}{m.group(2) or ''}final {m.group(3)}"
            return "\n".join(lines), "added `final`"
        return None

    if rule == "deprecated_member_use" and re.match(r"^\s*(background|onBackground):\s*.+,\s*(//.*)?$", line):
        del lines[idx]
        return "\n".join(lines), "deleted the deprecated ColorScheme argument line"

    return None


def fix_one(worktree, rel, issue, before_keys, scheme_read, tests, baseline_fails, host, model, feedback, log):
    """Fix this one issue (deterministically if possible, else via the model), verify,
    return (ok, info, exposed_issues)."""
    path = os.path.join(worktree, rel)
    current, crlf = read_text(path)
    det = deterministic_fix(current, issue) if feedback is None else None
    if det is not None:
        new, info = det
        log(f"    -> driver applied a deterministic edit: {info}")
    else:
        user = (f"FILE: {rel}\n\nTHE ONE ISSUE TO REMOVE:\n  line {issue['line']}: [{issue['rule']}] {issue['msg']}\n"
                + (f"\nYOUR PREVIOUS ANSWER WAS REJECTED BECAUSE:\n{feedback}\nFix that; the source below is the current file.\n" if feedback else "")
                + "\n" + source_context(current, issue))
        log(f"    -> asking {model} for line {issue['line']} [{issue['rule']}]")
        reply = chat(host, model, [{"role": "system", "content": SYSTEM_PROMPT},
                                   {"role": "user", "content": user}])
        if reply.strip().upper().startswith("SKIP"):
            return False, "model skipped: " + reply.strip()[:200], []
        new, info = apply_blocks(current, reply)
        if new is None:
            log("    model reply (rejected):\n" + "\n".join("      | " + l for l in reply.strip().splitlines()[:40]))
            return False, info, []
        if new == current:
            return False, "the edit produced no change", []
        log("    model reply:\n" + "\n".join("      | " + l for l in reply.strip().splitlines()[:40]))
    write_text(path, new, crlf)

    after = analyze(worktree, rel)
    after_keys = [key(i) for i in after]
    if after_keys.count(key(issue)) >= before_keys.count(key(issue)):
        return False, f"the issue at line {issue['line']} is still reported", []
    exposed, bad = [], []
    for i in after:
        if key(i) not in before_keys:
            (exposed if is_safe(i, scheme_read) else bad).append(i)
    if bad:
        return False, "new analyzer issue(s): " + "; ".join(f"{i['rule']} at line {i['line']}: {i['msg'][:80]}" for i in bad), []

    _, stat = git(worktree, "diff", "--numstat")
    changed = [l for l in stat.splitlines() if l.strip()]
    if len(changed) != 1:
        return False, f"more than one file changed: {changed}", []
    added, deleted = (int(x) for x in changed[0].split()[:2])
    if added + deleted > 120:
        return False, f"the diff is far too large (+{added}/-{deleted}) for one issue; you changed things you were not asked to", []

    if tests:
        new_fails = failing_tests(worktree, tests) - baseline_fails
        if new_fails:
            return False, "tests newly failing: " + "; ".join(sorted(new_fails))[:600], []
    return True, f"{info}, cumulative +{added}/-{deleted}", exposed


def discover(worktree, scheme_read, log):
    """All unowned lib files that carry at least one in-scope issue."""
    log("discovering targets with a whole-lib analyze (takes a couple of minutes)...")
    _, out = run([FLUTTER, "analyze", "--no-pub", "lib"], worktree)
    per_file = {}
    for line in out.splitlines():
        m = ISSUE_RE.match(line.replace("\\", "/"))
        if not m:
            continue
        sev, msg, path, ln, _c, rule = m.groups()
        path = path.replace("\\", "/")
        if not path.startswith("lib/") or path.startswith(OWNED_PREFIXES):
            continue
        if is_safe({"sev": sev, "msg": msg, "line": int(ln), "rule": rule}, scheme_read):
            per_file[path] = per_file.get(path, 0) + 1
    files = sorted(per_file, key=lambda p: -per_file[p])
    log(f"  {len(files)} unowned file(s) with {sum(per_file.values())} in-scope item(s)")
    return files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--worktree", required=True)
    ap.add_argument("--discover", action="store_true",
                    help="analyze all of lib and work every unowned file with in-scope issues")
    ap.add_argument("--host", default="http://localhost:1234")
    ap.add_argument("--model", default=None)
    ap.add_argument("--only", action="append", default=[])
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    wt = os.path.abspath(args.worktree)
    report = os.path.join(os.path.dirname(wt), "qwen_report.md")
    lines = [f"# Local-model cleanup run {dt.datetime.now():%Y-%m-%d %H:%M}", ""]

    def log(s):
        print(s, flush=True)
        lines.append(s)

    _, status = git(wt, "status", "--short", "--untracked-files=no")
    if status.strip():
        log("ABORT: worktree has uncommitted tracked changes:\n" + status)
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
    scheme_read = lib_reads_deprecated_scheme_getters(wt)
    if scheme_read:
        log("note: lib reads ColorScheme.background/onBackground; those deprecations are left alone")
    task_files = discover(wt, scheme_read, log) if args.discover else TASK_FILES

    for rel in task_files:
        if args.only and rel not in args.only:
            continue
        log(f"\n## {rel}")
        before = analyze(wt, rel)
        queue = [i for i in before if is_safe(i, scheme_read)]
        log(f"  analyzer: {len(before)} issue(s), {len(queue)} in scope")
        for t in queue:
            log(f"    - line {t['line']} [{t['rule']}] {t['msg'][:90]}")
        if not queue or args.dry_run:
            continue
        tests = related_tests(wt, rel)
        baseline = failing_tests(wt, tests) if tests else set()
        log(f"  tests: {len(tests)} related file(s); {len(baseline)} already failing on the clean tree" + (": " + "; ".join(sorted(baseline))[:300] if baseline else ""))

        fixed, given_up = [], []
        while queue:
            # Re-read the analyzer each round: line numbers shift after every accepted edit.
            current_issues = analyze(wt, rel)
            current_keys = [key(i) for i in current_issues]
            wanted = queue.pop(0)
            live = next((i for i in current_issues if key(i) == key(wanted)), None)
            if live is None:
                log(f"  already gone: [{wanted['rule']}] {wanted['msg'][:60]}")
                continue
            path = os.path.join(wt, rel)
            snapshot, crlf = read_text(path)  # last ACCEPTED state
            feedback, ok = None, False
            for n in (1, 2):
                try:
                    ok, info, exposed = fix_one(wt, rel, live, current_keys, scheme_read, tests, baseline, args.host, model, feedback, log)
                except Exception as e:
                    ok, info, exposed = False, f"driver error: {e}", []
                if ok:
                    fixed.append(f"line {live['line']} [{live['rule']}] {live['msg'][:70]}")
                    log(f"    accepted ({info})")
                    for x in exposed:
                        log(f"    follow-on target exposed: line {x['line']} [{x['rule']}] {x['msg'][:70]}")
                        queue.append(x)
                    break
                log(f"    attempt {n} rejected: {info}")
                write_text(path, snapshot, crlf)  # back to last accepted state, not the original
                git(wt, "checkout", "--", *GENERATED)
                feedback = info
            if not ok:
                given_up.append(f"line {live['line']} [{live['rule']}] {live['msg'][:70]}")
        git(wt, "checkout", "--", *GENERATED)
        if fixed:
            body = "Cleanup: " + os.path.basename(rel) + "\n\nRemoved analyzer items:\n" + "\n".join("- " + f for f in fixed)
            if given_up:
                body += "\n\nLeft in place (model could not fix under the rules):\n" + "\n".join("- " + g for g in given_up)
            git(wt, *AUTHOR, "commit", "-q", "-m", body, "--", rel)
            _, h = git(wt, "rev-parse", "--short", "HEAD")
            log(f"  COMMITTED {h.strip()}: {len(fixed)} fixed, {len(given_up)} left")
        else:
            git(wt, "checkout", "--", rel)
            log(f"  no accepted edits; file left unchanged ({len(given_up)} given up)")

    _, final = git(wt, "log", "--oneline", f"{head.strip()}..HEAD")
    log("\n## commits\n" + (final.strip() or "(none)"))
    open(report, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print(f"\nreport: {report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

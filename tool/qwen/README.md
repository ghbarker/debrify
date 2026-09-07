# Local-model analyzer cleanup (lane QA)

Feeds behaviour-neutral analyzer cleanups to a local model served by LM Studio
(or Ollama), verifies every edit with the analyzer and the related tests, and
commits on success. Nothing is pushed by the driver.

## One-time setup on a machine

1. Install Git, Python 3, and Flutter (3.44.8 to match CI, or newer). Put
   `flutter` on PATH (or set `FLUTTER_BIN` to the full path of `flutter.bat`).
   Turn on Windows Developer Mode (Flutter needs it for `pub get`).
2. Clone the working branch:

       git clone -b refactor/qa-analyzer-cleanup https://github.com/ghbarker/debrify.git debrify-qwen
       cd debrify-qwen
       flutter pub get
       git checkout -- pubspec.lock analysis_options.yaml linux macos windows

3. In LM Studio: load a Qwen coder model, set its context length to 32768,
   start the server (Developer tab).

## Run

    tool\qwen\run_qwen.cmd

Options pass through: `--discover` (analyze all of lib and work every unowned file with in-scope issues, not just the five listed), `--dry-run` (list targets, no model call),
`--only lib/theme/app_theme_adapter.dart`, `--host http://localhost:11434`
(Ollama), `--model <id>`.

The report lands in `qwen_report.md` in the folder ABOVE the clone (outside the repository, so it never dirties the tree). Commits are made on the
current branch under the repository author; push them yourself when you have
reviewed `git log -p`.

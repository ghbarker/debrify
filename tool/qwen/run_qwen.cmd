@echo off
rem Local-model analyzer cleanup. Run from a normal terminal or double-click.
rem Requires: git, Flutter on PATH, Python 3, and LM Studio serving a model
rem on http://localhost:1234 (or pass --host http://<ip>:1234).
setlocal
set HERE=%~dp0
set REPO=%HERE%..\..
where py >nul 2>nul && (set PY=py -3) || (set PY=python)
%PY% "%HERE%qwen_driver.py" --worktree "%REPO%" %*
echo.
echo Report: %HERE%qwen_report.md
pause

#!/usr/bin/env bash
# Idempotent Qwen Code CLI install for Cloud Agent VMs.
# Does not write API keys. Auth is environment secrets:
#   BAILIAN_CODING_PLAN_API_KEY (Coding Plan, sk-sp-...)
#   DASHSCOPE_API_KEY (standard ModelStudio)
set -euo pipefail

PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.local}"
mkdir -p "$PREFIX"
export NPM_CONFIG_PREFIX="$PREFIX"
npm install -g @qwen-code/qwen-code@latest

if [[ -x "$PREFIX/bin/qwen" ]]; then
  if sudo -n ln -sfn "$PREFIX/bin/qwen" /usr/local/bin/qwen 2>/dev/null; then
    :
  elif ln -sfn "$PREFIX/bin/qwen" /usr/local/bin/qwen 2>/dev/null; then
    :
  fi
  if ! grep -qF '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  fi
fi

mkdir -p "$HOME/.qwen"
SETTINGS="$HOME/.qwen/settings.json"
if [[ ! -f "$SETTINGS" ]]; then
  cat > "$SETTINGS" <<'JSON'
{
  "modelProviders": {
    "openai": [
      {
        "id": "qwen3-coder-plus",
        "name": "qwen3-coder-plus (Coding Plan intl)",
        "baseUrl": "https://coding-intl.dashscope.aliyuncs.com/v1",
        "envKey": "BAILIAN_CODING_PLAN_API_KEY"
      },
      {
        "id": "qwen3-coder-plus-dashscope",
        "name": "qwen3-coder-plus (Dashscope intl)",
        "baseUrl": "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
        "envKey": "DASHSCOPE_API_KEY"
      }
    ]
  },
  "security": {
    "auth": {
      "selectedType": "openai"
    }
  },
  "model": {
    "name": "qwen3-coder-plus"
  }
}
JSON
fi

command -v qwen >/dev/null || export PATH="$PREFIX/bin:$PATH"
qwen --version

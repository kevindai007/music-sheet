#!/usr/bin/env bash
# One-time setup on a Mac: bakes the backend's App Token into the app and generates the Xcode project.
# Usage: ./setup.sh            (reads APP_TOKEN from the server over ssh)
#        ./setup.sh <token>    (uses the token you pass)
set -euo pipefail
cd "$(dirname "$0")"

SERVER="${MUSIC_SHEET_SERVER:-ubuntu@141.145.149.119}"

if ! command -v xcodegen >/dev/null; then
  echo "安装 XcodeGen…"
  brew install xcodegen
fi

token="${1:-}"
if [ -z "$token" ] && [ ! -f Secrets.xcconfig ]; then
  echo "从服务器 $SERVER 读取 APP_TOKEN…"
  token=$(ssh -o ConnectTimeout=10 "$SERVER" "sed -n 's/^APP_TOKEN=//p' ~/music-sheet-api.env" || true)
  if [ -z "$token" ]; then
    read -r -s -p "没读到，请粘贴 APP_TOKEN（和服务器上的一致）: " token
    echo
  fi
fi

if [ -n "$token" ]; then
  # xcconfig treats "//" as a comment and "$" as a variable, so only allow plain token characters.
  if [[ ! "$token" =~ ^[A-Za-z0-9._~+=-]+$ ]]; then
    echo "APP_TOKEN 里有 xcconfig 不支持的字符（如 / 或 \$），请在服务器上换一个只含字母数字的 token。" >&2
    exit 1
  fi
  umask 077
  printf 'MUSIC_SHEET_APP_TOKEN = %s\n' "$token" > Secrets.xcconfig
  echo "已写入 Secrets.xcconfig（不会提交到 git）。"
fi

xcodegen
open MusicSheet.xcodeproj

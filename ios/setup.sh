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

# xcodegen regenerates the project and drops the Team picked in Xcode, so remember it in Local.xcconfig.
if ! grep -qs '^DEVELOPMENT_TEAM' Local.xcconfig; then
  # The team id is the OU of the "Apple Development" certificate Xcode created for your Apple ID.
  team=$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1 || true)
  if [ -n "$team" ]; then
    printf 'DEVELOPMENT_TEAM = %s\n' "$team" >> Local.xcconfig
    echo "已记住签名 Team：$team（Local.xcconfig，不会提交到 git）。"
  else
    echo "没找到开发证书：在 Xcode 里选中 MusicSheet target → Signing & Capabilities → Team 选你的 Apple ID，运行一次后再执行 ./setup.sh，以后就不用再选了。"
  fi
fi

xcodegen
open MusicSheet.xcodeproj

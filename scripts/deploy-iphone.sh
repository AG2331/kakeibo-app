#!/usr/bin/env bash
#
# 実機の iPhone へビルドして転送する。
#
#   scripts/deploy-iphone.sh                  1回だけビルドして転送
#   scripts/deploy-iphone.sh --watch          ソースの変更を検知して毎回転送
#   scripts/deploy-iphone.sh --interval 30    30分ごとに転送
#
# 主なオプション:
#   --device <名前かID>   対象デバイス（既定: 接続中の最初のiPhone）
#   --config <Debug|Release>
#   --team <TEAM_ID>      署名チーム（既定: プロビジョニングプロファイルから自動検出）
#   --no-launch           インストールのみ（アプリを起動しない）
#   --list-devices        接続中のデバイスを一覧表示して終了
#
# 備考:
#   - project.yml を更新していれば xcodegen で .xcodeproj を作り直してからビルドする
#     （新しいファイルを追加したのにビルドに含まれない、という事故を防ぐため）
#   - --watch / --interval は前面で動き続ける。Ctrl+C で止める
#   - launchd に登録して常駐させたい場合は末尾の「常駐させる場合」を参照

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT="Kakeibo.xcodeproj"
readonly SCHEME="Kakeibo"
readonly DERIVED_DATA="$REPO_ROOT/.build/device"
readonly LOG_DIR="$REPO_ROOT/.build/logs"
readonly LOCK_DIR="$REPO_ROOT/.build/deploy.lock"

CONFIG="Debug"
DEVICE_WANTED=""
TEAM_ID="${KAKEIBO_TEAM_ID:-}"
LAUNCH_APP=1
MODE="once"
INTERVAL_MIN=0

# --- ログ ------------------------------------------------------------------

log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
fail() { printf '[%s] エラー: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }

# --- 引数 ------------------------------------------------------------------

usage() {
  awk 'NR==1 && /^#!/ { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch)         MODE="watch"; shift ;;
    --interval)      MODE="interval"; INTERVAL_MIN="${2:?--interval には分数が必要です}"; shift 2 ;;
    --once)          MODE="once"; shift ;;
    --device)        DEVICE_WANTED="${2:?--device にはデバイス名かIDが必要です}"; shift 2 ;;
    --config)        CONFIG="${2:?--config には Debug か Release が必要です}"; shift 2 ;;
    --team)          TEAM_ID="${2:?--team には Team ID が必要です}"; shift 2 ;;
    --no-launch)     LAUNCH_APP=0; shift ;;
    --list-devices)  MODE="list"; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               fail "不明なオプション: $1"; usage; exit 2 ;;
  esac
done

# --- デバイスの解決 ---------------------------------------------------------

# 接続中の iPhone を探す。$1 に名前かIDを指定するとそれを優先する。
# 「UDID<TAB>名前」を返す。xcodebuild の -destination は UDID を要求し、
# devicectl は UDID も受け付けるので、UDID に統一する。
resolve_device() {
  local wanted="${1:-}" json
  json="$(mktemp)"
  trap 'rm -f "$json"' RETURN

  if ! xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1; then
    fail "デバイス一覧を取得できませんでした。Xcode がインストールされているか確認してください。"
    return 1
  fi

  python3 - "$json" "$wanted" <<'PY'
import json, sys
path, wanted = sys.argv[1], sys.argv[2]
devices = json.load(open(path))["result"]["devices"]

def usable(d):
    hw = d.get("hardwareProperties", {})
    conn = d.get("connectionProperties", {})
    return (hw.get("platform") == "iOS"
            and hw.get("deviceType") == "iPhone"
            and conn.get("tunnelState") == "connected")

candidates = [d for d in devices if usable(d)]
if wanted:
    candidates = [d for d in candidates
                  if wanted in (d.get("identifier", ""),
                                d.get("hardwareProperties", {}).get("udid", ""),
                                d.get("deviceProperties", {}).get("name", ""))]
if not candidates:
    sys.exit(1)

d = candidates[0]
print(f'{d["hardwareProperties"]["udid"]}\t{d["deviceProperties"]["name"]}')
PY
}

list_devices() {
  local json
  json="$(mktemp)"
  xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || true
  python3 - "$json" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
if not devices:
    print("（デバイスが見つかりません）")
for d in devices:
    hw, conn, prop = d["hardwareProperties"], d["connectionProperties"], d["deviceProperties"]
    print(f'{prop.get("name")}  [{hw.get("deviceType")}/{hw.get("platform")} '
          f'{prop.get("osVersionNumber")}]  {conn.get("tunnelState")}  {hw.get("udid")}')
PY
  rm -f "$json"
}

# --- 署名チームの自動検出 ---------------------------------------------------

detect_team_id() {
  local profile
  profile="$(find "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
                  "$HOME/Library/MobileDevice/Provisioning Profiles" \
                  -name '*.mobileprovision' 2>/dev/null | head -1)"
  [[ -n "$profile" ]] || return 1
  security cms -D -i "$profile" 2>/dev/null | plutil -extract TeamIdentifier.0 raw - 2>/dev/null
}

# --- ビルドと転送 -----------------------------------------------------------

# project.yml のほうが新しければ .xcodeproj を作り直す
regenerate_project_if_needed() {
  local pbxproj="$REPO_ROOT/$PROJECT/project.pbxproj"
  [[ -f "$REPO_ROOT/project.yml" ]] || return 0
  if [[ ! -f "$pbxproj" || "$REPO_ROOT/project.yml" -nt "$pbxproj" ]]; then
    if command -v xcodegen >/dev/null 2>&1; then
      log "project.yml が更新されているので xcodegen で作り直します"
      (cd "$REPO_ROOT" && xcodegen generate >/dev/null)
    else
      fail "project.yml が更新されていますが xcodegen がありません（brew install xcodegen）"
    fi
  fi
}

build_and_deploy() {
  local device_id="$1" device_name="$2"
  local log_file="$LOG_DIR/build-$(date '+%Y%m%d-%H%M%S').log"
  mkdir -p "$LOG_DIR"

  regenerate_project_if_needed

  log "ビルド中（$CONFIG / $device_name）…"
  if ! (cd "$REPO_ROOT" && xcodebuild build \
          -project "$PROJECT" \
          -scheme "$SCHEME" \
          -configuration "$CONFIG" \
          -destination "id=$device_id" \
          -derivedDataPath "$DERIVED_DATA" \
          DEVELOPMENT_TEAM="$TEAM_ID" \
          -allowProvisioningUpdates \
          >"$log_file" 2>&1); then
    fail "ビルドに失敗しました。詳細: $log_file"
    grep -E "error:|Signing for|requires a provisioning profile" "$log_file" | head -5 >&2 || true
    return 1
  fi

  local app_path="$DERIVED_DATA/Build/Products/$CONFIG-iphoneos/$SCHEME.app"
  if [[ ! -d "$app_path" ]]; then
    fail "ビルド成果物が見つかりません: $app_path"
    return 1
  fi

  log "転送中…"
  if ! xcrun devicectl device install app --device "$device_id" "$app_path" \
        >>"$log_file" 2>&1; then
    fail "転送に失敗しました。iPhone のロックを解除して、画面を点けたままお試しください。詳細: $log_file"
    return 1
  fi

  if (( LAUNCH_APP )); then
    local bundle_id
    bundle_id="$(plutil -extract CFBundleIdentifier raw "$app_path/Info.plist" 2>/dev/null || echo "")"
    if [[ -n "$bundle_id" ]]; then
      log "起動中（$bundle_id）…"
      xcrun devicectl device process launch --device "$device_id" "$bundle_id" \
        >>"$log_file" 2>&1 || fail "起動に失敗しました（インストールは完了しています）"
    fi
  fi

  log "完了しました（$device_name）"
}

# --- 変更の検知 -------------------------------------------------------------

# 監視対象（ソースとプロジェクト定義）のタイムスタンプをまとめた指紋を返す
source_fingerprint() {
  find "$REPO_ROOT/Sources" "$REPO_ROOT/project.yml" -type f \
       \( -name '*.swift' -o -name '*.yml' \) -exec stat -f '%m %N' {} + 2>/dev/null |
    sort | shasum | cut -d' ' -f1
}

# --- 実行 -------------------------------------------------------------------

if [[ "$MODE" == "list" ]]; then
  list_devices
  exit 0
fi

# 多重起動を防ぐ（launchd で定期実行させたときに前回の処理と重ならないように）。
# macOS には flock が無いため、mkdir の原子性を使う。
mkdir -p "$(dirname "$LOCK_DIR")"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  owner="$(cat "$LOCK_DIR/pid" 2>/dev/null || echo '')"
  if [[ -n "$owner" ]] && kill -0 "$owner" 2>/dev/null; then
    fail "すでに実行中です（PID $owner）。先に終了させてください。"
    exit 1
  fi
  log "前回の残骸を片付けます"
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" || { fail "ロックを取得できませんでした"; exit 1; }
fi
echo $$ >"$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT

if [[ -z "$TEAM_ID" ]]; then
  TEAM_ID="$(detect_team_id || true)"
  [[ -n "$TEAM_ID" ]] && log "署名チームを自動検出しました: $TEAM_ID"
fi
if [[ -z "$TEAM_ID" ]]; then
  fail "署名チーム（Team ID）が分かりません。--team か環境変数 KAKEIBO_TEAM_ID で指定してください。"
  fail "Xcode で一度この端末向けにビルドしておくと自動検出できるようになります。"
  exit 1
fi

device_info="$(resolve_device "$DEVICE_WANTED" || true)"
if [[ -z "$device_info" ]]; then
  fail "接続中の iPhone が見つかりません。USB接続か同じWi-Fi上にあるか、ロックが解除されているか確認してください。"
  echo "--- 認識しているデバイス ---" >&2
  list_devices >&2
  exit 1
fi
DEVICE_ID="${device_info%%$'\t'*}"
DEVICE_NAME="${device_info#*$'\t'}"

case "$MODE" in
  once)
    build_and_deploy "$DEVICE_ID" "$DEVICE_NAME"
    ;;

  watch)
    log "監視を開始します（Ctrl+C で終了）: $REPO_ROOT/Sources"
    build_and_deploy "$DEVICE_ID" "$DEVICE_NAME" || true
    last="$(source_fingerprint)"
    while true; do
      sleep 3
      current="$(source_fingerprint)"
      if [[ "$current" != "$last" ]]; then
        last="$current"
        log "変更を検知しました"
        # 保存が連続したときにまとめて拾えるよう少し待つ
        sleep 1
        last="$(source_fingerprint)"
        build_and_deploy "$DEVICE_ID" "$DEVICE_NAME" || true
      fi
    done
    ;;

  interval)
    log "${INTERVAL_MIN}分ごとにビルドします（Ctrl+C で終了）"
    while true; do
      build_and_deploy "$DEVICE_ID" "$DEVICE_NAME" || true
      sleep $(( INTERVAL_MIN * 60 ))
      # 実行中に別の端末へ差し替えられていることもあるので取り直す
      if info="$(resolve_device "$DEVICE_WANTED" || true)"; [[ -n "$info" ]]; then
        DEVICE_ID="${info%%$'\t'*}"
        DEVICE_NAME="${info#*$'\t'}"
      else
        fail "iPhone が見つからないため、この回は見送ります"
      fi
    done
    ;;
esac

# 常駐させる場合（ログイン中に自動で回す）:
#   1) 次の内容を ~/Library/LaunchAgents/com.util.kakeibo.deploy.plist に保存する
#      （StartInterval は秒。下の例は1時間ごと）
#
#   <?xml version="1.0" encoding="UTF-8"?>
#   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
#     "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
#   <plist version="1.0"><dict>
#     <key>Label</key>              <string>com.util.kakeibo.deploy</string>
#     <key>ProgramArguments</key>
#       <array>
#         <string>/bin/bash</string>
#         <string>-lc</string>
#         <string>"<このリポジトリのパス>/scripts/deploy-iphone.sh" --once</string>
#       </array>
#     <key>StartInterval</key>      <integer>3600</integer>
#     <key>StandardOutPath</key>    <string>/tmp/kakeibo-deploy.log</string>
#     <key>StandardErrorPath</key>  <string>/tmp/kakeibo-deploy.log</string>
#   </dict></plist>
#
#   2) launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.util.kakeibo.deploy.plist
#   3) 解除するときは launchctl bootout gui/$(id -u)/com.util.kakeibo.deploy

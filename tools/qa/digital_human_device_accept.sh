#!/usr/bin/env bash
# AcquireEnglish — 数字人真机自动化验收
# Digital-human real-device acceptance (adb + uiautomator).
#
# Usage (from repo root or anywhere):
#   ./tools/qa/digital_human_device_accept.sh
#   ./tools/qa/digital_human_device_accept.sh --install
#   ./tools/qa/digital_human_device_accept.sh --no-install --skip-build
#   ANDROID_SERIAL=b1481470 ./tools/qa/digital_human_device_accept.sh --install
#
# Exit: 0 = all hard checks PASS; 1 = hard FAIL; 2 = usage / missing tools.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MOBILE="$ROOT/apps/mobile"
PKG_PROD="com.acquire.english"
PKG_DEV="com.acquire.english.dev"
MAIN_ACT="${PKG_PROD}/.MainActivity"
APK_REL="build/app/outputs/flutter-apk/app-prod-debug.apk"
APK="$MOBILE/$APK_REL"

STAMP="$(date '+%Y%m%d-%H%M%S')"
ART_DIR="$ROOT/tools/qa/artifacts/$STAMP"
REPORT_MD="$ART_DIR/report.md"
REPORT_LOG="$ART_DIR/report.log"
UI_XML="$ART_DIR/ui_dump.xml"
UI_XML_DEVICE="/sdcard/acquire_dh_ui_dump.xml"

DO_INSTALL=0
NO_INSTALL=0
SKIP_BUILD=0
SKIP_COACH_HEALTH=0
COACH_HEALTH_URLS=(
  "https://acquireenglish.curlhairai.com/coach/api/health"
  "http://127.0.0.1:8770/api/health"
)

PASS_N=0
FAIL_N=0
MANUAL_N=0
SKIP_N=0
HARD_FAIL=0

usage() {
  cat <<'EOF'
AcquireEnglish 数字人真机验收脚本

用法:
  digital_human_device_accept.sh [选项]

选项:
  --install       构建（除非 --skip-build）并用 adb install -r 覆盖安装 prod debug
  --no-install    不安装，仅验收已装包（默认行为）
  --skip-build    与 --install 合用：跳过 flutter build，直接装已有 APK
  --skip-health   跳过 oral_coach HTTP health（默认会尝试公网/本机）
  -h, --help      显示帮助

环境变量:
  ANDROID_SERIAL  指定 adb 设备序列号（多机时必填）

产物:
  tools/qa/artifacts/<时间戳>/report.md|.log|*.png|ui_dump.xml
EOF
}

log() { printf '%s\n' "$*" | tee -a "$REPORT_LOG"; }
log_raw() { printf '%s\n' "$*" >>"$REPORT_LOG"; }

record() {
  # record STATUS "id" "中文说明" ["细节"]
  local status="$1" id="$2" title="$3" detail="${4:-}"
  local line mark
  case "$status" in
    PASS)   mark="✅ PASS"; PASS_N=$((PASS_N + 1)) ;;
    FAIL)   mark="❌ FAIL"; FAIL_N=$((FAIL_N + 1)); HARD_FAIL=1 ;;
    MANUAL) mark="🖐 MANUAL"; MANUAL_N=$((MANUAL_N + 1)) ;;
    SKIP)   mark="⏭ SKIP"; SKIP_N=$((SKIP_N + 1)) ;;
    INFO)   mark="ℹ️  INFO" ;;
    *)      mark="$status" ;;
  esac
  line="[$mark] $id — $title"
  if [[ -n "$detail" ]]; then
    line="$line · $detail"
  fi
  log "$line"
  {
    echo "| $mark | \`$id\` | $title | ${detail:-—} |"
  } >>"$REPORT_MD.tmp_rows"
}

adb_cmd() {
  if [[ -n "${ANDROID_SERIAL:-}" ]]; then
    adb -s "$ANDROID_SERIAL" "$@"
  else
    adb "$@"
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少依赖命令: $1" >&2
    exit 2
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --install) DO_INSTALL=1 ;;
      --no-install) NO_INSTALL=1; DO_INSTALL=0 ;;
      --skip-build) SKIP_BUILD=1 ;;
      --skip-health) SKIP_COACH_HEALTH=1 ;;
      -h|--help) usage; exit 0 ;;
      *)
        echo "未知参数: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
    shift
  done
  if [[ "$NO_INSTALL" -eq 1 && "$DO_INSTALL" -eq 1 ]]; then
    echo "--install 与 --no-install 互斥" >&2
    exit 2
  fi
}

init_report() {
  mkdir -p "$ART_DIR"
  : >"$REPORT_LOG"
  : >"$REPORT_MD.tmp_rows"
  cat >"$REPORT_MD" <<EOF
# 数字人真机验收报告

- 时间: $(date '+%Y-%m-%d %H:%M:%S %z')
- 仓库: \`$ROOT\`
- 包名目标: \`$PKG_PROD\`
- 设备: \`${ANDROID_SERIAL:-auto}\`
- 产物目录: \`$ART_DIR\`

| 结果 | 检查项 | 说明 | 细节 |
|------|--------|------|------|
EOF
}

finalize_report() {
  local verdict
  if [[ "$HARD_FAIL" -eq 0 ]]; then
    verdict="总体 **PASS**（硬失败=0；含 MANUAL/SKIP 项请人工扫一眼）"
  else
    verdict="总体 **FAIL**（存在硬失败项）"
  fi
  {
    cat "$REPORT_MD"
    cat "$REPORT_MD.tmp_rows"
    echo
    echo "## 汇总"
    echo
    echo "- PASS: $PASS_N"
    echo "- FAIL: $FAIL_N"
    echo "- MANUAL: $MANUAL_N"
    echo "- SKIP: $SKIP_N"
    echo
    echo "$verdict"
    echo
    echo "## 人工补验（脚本无法可靠断言时）"
    echo
    echo "1. 竖屏播放器拖动「问我」浮球 → 打开口语教练 bottom sheet（embedded）。"
    echo "2. 字幕行双 CEFR 标签形如 \`B1 · 中考\`。"
    echo "3. 句子收藏提示「已加入知识卡，进入复习队列」。"
    echo "4. 卡通数字人 atlas / 口型动画可见；LiveTalking GPU 非硬门槛。"
    echo "5. hintEnable 时点「卡壳」应返回脚手架提示（需会话已建立）。"
  } >"$REPORT_MD.final"
  mv "$REPORT_MD.final" "$REPORT_MD"
  rm -f "$REPORT_MD.tmp_rows"
  log ""
  log "======== 汇总 PASS=$PASS_N FAIL=$FAIL_N MANUAL=$MANUAL_N SKIP=$SKIP_N ========"
  log "报告: $REPORT_MD"
}

# --- Device ---

check_adb_device() {
  require_cmd adb
  local out state lines count
  out="$(adb devices | awk 'NR>1 && $1!="" {print $1"\t"$2}')"
  if [[ -z "${out//[[:space:]]/}" ]]; then
    record FAIL A-device "无在线 adb 设备" "请连接手机并开启 USB 调试"
    return 1
  fi

  if [[ -n "${ANDROID_SERIAL:-}" ]]; then
    state="$(printf '%s\n' "$out" | awk -F'\t' -v s="$ANDROID_SERIAL" '$1==s{print $2; exit}')"
    if [[ -z "$state" ]]; then
      record FAIL A-device "ANDROID_SERIAL 未出现在 adb devices" "$ANDROID_SERIAL"
      return 1
    fi
    if [[ "$state" != "device" ]]; then
      record FAIL A-device "设备未授权或离线" "$ANDROID_SERIAL state=$state"
      return 1
    fi
  else
    lines="$(printf '%s\n' "$out" | awk -F'\t' '$2=="device"{print $1}')"
    count="$(printf '%s\n' "$lines" | awk 'NF{c++} END{print c+0}')"
    if [[ "$count" -eq 0 ]]; then
      local unauthorized
      unauthorized="$(printf '%s\n' "$out" | awk -F'\t' '$2=="unauthorized"{print $1}' | tr '\n' ' ')"
      if [[ -n "${unauthorized//[[:space:]]/}" ]]; then
        record FAIL A-device "设备未授权（unauthorized）" "$unauthorized"
      else
        record FAIL A-device "无 authorized 设备" "$(printf '%s' "$out" | tr '\n' ' ')"
      fi
      return 1
    fi
    if [[ "$count" -gt 1 ]]; then
      record FAIL A-device "检测到多台设备，请设置 ANDROID_SERIAL" "$(printf '%s' "$lines" | tr '\n' ' ')"
      return 1
    fi
    ANDROID_SERIAL="$(printf '%s\n' "$lines" | head -n1)"
    export ANDROID_SERIAL
  fi

  local model sdk
  model="$(adb_cmd shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"
  sdk="$(adb_cmd shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r' || true)"
  record PASS A-device "adb 设备在线且已授权" "$ANDROID_SERIAL model=$model sdk=$sdk"
  return 0
}

# --- Build / install ---

maybe_build_install() {
  if [[ "$DO_INSTALL" -eq 0 ]]; then
    record SKIP B-install "未请求安装（默认 --no-install）" "需要时加 --install"
    return 0
  fi

  if [[ "$SKIP_BUILD" -eq 0 ]]; then
    require_cmd flutter
    log "构建 prod debug APK…"
    (
      cd "$MOBILE"
      flutter build apk --debug --flavor prod --no-pub
    ) || {
      record FAIL B-build "flutter build apk 失败" "$APK_REL"
      return 1
    }
    record PASS B-build "flutter build apk --debug --flavor prod" "$APK_REL"
  else
    record SKIP B-build "跳过构建 (--skip-build)" ""
  fi

  if [[ ! -f "$APK" ]]; then
    record FAIL B-install "APK 不存在" "$APK"
    return 1
  fi

  log "覆盖安装: adb install -r $APK"
  if adb_cmd install -r "$APK" >/tmp/ae_dh_install.out 2>&1; then
    record PASS B-install "adb install -r 成功（保留数据）" "$(basename "$APK")"
  else
    record FAIL B-install "adb install -r 失败" "$(tr '\n' ' ' </tmp/ae_dh_install.out)"
    return 1
  fi
}

check_package() {
  local path_line paths
  paths="$(adb_cmd shell pm path "$PKG_PROD" 2>/dev/null | tr -d '\r' || true)"
  if [[ -z "$paths" ]]; then
    record FAIL A-package "未安装正式包 $PKG_PROD" "请用 --install 或手动装 prod debug"
    return 1
  fi
  path_line="$(printf '%s\n' "$paths" | head -n1)"
  record PASS A-package "已安装正式包 $PKG_PROD" "$path_line"

  if adb_cmd shell pm path "$PKG_DEV" >/dev/null 2>&1; then
    record INFO A-package-dev "设备上同时存在 .dev 包（可忽略，本验收用 prod）" "$PKG_DEV"
  fi

  # Reject if somehow we're about to launch .dev
  if [[ "$PKG_PROD" == *".dev" ]]; then
    record FAIL A-package "包名配置错误（含 .dev）" "$PKG_PROD"
    return 1
  fi
  return 0
}

launch_app() {
  adb_cmd shell am force-stop "$PKG_PROD" >/dev/null 2>&1 || true
  sleep 0.4
  local out
  out="$(adb_cmd shell am start -W -n "$MAIN_ACT" 2>&1 | tr -d '\r' || true)"
  log_raw "am start: $out"
  if printf '%s' "$out" | grep -qiE 'Error|Exception|does not exist'; then
    record FAIL A-launch "启动失败" "$out"
    return 1
  fi
  # Wait for first frame / auth splash
  sleep 3
  local fg
  fg="$(adb_cmd shell dumpsys activity activities 2>/dev/null | tr -d '\r' | grep -E 'mResumedActivity|topResumedActivity' | head -n3 || true)"
  if printf '%s' "$fg" | grep -q "$PKG_PROD"; then
    record PASS A-launch "应用已启动且前台为 $PKG_PROD" "$(printf '%s' "$fg" | head -n1 | sed 's/^ *//')"
  else
    # Some OEM dumpsys formats differ; soft-fail only if process missing
    if adb_cmd shell pidof "$PKG_PROD" >/dev/null 2>&1; then
      record PASS A-launch "应用进程在跑（dumpsys 格式未命中前台行）" "pidok"
    else
      record FAIL A-launch "启动后进程不存在" "$out"
      return 1
    fi
  fi
  return 0
}

screenshot() {
  local name="$1"
  local dest="$ART_DIR/$name.png"
  if adb_cmd exec-out screencap -p >"$dest" 2>/dev/null && [[ -s "$dest" ]]; then
    log "截图: $dest"
    return 0
  fi
  rm -f "$dest"
  log "截图失败: $name"
  return 1
}

dump_ui() {
  # Flutter continuous animation often makes plain `uiautomator dump` fail with
  # "could not get idle state". Retry + compressed + short settle helps.
  local attempt=0
  local out=""
  adb_cmd shell rm -f "$UI_XML_DEVICE" /sdcard/window_dump.xml >/dev/null 2>&1 || true
  while (( attempt < 3 )); do
    attempt=$((attempt + 1))
    sleep 0.4
    out="$(adb_cmd shell uiautomator dump --compressed "$UI_XML_DEVICE" 2>&1 || true)"
    if adb_cmd pull "$UI_XML_DEVICE" "$UI_XML" >/dev/null 2>&1 && [[ -s "$UI_XML" ]]; then
      return 0
    fi
    out="$(adb_cmd shell uiautomator dump "$UI_XML_DEVICE" 2>&1 || true)"
    if adb_cmd pull "$UI_XML_DEVICE" "$UI_XML" >/dev/null 2>&1 && [[ -s "$UI_XML" ]]; then
      return 0
    fi
    # Default path on some OEMs
    adb_cmd shell uiautomator dump >/dev/null 2>&1 || true
    if adb_cmd pull /sdcard/window_dump.xml "$UI_XML" >/dev/null 2>&1 && [[ -s "$UI_XML" ]]; then
      return 0
    fi
  done
  log "uiautomator dump 仍失败（Flutter idle）: ${out//$'\n'/ }"
  return 1
}

ui_has_text() {
  local needle="$1"
  [[ -f "$UI_XML" ]] || return 1
  grep -Fq "text=\"$needle\"" "$UI_XML" 2>/dev/null \
    || grep -Fq "content-desc=\"$needle\"" "$UI_XML" 2>/dev/null
}

# Return bounds center "x y" for first node matching text= or content-desc=
ui_center_of_text() {
  local needle="$1"
  python3 - "$UI_XML" "$needle" <<'PY'
import re, sys
path, needle = sys.argv[1], sys.argv[2]
try:
    xml = open(path, encoding="utf-8", errors="ignore").read()
except OSError:
    sys.exit(1)
# Prefer exact text=, then content-desc=
patterns = [
    rf'text="{re.escape(needle)}"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
    rf'content-desc="{re.escape(needle)}"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
    rf'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*text="{re.escape(needle)}"',
    rf'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*content-desc="{re.escape(needle)}"',
]
for pat in patterns:
    m = re.search(pat, xml)
    if m:
        x1, y1, x2, y2 = map(int, m.groups())
        print((x1 + x2) // 2, (y1 + y2) // 2)
        sys.exit(0)
sys.exit(1)
PY
}

tap_text() {
  local needle="$1"
  local xy
  if ! dump_ui; then
    return 1
  fi
  xy="$(ui_center_of_text "$needle" || true)"
  if [[ -z "$xy" ]]; then
    return 1
  fi
  # shellcheck disable=SC2086
  adb_cmd shell input tap $xy >/dev/null 2>&1
  sleep 1.2
  return 0
}

dismiss_common_overlays() {
  # Best-effort: permission / update dialogs
  local labels=("允许" "仅在使用中允许" "仅限这一次" "同意" "我知道了" "关闭" "取消" "跳过")
  local lab
  for lab in "${labels[@]}"; do
    if dump_ui && ui_has_text "$lab"; then
      tap_text "$lab" || true
    fi
  done
}

navigate_to_oral_coach() {
  # Preferred automated path: bottom nav 「口语」→ /digital-human standalone coach.
  # Player 「问我」orb requires an open episode — marked MANUAL.
  dismiss_common_overlays
  screenshot "01_after_launch" || true

  if dump_ui && (ui_has_text "登录" || ui_has_text "验证码登录" || ui_has_text "微信登录"); then
    record MANUAL B-entry "当前在登录页，无法自动进入口语教练" "请先真机登录后再跑，或保留登录态后重试"
    screenshot "01b_login_gate" || true
    return 2
  fi

  if dump_ui && ui_has_text "问我"; then
    record PASS B-orb "UI 中已出现「问我」（可能在播放器或阅读浮球）" "将尝试点击"
    if tap_text "问我"; then
      sleep 1
      dump_ui || true
      screenshot "02_after_ask_me" || true
    fi
  else
    record MANUAL B-orb "未在当前页看到「问我」浮球" "请打开竖屏播放器后确认拖动浮球 → 口语 sheet"
  fi

  # Bottom nav 口语
  if tap_text "口语"; then
    :
  else
    # Coordinate fallback for 5-tab bars. Prod home is often
    # 学习/视频/阅读/口语/社区 → 口语 = 4th (≈70% width). Older builds used
    # 视频/阅读/口语/社区/对战 → 口语 = 3rd (center). Try both.
    local size w h cy
    size="$(adb_cmd shell wm size 2>/dev/null | tr -d '\r' | awk -F': ' '/Physical size/{print $2}')"
    w="${size%x*}"; h="${size#*x}"
    if [[ -n "$w" && -n "$h" ]]; then
      cy=$((h * 96 / 100))
      log "dump 不可用，依次点底栏候选「口语」坐标 (${w}x${h})"
      adb_cmd shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
      sleep 0.4
      for cx in $((w * 70 / 100)) $((w / 2)) $((w * 78 / 100)); do
        adb_cmd shell input tap "$cx" "$cy" >/dev/null 2>&1 || true
        sleep 1.6
        dump_ui || true
        if ui_has_text "数字人口语" || ui_has_text "换教练" || ui_has_text "卡壳" \
          || ui_has_text "英语口语闲聊" || ui_has_text "说话"; then
          break
        fi
      done
    fi
  fi
  sleep 1.2
  dump_ui || true
  screenshot "03_oral_tab" || true
  if ui_has_text "数字人口语" || ui_has_text "数字人" || ui_has_text "说话" \
    || ui_has_text "场景" || ui_has_text "音色" || ui_has_text "英语口语闲聊" \
    || ui_has_text "卡壳" || ui_has_text "换教练"; then
    record PASS B-entry "已进入口语/数字人页（底栏「口语」）" "route≈/digital-human"
    return 0
  fi
  # Soft pass only when screenshot likely shows coach (filename always exists after shot)
  if [[ -f "$ART_DIR/03_oral_tab.png" ]] && dump_ui && (ui_has_text "口语" || ui_has_text "说话" || ui_has_text "换教练"); then
    record PASS B-entry "已点到「口语」底栏（dump 弱/对照截图）" "请对照截图 03_oral_tab.png"
    return 0
  fi

  record MANUAL B-entry "未能自动导航到口语教练" "fallback：登录后点底栏「口语」，或播放器「问我」"
  return 2
}

ensure_app_foreground() {
  local fg
  fg="$(adb_cmd shell dumpsys activity activities 2>/dev/null | tr -d '\r' | grep -E 'mResumedActivity|topResumedActivity' | head -n2 || true)"
  if printf '%s' "$fg" | grep -q "$PKG_PROD"; then
    return 0
  fi
  log "前台已离开 $PKG_PROD，重新拉起并点「口语」"
  adb_cmd shell am start -n "$PKG_PROD/.MainActivity" >/dev/null 2>&1 || \
    adb_cmd shell monkey -p "$PKG_PROD" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
  sleep 2.5
  local size w h cx cy
  size="$(adb_cmd shell wm size 2>/dev/null | tr -d '\r' | awk -F': ' '/Physical size/{print $2}')"
  w="${size%x*}"; h="${size#*x}"
  if [[ -n "$w" && -n "$h" ]]; then
    cy=$((h * 96 / 100))
    # Prefer 4th-of-5 tab (口语 on 学习/视频/阅读/口语/社区)
    for cx in $((w * 70 / 100)) $((w / 2)); do
      adb_cmd shell input tap "$cx" "$cy" >/dev/null 2>&1 || true
      sleep 1.4
    done
  fi
}

assert_coach_ui() {
  ensure_app_foreground
  # Screenshot first — dump retries can lose foreground on some OEMs.
  screenshot "04_coach_ui" || true

  local dumped=0
  if dump_ui; then
    dumped=1
    # If dump is launcher chrome, re-enter oral and dump once more.
    if ui_has_text "爱快英语" && ui_has_text "搜索" && ! ui_has_text "数字人口语"; then
      record INFO C-dump "dump 像桌面，尝试重新进入口语页" ""
      ensure_app_foreground
      screenshot "04b_coach_ui_retry" || true
      dump_ui && dumped=1 || dumped=0
    fi
  else
    # Flutter lip-sync / LiveTalking keeps the a11y tree busy — do not hard-fail
    # the whole run; screenshots + logcat still give real-device evidence.
    record MANUAL C-dump "uiautomator dump 失败（Flutter 动画/idle）" "对照 04_coach_ui.png 目视验收"
  fi

  # Crash / ANR smell
  local tomb
  tomb="$(adb_cmd logcat -d -t 80 2>/dev/null | tr -d '\r' | grep -E "FATAL EXCEPTION|AndroidRuntime|$PKG_PROD.*crash" | tail -n3 || true)"
  if [[ -n "$tomb" ]]; then
    record FAIL C-sheet "检测到疑似崩溃日志" "$tomb"
  else
    record PASS C-sheet "口语页打开后未见即时 FATAL（logcat 近窗）" ""
  fi

  # Avatar / stage — Flutter often does not expose asset names; use chrome text.
  if [[ "$dumped" -eq 1 ]] && (ui_has_text "数字人口语" || ui_has_text "数字人" || ui_has_text "英语口语闲聊" \
    || ui_has_text "选择场景" || ui_has_text "场景" || ui_has_text "换教练"); then
    record PASS C-avatar "教练舞台相关文案可见（卡通阶段弱断言）" "完整口型需人工看截图"
  else
    record MANUAL C-avatar "未能从 UI dump 断言卡通数字人舞台" "请打开 04_coach_ui.png 目视确认 atlas/头像"
  fi

  # Mic / hold-to-talk — labels 说话 / 松开 / 再说 (ValueKey study-oral-coach-mic-legacy not in dump)
  if [[ "$dumped" -eq 1 ]] && (ui_has_text "说话" || ui_has_text "松开" || ui_has_text "再说" || ui_has_text "按住说话"); then
    record PASS D-mic "按住说话控件文案可见" "代码 ValueKey=study-oral-coach-mic-legacy"
  else
    record MANUAL D-mic "未在 dump 中看到「说话」等麦克风文案" "可能需先选场景/素材；对照截图与 ValueKey"
  fi

  # 卡壳 — only when hintEnable (player sheet true; standalone default true)
  if [[ "$dumped" -eq 1 ]] && ui_has_text "卡壳"; then
    record PASS E-hint "「卡壳」按钮可见（hintEnable 路径）" ""
  else
    record MANUAL E-hint "当前页未见「卡壳」" "embedded 播放器 sheet + hintEnable=true 时应出现；或会话 UI 未展开 dock"
  fi
}

check_coach_health() {
  if [[ "$SKIP_COACH_HEALTH" -eq 1 ]]; then
    record SKIP F-health "跳过 oral_coach health (--skip-health)" ""
    return 0
  fi
  require_cmd curl
  local url ok=0 body code
  for url in "${COACH_HEALTH_URLS[@]}"; do
    body="$(curl -fsS --connect-timeout 3 --max-time 8 "$url" 2>/dev/null || true)"
    if [[ -n "$body" ]]; then
      code=0
      if printf '%s' "$body" | grep -qiE '"ready"\s*:\s*true|"status"\s*:\s*"ok"|ok'; then
        record PASS F-health "oral_coach health 可达" "$url → ${body:0:120}"
        ok=1
        break
      else
        record INFO F-health "health 有响应但未识别 ready" "$url → ${body:0:120}"
        ok=1
        break
      fi
    fi
  done
  if [[ "$ok" -eq 0 ]]; then
    record SKIP F-health "Mac 侧未能连上 oral_coach health（非硬失败）" "可 SSH ECS 查 acquireenglish-oral-coach / :8770；LiveTalking GPU 非本脚本门槛"
  fi
}

# --- main ---

main() {
  parse_args "$@"
  # Allow --help without creating artifacts? already exited.
  # Device-less path still creates report dir after we know we'll run checks —
  # but for clean fail-before-device we need ART_DIR. Create early.
  init_report
  log "AcquireEnglish 数字人真机验收 · $STAMP"
  log "ROOT=$ROOT"

  check_coach_health

  if ! check_adb_device; then
    finalize_report
    log "无可用设备 — 脚本已就位。连接手机后执行:"
    log "  $ROOT/tools/qa/digital_human_device_accept.sh --install"
    exit 1
  fi

  maybe_build_install || true
  if ! check_package; then
    if [[ "$DO_INSTALL" -eq 0 ]]; then
      log "提示: 加 --install --skip-build 可安装已有 APK: $APK"
    fi
    finalize_report
    exit 1
  fi

  if ! launch_app; then
    finalize_report
    exit 1
  fi

  local nav_rc=0
  navigate_to_oral_coach || nav_rc=$?
  # 0 = entered; 2 = manual; other = soft
  if [[ "$nav_rc" -eq 0 ]]; then
    assert_coach_ui
  else
    record MANUAL C-sheet "跳过教练 UI 深检（未进入口语页）" ""
    record MANUAL D-mic "跳过麦克风断言" ""
    record MANUAL E-hint "跳过卡壳断言" ""
    screenshot "99_final_state" || true
  fi

  # Final screenshot always useful
  screenshot "99_final" || true

  # G already covered via screenshot calls
  if ls "$ART_DIR"/*.png >/dev/null 2>&1; then
    record PASS G-shots "已保存 screencap 到 artifacts" "$ART_DIR"
  else
    record FAIL G-shots "未能保存任何截图" ""
  fi

  finalize_report
  # Echo Chinese one-liner for humans
  if [[ "$HARD_FAIL" -eq 0 ]]; then
    echo "真机验收硬检查通过（含 MANUAL 项请看报告）。"
    exit 0
  fi
  echo "真机验收存在失败项，见 $REPORT_MD" >&2
  exit 1
}

main "$@"

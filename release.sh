#!/usr/bin/env bash
#
# release.sh —— 一键发布新版 PRD 原型
#
#   替换 index.html → 更新 README 版本表 → 提交 → 打 tag → 推送 → 建 Release
#   → 等 GitHub Pages 构建完成 → 线上验收
#
# 用法:
#   ./release.sh "../../【V2.12-查看】....html" --notes notes/v2.12.md
#   ./release.sh new.html --version v2.12.1 --title "V2.12.1 热修"
#   ./release.sh --check new.html          # 只校验，不改任何东西
#   ./release.sh --resume                  # 推送失败后接着跑（跳过提交）
#   ./release.sh --push-only               # 只把本地提交推上去
#   ./release.sh --save-token              # 把 token 存进 macOS Keychain
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# ---------- 输出 ----------
if [ -t 1 ]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'
else
  B=''; G=''; Y=''; R=''; D=''; N=''
fi
info() { printf '%s▸%s %s\n' "$D" "$N" "$*"; }
ok()   { printf '%s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s!%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%s✗%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

# ---------- 参数 ----------
HTML=""
VERSION=""
TITLE=""
NOTES=""
DATE_STR="$(date +%F)"
DRY_RUN=0
CHECK_ONLY=0
ASSUME_YES=0
UPDATE_README=1
UPLOAD_ASSET=1
BUMP=0
SAVE_TOKEN=0
RESUME=0
PUSH_ONLY=0
BRANCH="main"

while [ $# -gt 0 ]; do
  case "$1" in
    -v|--version) VERSION="${2:-}"; shift 2 ;;
    -t|--title)   TITLE="${2:-}";   shift 2 ;;
    -n|--notes)   NOTES="${2:-}";   shift 2 ;;
    -d|--date)    DATE_STR="${2:-}"; shift 2 ;;
    --bump)       BUMP=1; shift ;;
    --no-readme)  UPDATE_README=0; shift ;;
    --no-asset)   UPLOAD_ASSET=0; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --check)      CHECK_ONLY=1; shift ;;
    --save-token) SAVE_TOKEN=1; shift ;;
    --resume)     RESUME=1; shift ;;
    --push-only)  PUSH_ONLY=1; shift ;;
    -y|--yes)     ASSUME_YES=1; shift ;;
    -h|--help)    awk 'NR>=3 && /^#/ {sub(/^# ?/,""); print; next} NR>=3 {exit}' "$0"; exit 0 ;;
    -*)           die "未知参数: $1（--help 查看用法）" ;;
    *)            [ -z "$HTML" ] && HTML="$1" || die "多余参数: $1"; shift ;;
  esac
done

# ---------- 仓库信息 ----------
git rev-parse --git-dir >/dev/null 2>&1 || die "当前目录不是 git 仓库: $REPO_DIR"

REMOTE_URL="$(git config --get remote.origin.url || true)"
[ -n "$REMOTE_URL" ] || die "未配置 remote.origin.url"
OWNER_REPO="${REMOTE_URL%.git}"          # 去掉尾部 .git
OWNER_REPO="${OWNER_REPO#*github.com:}"   # git@github.com:owner/repo
OWNER_REPO="${OWNER_REPO#*github.com/}"   # https://github.com/owner/repo
OWNER="${OWNER_REPO%%/*}"
REPO="${OWNER_REPO#*/}"
[ -n "$OWNER" ] && [ -n "$REPO" ] || die "无法从 remote 解析 owner/repo: $REMOTE_URL"

PAGE_URL="${PAGE_URL:-https://$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]').github.io/$REPO/}"
API="https://api.github.com/repos/$OWNER/$REPO"

# ---------- token ----------
read_token() {
  TOKEN=""
  if [ -n "${GITHUB_TOKEN:-}" ]; then TOKEN="$GITHUB_TOKEN"; return 0; fi
  if [ -n "${GH_TOKEN:-}" ]; then TOKEN="$GH_TOKEN"; return 0; fi
  local t
  if t="$(security find-generic-password -s "$REPO" -w 2>/dev/null)"; then TOKEN="$t"; return 0; fi
  if [ -f "$HOME/.config/$REPO/token" ]; then TOKEN="$(cat "$HOME/.config/$REPO/token")"; return 0; fi
  if command -v gh >/dev/null 2>&1 && t="$(gh auth token 2>/dev/null)"; then TOKEN="$t"; return 0; fi
  return 1
}

if [ "$SAVE_TOKEN" = 1 ]; then
  read -r -s -p "粘贴 GitHub token（不会回显）: " _t; echo
  [ -n "$_t" ] || die "token 为空"
  security add-generic-password -a "$USER" -s "$REPO" -w "$_t" -U >/dev/null \
    && ok "已存进 Keychain（服务名: ${REPO}），之后 $0 会自动读取" \
    || die "写入 Keychain 失败"
  exit 0
fi

# ---------- 只推送 ----------
if [ "$PUSH_ONLY" = 1 ]; then
  read_token || die "找不到 token，先执行 ./release.sh --save-token"
  TMP_FILES=()
  cleanup() { for f in ${TMP_FILES[@]+"${TMP_FILES[@]}"}; do [ -n "$f" ] && rm -f "$f"; done; }
  trap cleanup EXIT
  git_push() {
    local pass ask
    pass="$(mktemp)"; ask="$(mktemp)"; TMP_FILES+=("$pass" "$ask")
    chmod 600 "$pass"; chmod 700 "$ask"
    printf '%s' "$TOKEN" >"$pass"
    printf '#!/bin/sh\nexec cat %q\n' "$pass" >"$ask"
    GIT_ASKPASS="$ask" GIT_TERMINAL_PROMPT=0 \
      git -c credential.helper= push "https://x-access-token@github.com/$OWNER/$REPO.git" "$@"
  }
  info "推送 $BRANCH"
  git_push "$BRANCH" || die "推送失败，检查网络或 token 权限"
  ok "已推送"
  exit 0
fi

# ---------- 校验输入 ----------
if [ "$RESUME" = 0 ]; then
[ -n "$HTML" ] || die "缺少输入文件。用法: ./release.sh <新的index.html> [--notes x.md]"
[ -f "$HTML" ] || die "文件不存在: $HTML"
HTML="$(cd "$(dirname "$HTML")" && pwd)/$(basename "$HTML")"

SIZE=$(wc -c <"$HTML" | tr -d ' ')
[ "$SIZE" -gt 100000 ] || die "文件只有 $SIZE 字节，不像完整原型（预期 >100 KB）"
head -c 2000 "$HTML" | grep -qi '<!DOCTYPE html\|<html' || die "开头不像 HTML 文件"
if ! tail -c 400 "$HTML" | grep -q '</html>'; then
  warn "文件结尾没有 </html>，确认没被截断"
fi
SIZE_MB="$(awk -v s="$SIZE" 'BEGIN{printf "%.1f", s/1048576}')"

ORIG_SHA="$(shasum -a 256 "$HTML" | cut -d' ' -f1)"
if [ -f index.html ] && [ "$(shasum -a 256 index.html | cut -d' ' -f1)" = "$ORIG_SHA" ]; then
  die "内容与当前 index.html 完全一致，没有可发布的变更"
fi

# ---------- 版本号 ----------
if [ -z "$VERSION" ]; then
  if [ "$BUMP" = 1 ]; then
    latest="$(git tag --list 'v*' --sort=-v:refname | head -1)"
    [ -n "$latest" ] || die "没有历史 tag，无法 --bump，请用 --version"
    base="${latest#v}"; major="${base%%.*}"; rest="${base#*.}"; minor="${rest%%.*}"
    VERSION="v${major}.$((minor + 1)).0"
    info "按最新 tag $latest 自增 → $VERSION"
  else
    from_name="$(basename "$HTML" | grep -oE '[Vv][0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)"
    [ -n "$from_name" ] || die "文件名里没有版本号，请用 --version 显式指定（如 v2.12.0）"
    VERSION="${from_name#[Vv]}"
    case "$VERSION" in
      *.*.*) : ;;
      *.*)   VERSION="$VERSION.0" ;;
    esac
    VERSION="v$VERSION"
    info "从文件名识别版本 → $VERSION"
  fi
fi
RAW="${VERSION#[Vv]}"
IFS=. read -r MAJOR MINOR PATCH <<<"$RAW"
[[ "${MAJOR:-}" =~ ^[0-9]+$ ]] && [[ "${MINOR:-}" =~ ^[0-9]+$ ]] \
  || die "版本号格式应为 vX.Y 或 vX.Y.Z，收到: $VERSION"
[ -n "${PATCH:-}" ] || PATCH=0
[[ "$PATCH" =~ ^[0-9]+$ ]] || die "版本号第三段应为数字，收到: $VERSION"
VERSION="v${MAJOR}.${MINOR}.${PATCH}"

SEMVER="${VERSION#v}"
DISP="V${SEMVER%.*}"
TITLE="${TITLE:-$DISP · 需求框架与高保真原型}"

# ---------- tag 冲突 ----------
git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null && die "本地已存在 tag ${VERSION}（换一个版本号，或先删除旧 tag）"

read_token || true
TOKEN_OK=0
[ -n "${TOKEN:-}" ] && TOKEN_OK=1
REMOTE_TAG_CHECK="未启用（无 token）"
if [ "$TOKEN_OK" = 1 ]; then
  if [ "$DRY_RUN" = 1 ]; then
    REMOTE_TAG_CHECK="跳过（dry-run）"
  else
    RCODE="$(curl -sS -m 20 -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
      "$API/git/ref/tags/$VERSION" || true)"
    [ "$RCODE" = "200" ] && die "远端已存在 tag $VERSION"
    REMOTE_TAG_CHECK="已校验"
  fi
fi

else
# ---------- --resume：推送失败后从这里续跑 ----------
[ -z "$(git status --porcelain)" ] || die "--resume 要求工作区干净（请先提交或还原改动）"
AT_HEAD="$(git tag --points-at HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
[ -n "$AT_HEAD" ] || die "--resume 需要当前 HEAD 带版本 tag；若还没有提交，请正常执行 ./release.sh <html>"
VERSION="${VERSION:-$AT_HEAD}"
[ "${VERSION#v}" = "${AT_HEAD#v}" ] || die "指定版本 $VERSION 与 HEAD 上的 tag $AT_HEAD 不一致"
VERSION="v${VERSION#v}"
SEMVER="${VERSION#v}"
DISP="V${SEMVER%.*}"
TITLE="${TITLE:-$DISP · 需求框架与高保真原型}"
SIZE_MB="—"
UPDATE_README=0
read_token || true
TOKEN_OK=0
[ -n "${TOKEN:-}" ] && TOKEN_OK=1
REMOTE_TAG_CHECK="跳过（resume）"
fi

# ---------- 说明文件 ----------
if [ -n "$NOTES" ]; then
  [ -f "$NOTES" ] || die "说明文件不存在: $NOTES"
  NOTES="$(cd "$(dirname "$NOTES")" && pwd)/$(basename "$NOTES")"
fi

# ---------- 计划 ----------
printf '\n%s发布计划%s\n' "$B" "$N"
printf '  仓库      %s/%s\n' "$OWNER" "$REPO"
printf '  版本      %s（%s）\n' "$VERSION" "$DATE_STR"
printf '  标题      %s\n' "$TITLE"
printf '  源文件    %s（%s MB）\n' "$HTML" "$SIZE_MB"
printf '  tag 校验  本地已通过；远端 %s\n' "$REMOTE_TAG_CHECK"
printf '  README    %s\n' "$([ "$UPDATE_README" = 1 ] && echo '更新版本号与版本记录' || echo '不修改')"
printf '  Release   %s\n' "$([ "$UPLOAD_ASSET" = 1 ] && echo '创建，并附上 HTML 附件' || echo '创建（不带附件）')"
printf '  线上地址  %s\n\n' "$PAGE_URL"

if [ "$DRY_RUN" = 1 ]; then
  ok "dry-run：以上为计划，未做任何改动"
  exit 0
fi
if [ "$CHECK_ONLY" = 1 ]; then
  ok "check：输入文件与版本号可用，可以发布"
  exit 0
fi

# ---------- 凭据 ----------
if [ "$TOKEN_OK" != 1 ]; then
  die "找不到 token。
  一次性设置:  ./release.sh --save-token
  或环境变量:  export GITHUB_TOKEN=ghp_xxx
  或文件:      ~/.config/$REPO/token
  token 需要 $OWNER/$REPO 的 Contents 读写 + Releases 读写 + Pages 读。"
fi

TMP_FILES=()
cleanup() { for f in ${TMP_FILES[@]+"${TMP_FILES[@]}"}; do [ -n "$f" ] && rm -f "$f"; done; }
trap cleanup EXIT

# token 只经由 600 权限的临时文件传给 git，不出现在命令行
git_push() {
  local pass ask
  pass="$(mktemp)"; ask="$(mktemp)"
  TMP_FILES+=("$pass" "$ask")
  chmod 600 "$pass"; chmod 700 "$ask"
  printf '%s' "$TOKEN" >"$pass"
  printf '#!/bin/sh\nexec cat %q\n' "$pass" >"$ask"
  GIT_ASKPASS="$ask" GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= push "https://x-access-token@github.com/$OWNER/$REPO.git" "$@"
}

api() { # api METHOD PATH [DATA]
  local method="$1" path="$2" data="${3:-}"
  local args=(-sS -m 60 -X "$method" -H "Authorization: Bearer $TOKEN"
              -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
  [ -n "$data" ] && args+=(-d "$data")
  curl "${args[@]}" "$API$path"
}

SHA="$(git rev-parse --short HEAD)"

if [ "$ASSUME_YES" = 0 ]; then
  read -r -p "确认发布？[y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || die "已取消"
fi

# ---------- 0. 连通性预检 ----------
info "检查 GitHub 连通性"
PCODE="$(curl -sS -m 10 -o /dev/null -w '%{http_code}' https://api.github.com/ 2>/dev/null || true)"
GCODE="$(curl -sS -m 10 -o /dev/null -w '%{http_code}' https://github.com/ 2>/dev/null || true)"
if [ -z "$PCODE" ] || [ "$PCODE" = "000" ] || [ -z "$GCODE" ] || [ "$GCODE" = "000" ]; then
  die "连不上 api.github.com，未做任何改动。
  本机到 GitHub 的线路不稳定，配好代理后重试：
    export HTTPS_PROXY=http://127.0.0.1:7890   # 换成你的代理端口
  git 与 curl 都会自动使用该变量。"
fi

if [ "$RESUME" = 0 ]; then
# ---------- 1. 替换 ----------
info "替换 index.html"
cp "$HTML" index.html
git add index.html

# ---------- 2. README ----------
if [ "$UPDATE_README" = 1 ]; then
  info "更新 README 版本信息"
  python3 scripts/update_readme.py --version "$DISP" --date "$DATE_STR" --notes "${NOTES:-}" \
    || die "README 更新失败"
  git add README.md
fi

# ---------- 3. 提交 ----------
COMMIT_MSG="feat($DISP): 更新原型至 $DISP"
if [ -n "$NOTES" ]; then
  COMMIT_MSG="$COMMIT_MSG"$'\n\n'"$(grep -v '^#' "$NOTES" | head -20)"
fi
git commit -q -m "$COMMIT_MSG" || die "提交失败（工作区可能无变更）"
SHA="$(git rev-parse --short HEAD)"
ok "已提交 $SHA"

# ---------- 4. tag ----------
info "打 tag $VERSION"
git tag -a "$VERSION" -m "$TITLE"

fi  # !resume

# ---------- 5. 推送 ----------
info "推送 $BRANCH 与 $VERSION"
if ! git_push "$BRANCH"; then
  die "推送 $BRANCH 失败：本地已有提交 $SHA 和 tag ${VERSION}，但没推到 GitHub。
  网络恢复后无需重做提交，直接执行：
    ./release.sh --resume
  （会接着推送、建 Release、等 Pages、做线上验收）"
fi
if ! git_push "refs/tags/$VERSION"; then
  die "推送 tag $VERSION 失败。网络恢复后执行： ./release.sh --resume"
fi
ok "已推送"

# ---------- 6. Release ----------
BODY_FILE="$(mktemp)"; TMP_FILES+=("$BODY_FILE")
if [ -n "$NOTES" ]; then
  { printf '**在线预览**：%s\n\n' "$PAGE_URL"; cat "$NOTES"; } >"$BODY_FILE"
else
  printf '**在线预览**：%s\n\n版本 %s 发布，变更详见提交记录。\n' "$PAGE_URL" "$DISP" >"$BODY_FILE"
  warn "未提供 --notes，Release 说明较简略"
fi

REQ="$(jq -n --arg tag "$VERSION" --arg name "$TITLE" --rawfile body "$BODY_FILE" --arg target "$BRANCH" \
  '{tag_name:$tag, name:$name, body:$body, target_commitish:$target, draft:false, prerelease:false}')"
RESP="$(api POST "/releases" "$REQ")"
RID="$(printf '%s' "$RESP" | jq -r '.id // empty')"
RURL="$(printf '%s' "$RESP" | jq -r '.html_url // empty')"
[ -n "$RID" ] || die "创建 Release 失败：$(printf '%s' "$RESP" | jq -r '.message // .' | head -3)"
ok "Release 已创建 $RURL"

# ---------- 7. 附件 ----------
if [ "$UPLOAD_ASSET" = 1 ]; then
  ASSET="saas-new-car-qc-prd-$VERSION.html"
  info "上传附件 $ASSET"
  ACODE="$(curl -sS -m 600 -X POST -H "Authorization: Bearer $TOKEN" \
             -H "Content-Type: text/html" --data-binary @"$HTML" \
             "https://uploads.github.com/repos/$OWNER/$REPO/releases/$RID/assets?name=$ASSET" \
             -o /dev/null -w '%{http_code}')"
  [ "$ACODE" = "201" ] && ok "附件已上传" || warn "附件上传失败（HTTP ${ACODE}），不影响发布"
fi

# ---------- 8. 等 Pages ----------
info "等待 GitHub Pages 构建……"
BUILT=0
for _ in $(seq 1 40); do
  BJSON="$(api GET "/pages/builds/latest" 2>/dev/null || true)"
  BSTATUS="$(printf '%s' "$BJSON" | jq -r '.status // empty' 2>/dev/null || true)"
  BSHA="$(printf '%s' "$BJSON" | jq -r '.commit // empty' 2>/dev/null || true)"
  if [ "$BSTATUS" = "built" ] && [ "${BSHA#"$SHA"}" != "$BSHA" ]; then BUILT=1; break; fi
  sleep 5
done
if [ "$BUILT" = 1 ]; then ok "Pages 构建完成"; else warn "等 Pages 超时，继续做线上验证"; fi

# ---------- 9. 验收 ----------
info "线上验收 $PAGE_URL"
CODE="$(curl -sS -m 60 --compressed -o /tmp/.release-check.html -w '%{http_code}' "$PAGE_URL?v=$VERSION")"
[ "$CODE" = "200" ] || die "线上首页返回 HTTP $CODE"
TITLE_ONLINE="$(grep -o '<title>[^<]*' /tmp/.release-check.html | head -1 | sed 's/<title>//')"
ECH="$(curl -sS -m 60 -o /dev/null -w '%{http_code}' "${PAGE_URL}_shared/js/echarts.min.js")"
[ "$ECH" = "200" ] || warn "echarts 返回 HTTP ${ECH}，图表可能失效（检查 .nojekyll）"
rm -f /tmp/.release-check.html

printf '\n%s发布完成 %s%s\n' "$B" "$VERSION" "$N"
printf '  在线    %s\n' "$PAGE_URL"
printf '  仓库    https://github.com/%s/%s\n' "$OWNER" "$REPO"
printf '  Release %s\n' "${RURL:-—}"
printf '  页面    %s\n' "${TITLE_ONLINE:-未知}"

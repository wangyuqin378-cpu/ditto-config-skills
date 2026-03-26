#!/usr/bin/env bash
#
# SSO 登录流程 Shell 脚本
# 用法:
#   ./run-sso.sh <workspace>          # 获取 SSO token (common-internal-access-token-prod)
#   ./run-sso.sh <workspace> --porch  # 获取 porch session (porch_beaker_session_id)
#
# 必须传入 workspace 路径，登录态存于 {workspace}/.redInfo
#
# SSO token 模式 exit code:
#   0: 有效，stdout 输出 common-internal-access-token-prod=<token>
#   1: 未登录，stderr 输出登录 URL
#
# porch session 模式 (--porch) exit code:
#   0: 有效，stdout 输出 porch_beaker_session_id=<value>
#   2: porch session 不存在或已过期，stderr 输出提示信息
#

set -e

API_BASE_URL="https://fe-data.devops.xiaohongshu.com"
CREATE_APP_URL="${API_BASE_URL}/api/open/app"
GET_TOKEN_URL="${API_BASE_URL}/api/open/app/token"
LOGIN_PAGE_URL="${API_BASE_URL}/login"
APP_DESC="${APP_DESC:-XCodeBook}"

# 必须传入 workspace 路径
[[ -n "${1:-}" ]] || { echo "用法: $0 <workspace> [--porch]" >&2; echo "必须传入 workspace 路径，登录态将存于 {workspace}/.redInfo" >&2; exit 1; }
BASE_DIR="$1"
AUTH_FILE="${BASE_DIR}/.redInfo"
MODE="${2:-}"

# 检查 jq
command -v jq >/dev/null 2>&1 || { echo "需要安装 jq: brew install jq" >&2; exit 1; }

read_app_id_from_file() {
  [[ -f "$AUTH_FILE" ]] || return
  local app_id
  app_id=$(jq -r '.appId // empty' "$AUTH_FILE" 2>/dev/null)
  [[ -n "$app_id" ]] && echo "$app_id"
}

# 仅创建新 appId（不依赖已有 .redInfo）
create_app_id() {
  local create_resp
  create_resp=$(curl -s -w "\n%{http_code}" -X POST "$CREATE_APP_URL" \
    -H "Content-Type: application/json" \
    -d "{\"appDesc\":\"$APP_DESC\",\"callback_urls\":[]}" 2>/dev/null)
  local http_code body
  http_code=$(echo "$create_resp" | tail -n1)
  body=$(echo "$create_resp" | sed '$d')
  if [[ "$http_code" != "200" ]] || ! echo "$body" | jq -e '.success == true and .data.appId' >/dev/null 2>&1; then
    echo "创建应用失败: $body" >&2
    exit 1
  fi
  echo "$body" | jq -r '.data.appId'
}

# 获取或创建 appId（有 .redInfo 时先尝试更新已有 appId）
get_or_create_app_id() {
  local existing_app_id
  existing_app_id=$(read_app_id_from_file)

  if [[ -n "$existing_app_id" ]]; then
    local update_resp
    update_resp=$(curl -s -w "\n%{http_code}" -X POST "$CREATE_APP_URL" \
      -H "Content-Type: application/json" \
      -d "{\"appId\":\"$existing_app_id\",\"appDesc\":\"$APP_DESC\",\"callback_urls\":[]}" 2>/dev/null) || true
    local http_code body
    http_code=$(echo "$update_resp" | tail -n1)
    body=$(echo "$update_resp" | sed '$d')
    if [[ "$http_code" == "200" ]] && echo "$body" | jq -e '.success == true and .data.appId' >/dev/null 2>&1; then
      echo "$body" | jq -r '.data.appId'
      return
    fi
  fi
  create_app_id
}

# 通过 appId 从接口获取 token，成功时输出 JSON，失败时 exit 1
get_token_by_app_id() {
  local app_id="$1"
  local resp
  resp=$(curl -s -w "\n%{http_code}" "${GET_TOKEN_URL}?appId=${app_id}" 2>/dev/null)
  local http_code body
  http_code=$(echo "$resp" | tail -n1)
  body=$(echo "$resp" | sed '$d')
  if [[ "$http_code" == "200" ]] && echo "$body" | jq -e '.success == true and .data.accessToken and .data.userInfo' >/dev/null 2>&1; then
    echo "$body"
    return
  fi
  # 404 且非重试：创建新 appId 再试
  if echo "$body" | jq -e '.code == 404' >/dev/null 2>&1 && [[ "${2:-}" != "retry" ]]; then
    local new_app_id
    new_app_id=$(get_or_create_app_id)
    save_auth_state "{\"appId\":\"$new_app_id\"}"
    get_token_by_app_id "$new_app_id" "retry"
    return
  fi
  echo "获取 token 失败: $body" >&2
  exit 1
}

save_auth_state() {
  local state="$1"
  mkdir -p "$BASE_DIR"
  echo "$state" | jq '.' > "$AUTH_FILE" 2>/dev/null || echo "$state" > "$AUTH_FILE"
}

output_login_url() {
  local app_id="$1"
  save_auth_state "{\"appId\":\"$app_id\"}"
  echo "${LOGIN_PAGE_URL}?appId=${app_id}" >&2
  exit 1
}

get_porch_session() {
  if [[ ! -f "$AUTH_FILE" ]]; then
    echo "porch session 未设置，请运行: bash $(dirname "$0")/set-porch-session.sh <workspace> <porch_beaker_session_id>" >&2
    echo "在浏览器 fe.devops.xiaohongshu.com 的 Network 请求中复制 porch_beaker_session_id" >&2
    exit 2
  fi

  local porch_session porch_exp now
  porch_session=$(jq -r '.porchSession // empty' "$AUTH_FILE" 2>/dev/null)
  porch_exp=$(jq -r '.porchSessionExp // 0' "$AUTH_FILE" 2>/dev/null)
  now=$(($(date +%s) * 1000))

  if [[ -z "$porch_session" ]]; then
    echo "porch session 未设置，请运行: bash $(dirname "$0")/set-porch-session.sh <workspace> <porch_beaker_session_id>" >&2
    echo "在浏览器 fe.devops.xiaohongshu.com 的 Network 请求中复制 porch_beaker_session_id" >&2
    exit 2
  fi

  if [[ "$porch_exp" -gt 0 && "$now" -ge "$porch_exp" ]]; then
    echo "porch session 已过期，请重新运行: bash $(dirname "$0")/set-porch-session.sh <workspace> <porch_beaker_session_id>" >&2
    exit 2
  fi

  echo "porch_beaker_session_id=${porch_session}"
}

main() {
  # porch session 模式
  if [[ "$MODE" == "--porch" ]]; then
    get_porch_session
    return
  fi

  # 路径 1: .redInfo 存在且登录态有效
  if [[ -f "$AUTH_FILE" ]]; then
    local token exp now
    token=$(jq -r '.token // empty' "$AUTH_FILE" 2>/dev/null)
    exp=$(jq -r '.exp // 0' "$AUTH_FILE" 2>/dev/null)
    now=$(($(date +%s) * 1000))
    if [[ -n "$token" && "$exp" -gt 0 && "$now" -lt "$exp" ]]; then
      echo "common-internal-access-token-prod=${token}"
      return
    fi
  fi

  # 路径 2: .redInfo 不存在
  if [[ ! -f "$AUTH_FILE" ]]; then
    local app_id
    app_id=$(create_app_id)
    output_login_url "$app_id"
  fi

  # 路径 3: .redInfo 存在但登录态无效或过期
  local app_id auth_data token state
  app_id=$(read_app_id_from_file)
  [[ -z "$app_id" ]] && app_id=$(get_or_create_app_id)

  auth_data=$(get_token_by_app_id "$app_id" 2>/dev/null) || output_login_url "$app_id"

  token=$(echo "$auth_data" | jq -r '.data.accessToken')
  exp=$(($(date +%s) * 1000 + 5 * 60 * 1000))
  state=$(echo "$auth_data" | jq --arg appId "$app_id" --argjson exp "$exp" '{
    appId: $appId,
    token: .data.accessToken,
    userInfo: .data.userInfo,
    exp: $exp
  }')
  save_auth_state "$state"
  echo "common-internal-access-token-prod=${token}"
}

main

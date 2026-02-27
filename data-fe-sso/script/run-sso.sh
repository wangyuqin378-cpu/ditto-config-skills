#!/usr/bin/env bash
#
# SSO 登录流程 Shell 脚本
# 用法: ./run-sso.sh <workspace>
# 必须传入 workspace 路径，登录态存于 {workspace}/.redInfo
#
# 三条路径：
# 1. .redInfo 存在且登录态有效 → 返回登录态
# 2. .redInfo 不存在 → 新建 appId 保存，提示访问 URL 登录
# 3. .redInfo 存在但登录态无效/过期 → 通过接口获取并存储；接口失败则提示访问 URL 登录
#
# 成功时输出: common-internal-access-token-prod={token}
# 需登录时输出登录 URL 到 stderr 并 exit 1
#

set -e

API_BASE_URL="https://fe-data.devops.xiaohongshu.com"
CREATE_APP_URL="${API_BASE_URL}/api/open/app"
GET_TOKEN_URL="${API_BASE_URL}/api/open/app/token"
LOGIN_PAGE_URL="${API_BASE_URL}/login"
APP_DESC="${APP_DESC:-XCodeBook}"

# 必须传入 workspace 路径
[[ -n "${1:-}" ]] || { echo "用法: $0 <workspace>" >&2; echo "必须传入 workspace 路径，登录态将存于 {workspace}/.redInfo" >&2; exit 1; }
BASE_DIR="$1"
AUTH_FILE="${BASE_DIR}/.redInfo"

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

main() {
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

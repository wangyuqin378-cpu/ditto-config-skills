#!/usr/bin/env bash
#
# 查询 Ditto 物料配置模块信息
#
# 用法:
#   bash query-module.sh <workspace> <config_id>             # 列出所有模块
#   bash query-module.sh <workspace> <config_id> <module_id> # 输出指定模块的 data JSON
#
# 无 module_id：每行输出 "<id>\t<name>"
# 有 module_id：stdout 输出该模块 data 字段的 JSON 字符串（可能是数组或对象）
#

set -euo pipefail

CONFIGSDK_MCP_URL="https://edithai.devops.xiaohongshu.com/mcp-servers/configsdk"
SSO_SCRIPT="$(dirname "$0")/../../data-fe-sso/script/run-sso.sh"

[[ $# -ge 2 ]] || { echo "用法: $0 <workspace> <config_id> [module_id]" >&2; exit 1; }
WORKSPACE="$1"
CONFIG_ID="$2"
MODULE_ID="${3:-}"

[[ -f "$SSO_SCRIPT" ]] || { echo "未找到 SSO 脚本: $SSO_SCRIPT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "需要安装 jq: brew install jq" >&2; exit 1; }

# 获取 SSO cookie
COOKIE=$("$SSO_SCRIPT" "$WORKSPACE" 2>/dev/null) || {
  echo "未登录，请先访问以下 URL 完成登录：" >&2
  "$SSO_SCRIPT" "$WORKSPACE" 2>&1 || true
  exit 1
}

# 查询配置
PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({
    'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call',
    'params': {
        'name': 'snsactivityconfig-queryMaterialInfo',
        'arguments': {'id': sys.argv[1], 'cookie': sys.argv[2]}
    }
}))" "$CONFIG_ID" "$COOKIE")

RESP=$(curl -s -X POST "$CONFIGSDK_MCP_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "cookie: $COOKIE" \
  -d "$PAYLOAD")

if [[ -z "$MODULE_ID" ]]; then
  # 列出所有模块
  echo "$RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
text = json.loads(d['result']['content'][0]['text'])
for m in text['material']['modules']:
    print(f\"{m['id']}\t{m['name']}\")
"
else
  # 输出指定模块的 data JSON
  echo "$RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
text = json.loads(d['result']['content'][0]['text'])
modules = text['material']['modules']
target = next((m for m in modules if str(m['id']) == sys.argv[1]), None)
if target is None:
    print(f'模块 {sys.argv[1]} 不存在', file=sys.stderr)
    sys.exit(1)
print(target.get('data', '[]'))
" "$MODULE_ID"
fi

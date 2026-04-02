#!/usr/bin/env bash
#
# 提交数据到 Ditto 物料配置指定模块
#
# 用法: bash submit-module.sh <workspace> <config_id> <module_id> <data_file> [draft|submit]
#
# data_file: 包含 JSON 数组的文件，由模型写入，内容为新模块数据
# draft（默认）: operationType=1，保存草稿
# submit:        operationType=2，提交审核
#
# 提交时自动包含全部模块，只有目标模块 data 被替换，其余原样保留
#

set -euo pipefail

CONFIGSDK_MCP_URL="https://edithai.devops.xiaohongshu.com/mcp-servers/configsdk"
SSO_SCRIPT="$(dirname "$0")/../../data-fe-sso/script/run-sso.sh"

[[ $# -ge 4 ]] || { echo "用法: $0 <workspace> <config_id> <module_id> <data_file> [draft|submit]" >&2; exit 1; }
WORKSPACE="$1"
CONFIG_ID="$2"
MODULE_ID="$3"
DATA_FILE="$4"
MODE="${5:-draft}"

[[ -f "$DATA_FILE" ]] || { echo "data_file 不存在: $DATA_FILE" >&2; exit 1; }
[[ -f "$SSO_SCRIPT" ]] || { echo "未找到 SSO 脚本: $SSO_SCRIPT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "需要安装 jq: brew install jq" >&2; exit 1; }

OPERATION_TYPE=1
[[ "$MODE" == "submit" ]] && OPERATION_TYPE=2

# 获取 SSO cookie
COOKIE=$("$SSO_SCRIPT" "$WORKSPACE" 2>/dev/null) || {
  echo "未登录，请先访问以下 URL 完成登录：" >&2
  "$SSO_SCRIPT" "$WORKSPACE" 2>&1 || true
  exit 1
}

# 查询所有模块
QUERY_PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({
    'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call',
    'params': {
        'name': 'snsactivityconfig-queryMaterialInfo',
        'arguments': {'id': sys.argv[1], 'cookie': sys.argv[2]}
    }
}))" "$CONFIG_ID" "$COOKIE")

QUERY_TMP=$(mktemp /tmp/query_resp_XXXXXX.json)
PAYLOAD_TMP=$(mktemp /tmp/submit_payload_XXXXXX.json)
trap 'rm -f "$QUERY_TMP" "$PAYLOAD_TMP"' EXIT

curl -s -X POST "$CONFIGSDK_MCP_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "cookie: $COOKIE" \
  -d "$QUERY_PAYLOAD" > "$QUERY_TMP"

# 构造提交 payload（目标模块替换，其余原样）
python3 - "$QUERY_TMP" "$DATA_FILE" "$CONFIG_ID" "$MODULE_ID" "$COOKIE" "$OPERATION_TYPE" "$PAYLOAD_TMP" <<'PYEOF'
import json, sys

query_file, data_file, config_id, module_id, cookie, operation_type, payload_file = sys.argv[1:]
operation_type = int(operation_type)

with open(query_file) as f:
    d = json.load(f)
text = json.loads(d['result']['content'][0]['text'])
modules = text['material']['modules']

# 验证目标模块存在
if not any(str(m['id']) == module_id for m in modules):
    print(f'模块 {module_id} 不存在', file=sys.stderr)
    print(f'可用模块: {[f"{m[\"id\"]} ({m[\"name\"]})" for m in modules]}', file=sys.stderr)
    sys.exit(1)

with open(data_file) as f:
    new_data = json.load(f)

submit_modules = []
for m in modules:
    if str(m['id']) == module_id:
        submit_modules.append({'id': m['id'], 'data': json.dumps(new_data, ensure_ascii=False)})
    else:
        submit_modules.append({'id': m['id'], 'data': m.get('data', '[]')})

payload = {
    'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call',
    'params': {
        'name': 'configsdk-submitMaterialData',
        'arguments': {
            'id': config_id,
            'modules': submit_modules,
            'operationType': operation_type,
            'cookie': cookie
        }
    }
}
with open(payload_file, 'w') as f:
    json.dump(payload, f, ensure_ascii=False)
PYEOF

SUBMIT_RESP=$(curl -s -X POST "$CONFIGSDK_MCP_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "cookie: $COOKIE" \
  -d "@$PAYLOAD_TMP")

SUCCESS=$(echo "$SUBMIT_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    text = json.loads(d['result']['content'][0]['text'])
    print('yes' if text.get('result', {}).get('success') else 'no')
except:
    print('no')
")

if [[ "$SUCCESS" == "yes" ]]; then
  ACTION="保存草稿"
  [[ "$MODE" == "submit" ]] && ACTION="提交审核"
  echo "完成！config_id=${CONFIG_ID} 模块 ${MODULE_ID} 已${ACTION}" >&2
else
  echo "提交失败，响应: $SUBMIT_RESP" >&2
  exit 1
fi

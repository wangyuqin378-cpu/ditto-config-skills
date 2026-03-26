#!/usr/bin/env bash
#
# 存储并验证 porch_beaker_session_id 到 .redInfo
#
# 用法: ./set-porch-session.sh <workspace> <porch_session_value>
#
# porch_beaker_session_id 是 fe.devops.xiaohongshu.com 的浏览器 session，
# 无法自动获取，需在浏览器 Network 请求中手动复制后存入。
#
# 成功时输出成功信息并 exit 0
# 失败时输出错误信息并 exit 1

set -euo pipefail

UPLOAD_URL="https://fe.devops.xiaohongshu.com/api/oss/fe-platform/upload"

[[ $# -ge 2 ]] || { echo "用法: $0 <workspace> <porch_session_value>" >&2; exit 1; }

BASE_DIR="$1"
PORCH_SESSION="$2"
AUTH_FILE="${BASE_DIR}/.redInfo"

command -v jq >/dev/null 2>&1 || { echo "需要安装 jq: brew install jq" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "需要 python3" >&2; exit 1; }

# 验证 porch session：上传一个 1px PNG 测试
echo "验证 porch session..." >&2

# 生成 1x1 像素透明 PNG（base64 编码的最小 PNG）
TEST_IMG=$(mktemp /tmp/test_porch_XXXXXX.png)
python3 -c "
import base64, sys
# 最小 1x1 透明 PNG
data = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==')
sys.stdout.buffer.write(data)
" > "$TEST_IMG"

RESP=$(curl -s -X POST "$UPLOAD_URL" \
  -H "cookie: porch_beaker_session_id=${PORCH_SESSION}" \
  -F "file=@${TEST_IMG}" 2>/dev/null)
rm -f "$TEST_IMG"

if echo "$RESP" | grep -q 'Unauthorized\|redirectUrl\|401\|403'; then
  echo "porch session 无效，请重新从浏览器 Network 中复制 porch_beaker_session_id" >&2
  exit 1
fi

CDN_URL=$(python3 -c "
import json, sys
try:
    d = json.loads('$( echo "$RESP" | sed "s/'/\\\\'/g" )')
    url = d.get('data', {}).get('url') or d.get('url') or ''
    print(url if isinstance(url, str) and url.startswith('http') else '')
except:
    print('')
" 2>/dev/null)

if [[ -z "$CDN_URL" ]]; then
  echo "porch session 验证失败，上传响应: $RESP" >&2
  exit 1
fi

echo "  验证成功，测试图片: $CDN_URL" >&2

# 计算过期时间（7天后，毫秒）
PORCH_EXP=$(python3 -c "import time; print(int((time.time() + 7*24*3600) * 1000))")

# 合并写入 .redInfo（保留已有 SSO 字段）
mkdir -p "$BASE_DIR"

if [[ -f "$AUTH_FILE" ]]; then
  # 保留已有内容，更新 porchSession 和 porchSessionExp
  jq --arg ps "$PORCH_SESSION" --argjson exp "$PORCH_EXP" \
    '. + {porchSession: $ps, porchSessionExp: $exp}' \
    "$AUTH_FILE" > "${AUTH_FILE}.tmp" && mv "${AUTH_FILE}.tmp" "$AUTH_FILE"
else
  jq -n --arg ps "$PORCH_SESSION" --argjson exp "$PORCH_EXP" \
    '{porchSession: $ps, porchSessionExp: $exp}' > "$AUTH_FILE"
fi

echo "porch session 已保存到 ${AUTH_FILE}，有效期 7 天" >&2

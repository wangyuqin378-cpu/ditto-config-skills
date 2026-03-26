#!/usr/bin/env bash
#
# 上传单张图片到 fe-platform CDN
#
# 用法: bash upload-image.sh <workspace> <file_path>
#
# 成功时 stdout 输出: <url> <width> <height>
# 失败时 exit 1
#

set -euo pipefail

UPLOAD_URL="https://fe.devops.xiaohongshu.com/api/oss/fe-platform/upload"
SSO_SCRIPT="$(dirname "$0")/../../data-fe-sso/script/run-sso.sh"

[[ $# -ge 2 ]] || { echo "用法: $0 <workspace> <file_path>" >&2; exit 1; }
WORKSPACE="$1"
FILE="$2"

[[ -f "$FILE" ]] || { echo "文件不存在: $FILE" >&2; exit 1; }
[[ -f "$SSO_SCRIPT" ]] || { echo "未找到 SSO 脚本: $SSO_SCRIPT" >&2; exit 1; }

# 获取 porch session
PORCH_COOKIE=$("$SSO_SCRIPT" "$WORKSPACE" --porch 2>/dev/null) || {
  echo "图片上传需要 porch_beaker_session_id，请运行：" >&2
  echo "  bash $(dirname "$SSO_SCRIPT")/set-porch-session.sh $WORKSPACE <porch_beaker_session_id>" >&2
  echo "在浏览器 fe.devops.xiaohongshu.com 的 Network 请求中复制 porch_beaker_session_id" >&2
  exit 1
}

# 上传
RESP=$(curl -s -X POST "$UPLOAD_URL" \
  -H "cookie: $PORCH_COOKIE" \
  -F "file=@${FILE}" 2>/dev/null)

if echo "$RESP" | grep -q 'Unauthorized\|redirectUrl'; then
  echo "porch session 已失效，请重新运行 set-porch-session.sh" >&2
  exit 1
fi

URL=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    url = d.get('data', {}).get('url') or d.get('url') or ''
    print(url if isinstance(url, str) and url.startswith('http') else '')
except:
    print('')
" "$RESP" 2>/dev/null)

[[ -n "$URL" ]] || { echo "上传失败，响应: $RESP" >&2; exit 1; }

# 解析图片尺寸
SIZE=$(python3 - "$FILE" <<'PYEOF'
import sys, struct

def get_size(path):
    with open(path, 'rb') as f:
        header = f.read(24)
    if header[:8] == b'\x89PNG\r\n\x1a\n':
        w, h = struct.unpack('>II', header[16:24])
        return w, h
    if header[:2] == b'\xff\xd8':
        with open(path, 'rb') as f:
            data = f.read()
        i = 2
        while i < len(data):
            if data[i] != 0xff:
                break
            marker = data[i+1]
            if marker in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack('>HH', data[i+5:i+9])
                return w, h
            length = struct.unpack('>H', data[i+2:i+4])[0]
            i += 2 + length
    if header[:6] in (b'GIF87a', b'GIF89a'):
        w, h = struct.unpack('<HH', header[6:10])
        return w, h
    return 1023, 1023

w, h = get_size(sys.argv[1])
print(f"{w} {h}")
PYEOF
)

W=$(echo "$SIZE" | cut -d' ' -f1)
H=$(echo "$SIZE" | cut -d' ' -f2)

echo "$URL $W $H"

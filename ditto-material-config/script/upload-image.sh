#!/usr/bin/env bash
#
# 上传单张图片到 xhscdn CDN（via edith permit + COS PUT）
#
# 用法: bash upload-image.sh <workspace> <file_path>
#
# 成功时 stdout 输出: <url> <width> <height>
# 失败时 exit 1
#

set -euo pipefail

[[ $# -ge 2 ]] || { echo "用法: $0 <workspace> <file_path>" >&2; exit 1; }
WORKSPACE="$1"
FILE="$2"

[[ -f "$FILE" ]] || { echo "文件不存在: $FILE" >&2; exit 1; }

# 获取登录态
AUTH_FILE="${WORKSPACE}/.redInfo"
[[ -f "$AUTH_FILE" ]] || { echo "错误: 未找到登录态文件 $AUTH_FILE" >&2; exit 1; }

TOKEN_VAL=$(jq -r '.token // empty' "$AUTH_FILE" 2>/dev/null)
EXP_VAL=$(jq -r '.exp // 0' "$AUTH_FILE" 2>/dev/null)
NOW_VAL=$(date +%s)

[[ -n "$TOKEN_VAL" ]] || { echo "错误: 登录态文件无效，请重新登录" >&2; exit 1; }
[[ "$NOW_VAL" -lt "$EXP_VAL" ]] || { echo "错误: 登录态已过期，请重新登录" >&2; exit 1; }

COOKIE="common-internal-access-token-prod=${TOKEN_VAL}"

# Content-Type
EXT="${FILE##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
case "$EXT_LOWER" in
  jpg|jpeg) CONTENT_TYPE="image/jpeg" ;;
  png)      CONTENT_TYPE="image/png" ;;
  gif)      CONTENT_TYPE="image/gif" ;;
  webp)     CONTENT_TYPE="image/webp" ;;
  *)        CONTENT_TYPE="image/jpeg" ;;
esac

# Step 1: 获取上传 permit
PERMIT_RESP=$(curl -s \
  "https://edith.xiaohongshu.com/api/media/v1/upload/web/permit?biz_name=fe&file_count=1&scene=platform&version=1" \
  -H "Cookie: $COOKIE" \
  -H "Accept: application/json" \
  -H "Referer: https://fe.devops.xiaohongshu.com/" \
  -H "Origin: https://fe.devops.xiaohongshu.com")

TOKEN=$(echo "$PERMIT_RESP" | jq -r '.data.uploadTempPermits[0].token')
FILE_ID=$(echo "$PERMIT_RESP" | jq -r '.data.uploadTempPermits[0].fileIds[0]')
UPLOAD_ADDR=$(echo "$PERMIT_RESP" | jq -r '.data.uploadTempPermits[0].uploadAddr')
UPLOAD_ID=$(echo "$PERMIT_RESP" | jq -r '.data.uploadTempPermits[0].uploadId')

[[ -n "$TOKEN" && "$TOKEN" != "null" ]] || { echo "错误: 获取 permit 失败: $PERMIT_RESP" >&2; exit 1; }

case "$UPLOAD_ADDR" in
  *xiaohongshu.com*) ;;
  *) echo "错误: 非法上传地址: $UPLOAD_ADDR" >&2; exit 1 ;;
esac

UPLOAD_URL="https://${UPLOAD_ADDR}/${FILE_ID}"

# Step 2: PUT 上传到 COS
UPLOAD_RESULT=$(python3 - <<PYEOF
import urllib.request, sys

url = "$UPLOAD_URL"
token = "$TOKEN"
content_type = "$CONTENT_TYPE"
image_path = "$FILE"

with open(image_path, 'rb') as f:
    data = f.read()

req = urllib.request.Request(url, data=data, method='PUT')
req.add_header('x-cos-security-token', token)
req.add_header('Content-Type', content_type)
req.add_header('Content-Length', str(len(data)))
req.add_header('Origin', 'https://fe.devops.xiaohongshu.com')
req.add_header('Referer', 'https://fe.devops.xiaohongshu.com/')

try:
    resp = urllib.request.urlopen(req)
    cdn_url = resp.headers.get('x-ros-static-url', '')
    print(f"{resp.status}|{cdn_url}")
except urllib.error.HTTPError as e:
    print(f"{e.code}|", file=sys.stderr)
    sys.exit(1)
PYEOF
)

HTTP_CODE=$(echo "$UPLOAD_RESULT" | cut -d'|' -f1)
URL=$(echo "$UPLOAD_RESULT" | cut -d'|' -f2 | tr -d '\r\n')

[[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "204" ]] || { echo "错误: 上传失败 (HTTP $HTTP_CODE)" >&2; exit 1; }

[[ -n "$URL" ]] || URL="https://fe-platform.xhscdn.com/${FILE_ID}"

# 记录历史（可选）
curl -s -X POST "https://fe.devops.xiaohongshu.com/api/uploader/histroy" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -H "Referer: https://fe.devops.xiaohongshu.com/" \
  -d "{\"url\":\"$URL\",\"uploadId\":$UPLOAD_ID}" -o /dev/null 2>/dev/null || true

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

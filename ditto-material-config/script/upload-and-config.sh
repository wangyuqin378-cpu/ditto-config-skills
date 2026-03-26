#!/usr/bin/env bash
#
# 上传图片并配置到 configsdk 物料平台
#
# 用法:
#   # 模式一：从图片目录批量上传，自动构造测试植物数据
#   ./upload-and-config.sh <workspace> <config_id> <module_id> --images <image_dir> [draft|submit]
#
#   # 模式二：Excel 定义植物属性，图片列为文件名，在 image_dir 中按文件名匹配并上传
#   ./upload-and-config.sh <workspace> <config_id> <module_id> --excel <xlsx_file> <image_dir> [draft|submit]
#
# Excel 列格式（第一行为表头）:
#   植物id | 植物名称 | 植物类型 | 价格 | 植物图片(文件名，如 杉树.png，留空则无图片)
#
# 依赖: jq, python3, curl, openpyxl（pip3 install openpyxl）
# 认证: 依赖 data-fe-sso skill 获取登录态
#

set -euo pipefail

CONFIGSDK_MCP_URL="https://edithai.devops.xiaohongshu.com/mcp-servers/configsdk"
UPLOAD_URL="https://fe.devops.xiaohongshu.com/api/oss/fe-platform/upload"
SSO_SCRIPT="$(dirname "$0")/../../data-fe-sso/script/run-sso.sh"

# ── 参数校验 ──────────────────────────────────────────────────────────────────
usage() {
  echo "用法:" >&2
  echo "  $0 <workspace> <config_id> <module_id> --images <image_dir> [draft|submit]" >&2
  echo "  $0 <workspace> <config_id> <module_id> --excel <xlsx_file> <image_dir> [draft|submit]" >&2
  exit 1
}

[[ $# -ge 5 ]] || usage
WORKSPACE="$1"
CONFIG_ID="$2"
MODULE_ID="$3"
INPUT_TYPE="$4"   # --images 或 --excel
[[ "$INPUT_TYPE" == "--images" || "$INPUT_TYPE" == "--excel" ]] || usage

# 根据模式解析后续参数
if [[ "$INPUT_TYPE" == "--images" ]]; then
  INPUT_PATH="$5"
  MODE="${6:-draft}"
elif [[ "$INPUT_TYPE" == "--excel" ]]; then
  [[ $# -ge 6 ]] || usage
  EXCEL_FILE="$5"
  IMAGE_DIR="$6"
  MODE="${7:-draft}"
fi

OPERATION_TYPE=1
[[ "$MODE" == "submit" ]] && OPERATION_TYPE=2
[[ -f "$SSO_SCRIPT" ]] || { echo "未找到 SSO 脚本: $SSO_SCRIPT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "需要安装 jq: brew install jq" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "需要 python3" >&2; exit 1; }

# ── 获取 SSO Cookie（用于 configsdk MCP） ────────────────────────────────────
echo "[1] 获取登录态..." >&2
COOKIE_VALUE=$("$SSO_SCRIPT" "$WORKSPACE" 2>/dev/null) || {
  echo "未登录，请先访问以下 URL 完成登录：" >&2
  "$SSO_SCRIPT" "$WORKSPACE" 2>&1 || true
  exit 1
}
echo "  SSO 登录态有效" >&2

# ── 获取 porch session（用于图片上传） ────────────────────────────────────────
PORCH_COOKIE=$("$SSO_SCRIPT" "$WORKSPACE" --porch 2>/dev/null) || {
  echo "" >&2
  echo "图片上传需要 porch_beaker_session_id，请运行：" >&2
  echo "  bash $(dirname "$SSO_SCRIPT")/set-porch-session.sh $WORKSPACE <porch_beaker_session_id>" >&2
  echo "" >&2
  echo "获取方式：在浏览器打开 fe.devops.xiaohongshu.com，打开 DevTools → Network，" >&2
  echo "找到任意请求，在 Request Headers 中复制 porch_beaker_session_id 的值" >&2
  exit 1
}
echo "  porch session 有效" >&2

# ── 工具函数 ──────────────────────────────────────────────────────────────────

# 获取图片尺寸（本地文件）
get_image_size() {
  python3 - "$1" <<'PYEOF'
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
}

# 获取图片尺寸（URL）
get_image_size_from_url() {
  python3 - "$1" <<'PYEOF'
import sys, struct, urllib.request

def get_size_from_url(url):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=10) as r:
            header = r.read(24)
        if header[:8] == b'\x89PNG\r\n\x1a\n':
            w, h = struct.unpack('>II', header[16:24])
            return w, h
        if header[:2] == b'\xff\xd8':
            req2 = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req2, timeout=10) as r:
                data = r.read()
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
    except:
        pass
    return 1023, 1023

w, h = get_size_from_url(sys.argv[1])
print(f"{w} {h}")
PYEOF
}

# 上传本地图片，返回 CDN URL
upload_image() {
  local img="$1"
  local resp
  resp=$(curl -s -X POST "$UPLOAD_URL" \
    -H "cookie: $PORCH_COOKIE" \
    -F "file=@${img}" 2>/dev/null)

  if echo "$resp" | grep -q 'Unauthorized\|redirectUrl'; then
    echo "登录态失效，请重新登录" >&2
    exit 1
  fi

  python3 -c "
import sys, json
try:
    d = json.loads('$(echo "$resp" | sed "s/'/\\\\\'/g")')
    url = d.get('data', {}).get('url') or d.get('url') or d.get('data', '')
    if isinstance(url, str) and url.startswith('http'):
        print(url)
    else:
        print('')
except:
    print('')
" 2>/dev/null
}

# ── 构造植物数据条目 ───────────────────────────────────────────────────────────
make_plant_json() {
  # 参数: plant_id plant_name category price image_url image_width image_height
  python3 - "$@" <<'PYEOF'
import sys, json

plant_id   = sys.argv[1]
plant_name = sys.argv[2]
category   = int(sys.argv[3]) if sys.argv[3] else 2
price      = int(sys.argv[4]) if sys.argv[4] else 10
img_url    = sys.argv[5] if len(sys.argv) > 5 else ""
img_w      = int(sys.argv[6]) if len(sys.argv) > 6 and sys.argv[6] else 1023
img_h      = int(sys.argv[7]) if len(sys.argv) > 7 and sys.argv[7] else 1023

plant_image = {"url": img_url, "width": img_w, "height": img_h} if img_url else None

plant = {
    "price": price,
    "plantId": plant_id,
    "canBloom": False,
    "category": category,
    "plantName": plant_name,
    "bloomCycle": 2,
    "bloomInfos": [],
    "plantImage": plant_image,
    "plantDetail": json.dumps({
        "plant_id": plant_id,
        "plant_name": plant_name,
        "category": "TREES",
        "occupy_size": 5,
        "tag": "锚点",
        "environment": "非水生",
        "growth_phases": ["常态"],
        "default_phase": "常态",
        "color_variants": [{
            "color_id": "default",
            "display_name": plant_name,
            "phase": "常态",
            "bloom_id": f"{plant_id}_1"
        }],
        "can_wither": False,
        "rarity": "普通",
        "plant_offset_y": 0.42,
        "visual_assets": {"常态": {"default": {"normal": ""}}},
        "is_active": True,
        "can_bloom": False,
        "price": price
    }, ensure_ascii=False),
    "lackWaterCycle": 10,
    "plantClearImage": None
}
print(json.dumps(plant, ensure_ascii=False))
PYEOF
}

# ── 模式一：从图片目录批量上传 ─────────────────────────────────────────────────
if [[ "$INPUT_TYPE" == "--images" ]]; then
  [[ -d "$INPUT_PATH" ]] || { echo "图片目录不存在: $INPUT_PATH" >&2; exit 1; }

  echo "[2] 上传图片..." >&2
  declare -a PLANTS=()
  shopt -s nullglob
  IMAGE_FILES=("$INPUT_PATH"/*.{jpg,jpeg,png,gif,webp,JPG,JPEG,PNG,GIF,WEBP})
  [[ ${#IMAGE_FILES[@]} -gt 0 ]] || { echo "目录中没有图片: $INPUT_PATH" >&2; exit 1; }

  i=1
  for img in "${IMAGE_FILES[@]}"; do
    filename=$(basename "$img")
    echo "  上传: $filename" >&2

    url=$(upload_image "$img")
    [[ -n "$url" ]] || { echo "  上传失败: $filename" >&2; exit 1; }

    size=$(get_image_size "$img")
    w=$(echo "$size" | cut -d' ' -f1)
    h=$(echo "$size" | cut -d' ' -f2)
    echo "  -> $url (${w}x${h})" >&2

    plant_id="TEST_PLANT_$(printf '%04d' $i)"
    plant_name="测试植物${i}"
    plant=$(make_plant_json "$plant_id" "$plant_name" "2" "10" "$url" "$w" "$h")
    PLANTS+=("$plant")
    ((i++))
  done

# ── 模式二：Excel + 图片目录（按文件名匹配）──────────────────────────────────────
elif [[ "$INPUT_TYPE" == "--excel" ]]; then
  [[ -f "$EXCEL_FILE" ]] || { echo "Excel 文件不存在: $EXCEL_FILE" >&2; exit 1; }
  [[ -d "$IMAGE_DIR" ]] || { echo "图片目录不存在: $IMAGE_DIR" >&2; exit 1; }

  python3 -c "import openpyxl" 2>/dev/null || {
    echo "需要安装 openpyxl: pip3 install openpyxl" >&2; exit 1
  }

  echo "[2] 读取 Excel 并匹配图片..." >&2

  # 用 Python 完整处理 Excel 解析 + 图片上传 + 构造 plants JSON
  # 上传通过 curl 子进程完成，结果写入临时文件
  EXCEL_PLANTS_TMP=$(mktemp /tmp/excel_plants_XXXXXX.json)

  python3 - "$EXCEL_FILE" "$IMAGE_DIR" "$UPLOAD_URL" "$PORCH_COOKIE" "$EXCEL_PLANTS_TMP" <<'PYEOF'
import sys, json, struct, subprocess, os

excel_file = sys.argv[1]
image_dir  = sys.argv[2]
upload_url = sys.argv[3]
cookie     = sys.argv[4]
out_file   = sys.argv[5]

import openpyxl
wb = openpyxl.load_workbook(excel_file)
ws = wb.active

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
            if data[i] != 0xff: break
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

def upload(img_path):
    result = subprocess.run([
        'curl', '-s', '-X', 'POST', upload_url,
        '-H', f'cookie: {cookie}',
        '-F', f'file=@{img_path}'
    ], capture_output=True, text=True)
    try:
        d = json.loads(result.stdout)
        url = d.get('data', {}).get('url') or d.get('url') or d.get('data', '')
        if isinstance(url, str) and url.startswith('http'):
            return url
    except:
        pass
    return ''

plants = []
for row in ws.iter_rows(min_row=2, values_only=True):
    if not any(row):
        continue
    plant_id   = str(row[0] or '')
    plant_name = str(row[1] or '')
    category   = int(row[2]) if row[2] else 2
    price      = int(row[3]) if row[3] else 10
    image_val  = str(row[4] or '')

    if not plant_id:
        continue

    print(f'  处理: {plant_id} ({plant_name})', file=sys.stderr)

    img_url, img_w, img_h = '', 1023, 1023
    if image_val:
        img_path = os.path.join(image_dir, image_val)
        if os.path.isfile(img_path):
            print(f'    匹配到图片: {image_val}，上传中...', file=sys.stderr)
            img_url = upload(img_path)
            if img_url:
                img_w, img_h = get_size(img_path)
                print(f'    -> {img_url} ({img_w}x{img_h})', file=sys.stderr)
            else:
                print(f'    上传失败: {image_val}', file=sys.stderr)
                sys.exit(1)
        else:
            print(f'    警告: 未找到文件 "{image_val}"，plantImage 将为 null', file=sys.stderr)

    plant_image = {'url': img_url, 'width': img_w, 'height': img_h} if img_url else None
    plants.append({
        'price': price,
        'plantId': plant_id,
        'canBloom': False,
        'category': category,
        'plantName': plant_name,
        'bloomCycle': 2,
        'bloomInfos': [],
        'plantImage': plant_image,
        'plantDetail': json.dumps({
            'plant_id': plant_id, 'plant_name': plant_name,
            'category': 'TREES', 'occupy_size': 5, 'tag': '锚点',
            'environment': '非水生', 'growth_phases': ['常态'],
            'default_phase': '常态',
            'color_variants': [{'color_id': 'default', 'display_name': plant_name,
                                 'phase': '常态', 'bloom_id': f'{plant_id}_1'}],
            'can_wither': False, 'rarity': '普通', 'plant_offset_y': 0.42,
            'visual_assets': {'常态': {'default': {'normal': ''}}},
            'is_active': True, 'can_bloom': False, 'price': price
        }, ensure_ascii=False),
        'lackWaterCycle': 10,
        'plantClearImage': None
    })

with open(out_file, 'w') as f:
    json.dump(plants, f, ensure_ascii=False)
print(f'  共 {len(plants)} 条植物数据', file=sys.stderr)
PYEOF

  # 从临时文件读取 plants，转成每行一条 JSON 供后续统一处理
  declare -a PLANTS=()
  while IFS= read -r line; do
    PLANTS+=("$line")
  done < <(python3 -c "
import json, sys
plants = json.load(open('$EXCEL_PLANTS_TMP'))
for p in plants:
    print(json.dumps(p, ensure_ascii=False))
")
  rm -f "$EXCEL_PLANTS_TMP"
fi

echo "  共 ${#PLANTS[@]} 条植物数据" >&2

# ── 查询物料配置 ────────────────────────────────────────────────────────────────
echo "[3] 查询配置 id=${CONFIG_ID}..." >&2

QUERY_PAYLOAD=$(python3 - <<PYEOF
import json
print(json.dumps({
    "jsonrpc": "2.0", "id": 1, "method": "tools/call",
    "params": {
        "name": "snsactivityconfig-queryMaterialInfo",
        "arguments": {"id": "${CONFIG_ID}", "cookie": "${COOKIE_VALUE}"}
    }
}))
PYEOF
)

MATERIAL_RESP=$(curl -s -X POST "$CONFIGSDK_MCP_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "cookie: $COOKIE_VALUE" \
  -d "$QUERY_PAYLOAD")

MODULES_JSON=$(echo "$MATERIAL_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
text = json.loads(d['result']['content'][0]['text'])
print(json.dumps(text['material']['modules']))
")

echo "  模块列表:" >&2
echo "$MODULES_JSON" | python3 -c "
import sys, json
for m in json.loads(sys.stdin.read()):
    print(f\"    ID={m['id']} 名称={m['name']}\")
" >&2

TARGET_EXISTS=$(echo "$MODULES_JSON" | python3 -c "
import sys, json
found = any(m['id'] == '${MODULE_ID}' for m in json.loads(sys.stdin.read()))
print('yes' if found else 'no')
")
[[ "$TARGET_EXISTS" == "yes" ]] || { echo "  模块 ${MODULE_ID} 不存在" >&2; exit 1; }

# ── 提交配置 ──────────────────────────────────────────────────────────────────
echo "[4] 提交配置 (${MODE})..." >&2

# 将 PLANTS 数组写入临时文件（避免 shell heredoc 插值破坏 JSON）
PLANTS_TMP=$(mktemp /tmp/plants_XXXXXX.json)
MODULES_TMP=$(mktemp /tmp/modules_XXXXXX.json)
PAYLOAD_TMP=$(mktemp /tmp/payload_XXXXXX.json)
trap 'rm -f "$PLANTS_TMP" "$MODULES_TMP" "$PAYLOAD_TMP"' EXIT

printf '%s\n' "${PLANTS[@]}" > "$PLANTS_TMP"
echo "$MODULES_JSON" > "$MODULES_TMP"

python3 - "$PLANTS_TMP" "$MODULES_TMP" "$PAYLOAD_TMP" \
  "$COOKIE_VALUE" "$CONFIG_ID" "$MODULE_ID" "$OPERATION_TYPE" <<'PYEOF'
import json, sys

plants_file, modules_file, payload_file = sys.argv[1], sys.argv[2], sys.argv[3]
cookie, config_id, module_id = sys.argv[4], sys.argv[5], sys.argv[6]
operation_type = int(sys.argv[7])

with open(plants_file) as f:
    plants = [json.loads(line) for line in f if line.strip()]

with open(modules_file) as f:
    modules_json = json.load(f)

submit_modules = []
for m in modules_json:
    if m["id"] == module_id:
        submit_modules.append({"id": m["id"], "data": json.dumps(plants, ensure_ascii=False)})
    else:
        submit_modules.append({"id": m["id"], "data": m["data"]})

payload = {
    "jsonrpc": "2.0", "id": 1, "method": "tools/call",
    "params": {
        "name": "configsdk-submitMaterialData",
        "arguments": {
            "id": config_id,
            "modules": submit_modules,
            "operationType": operation_type,
            "cookie": cookie
        }
    }
}
with open(payload_file, 'w') as f:
    json.dump(payload, f, ensure_ascii=False)
PYEOF

SUBMIT_PAYLOAD=$(cat "$PAYLOAD_TMP")

SUBMIT_RESP=$(curl -s -X POST "$CONFIGSDK_MCP_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "cookie: $COOKIE_VALUE" \
  -d "$SUBMIT_PAYLOAD")

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
  [[ "$MODE" == "submit" ]] && ACTION="提交审核" || ACTION="保存草稿"
  echo "" >&2
  echo "完成！配置 id=${CONFIG_ID} 模块 ${MODULE_ID} 已${ACTION}，共 ${#PLANTS[@]} 条植物数据" >&2
  exit 0
else
  echo "提交失败，响应: $SUBMIT_RESP" >&2
  exit 1
fi

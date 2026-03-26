---
name: configsdk-plant-image
description: >
  小红书内部 configsdk 物料配置助手：将本地图片或 Excel 批量配置到「物料配置平台」指定模块的植物图片字段。
  支持通过 ditto 配置页链接（如 https://ditto.devops.xiaohongshu.com/ditto-dataconfig-center/data-configuration/preview/699）或直接提供 config_id 启动。
  当用户说「帮我配置植物图片」「把图片上传到配置」「更新物料模块的图片」「ditto 配置页链接 + 上传/配置」时触发本 skill。
allowed-tools:
  - Bash
---

# configsdk-plant-image

## 何时触发

- 用户提供 ditto 配置页链接并提到「上传」「配置」「图片」
- 用户说「帮我配置植物图片」「把图片配到某个模块」「从 Excel 更新植物数据」
- 用户提供 config_id / module_id 并提到图片上传或物料配置

**不触发**：仅查询配置内容、仅浏览模块信息

---

## 模型交互流程

### 第一步：获取 config_id 和 module_id

**方式一：用户提供 ditto 链接**

从 URL 中解析 config_id，例如：
```
https://ditto.devops.xiaohongshu.com/ditto-dataconfig-center/data-configuration/preview/699
                                                                                         ^^^
                                                                                     config_id = 699
```

**方式二：用户直接提供 config_id**

直接使用。

拿到 config_id 后，通过 configsdk MCP 查询配置，列出所有模块供用户选择：

```bash
curl -s -X POST "https://edithai.devops.xiaohongshu.com/mcp-servers/configsdk" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "cookie: <SSO_COOKIE>" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"snsactivityconfig-queryMaterialInfo","arguments":{"id":"<config_id>","cookie":"<SSO_COOKIE>"}}}'
```

展示模块列表，询问用户选择哪个模块作为目标（module_id）。

### 第二步：获取数据来源

询问用户使用哪种方式：

**方式 A：图片目录**
- 获取本地图片目录路径
- 脚本批量上传目录下所有图片（jpg/png/gif/webp），自动构造植物数据（plantId = `TEST_PLANT_000N`）

**方式 B：Excel + 图片目录**
- 获取 Excel 文件路径（`.xlsx`）和图片目录路径
- Excel 定义植物属性，「植物图片」列填写**文件名**（如 `杉树.png`），脚本在图片目录中按文件名匹配并上传

### 第三步：确认参数后执行

展示汇总参数，确认后调用脚本：

```bash
bash /path/to/data-fe-skills/configsdk-plant-image/script/upload-and-config.sh \
  <workspace> <config_id> <module_id> \
  --images <image_dir> \        # 方式 A
  # 或
  --excel <xlsx_file> <image_dir> \  # 方式 B
  [draft|submit]
```

默认保存草稿（`draft`），需要提交审核时使用 `submit`。

---

## 脚本参数说明

| 参数 | 说明 |
|------|------|
| `workspace` | 工作区路径，SSO 登录态存于 `{workspace}/.redInfo` |
| `config_id` | 物料配置 ID |
| `module_id` | 目标模块 ID，**仅此模块会被修改，其余模块原样保留** |
| `--images <dir>` | 图片目录模式 |
| `--excel <xlsx> <dir>` | Excel + 图片目录模式，图片列为文件名，在 dir 中匹配 |
| `draft` / `submit` | 保存草稿（默认）或提交审核 |

---

## Excel 格式

第一行为表头，列顺序固定：

| 列 | 字段 | 必填 | 说明 |
|----|------|------|------|
| A | 植物id | 是 | 如 `PLANT_2001` |
| B | 植物名称 | 是 | 如 `杉树` |
| C | 植物类型 | 否 | 数字，默认 `2` |
| D | 价格 | 否 | 数字，默认 `10` |
| E | 植物图片 | 否 | 文件名（如 `杉树.png`），在图片目录中匹配；留空则 plantImage 为 null |

---

## 前置依赖

脚本依赖两套认证：

| 认证 | 用途 | 获取方式 |
|------|------|---------|
| SSO token (`common-internal-access-token-prod`) | configsdk MCP 查询/提交 | `data-fe-sso/script/run-sso.sh <workspace>` 自动获取 |
| porch session (`porch_beaker_session_id`) | 图片上传到 fe.devops | 需手动从浏览器复制，运行 `data-fe-sso/script/set-porch-session.sh <workspace> <value>` 存储 |

**首次使用前必须先存储 porch session**，否则图片上传会报错。

---

## 脚本执行流程

1. **SSO**：调用 `data-fe-sso/script/run-sso.sh <workspace>`，失败时输出登录 URL 并退出
2. **porch session**：调用 `run-sso.sh <workspace> --porch`，失败时提示运行 `set-porch-session.sh` 并退出
3. **准备数据**：
   - `--images`：逐张上传，从文件头解析尺寸（PNG/JPEG/GIF，fallback 1023×1023）
   - `--excel <xlsx> <dir>`：解析表格，按「植物图片」列的文件名在 dir 中查找并上传；找不到则 plantImage 为 null
4. **查询配置**：MCP 读取 config_id 的所有模块数据
5. **写入**：目标模块替换为新数据，其余模块原样提交
6. **提交**：`draft` → operationType=1；`submit` → operationType=2

---

## 关键接口

| 用途 | 值 |
|------|----|
| 图片上传 | `POST https://fe.devops.xiaohongshu.com/api/oss/fe-platform/upload` |
| configsdk MCP | `https://edithai.devops.xiaohongshu.com/mcp-servers/configsdk` |
| 查询配置 | `snsactivityconfig-queryMaterialInfo` |
| 提交配置 | `configsdk-submitMaterialData` |
| SSO | `data-fe-sso/script/run-sso.sh <workspace>` |

---

## 注意事项

- 提交时必须包含**全部模块**，否则其他模块数据会丢失（脚本已自动处理）
- 配置非草稿态时 `draft` 会报错，需改用 `submit`
- SSO 登录态失效时脚本输出登录 URL 并 exit 1，提示用户登录后重试
- porch session 失效时 exit 1，提示运行 `set-porch-session.sh` 更新
- config_id 可从 ditto 链接末尾的数字提取

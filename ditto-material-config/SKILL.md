---
name: ditto-material-config
description: >
  小红书内部 Ditto 数据配置中心物料配置助手：将本地图片或 Excel 批量写入指定模块。
  支持通过 ditto 配置页链接（如 https://ditto.devops.xiaohongshu.com/ditto-dataconfig-center/data-configuration/preview/699）或直接提供 config_id 启动。
  当用户说「帮我配置物料」「更新模块数据」「把图片/Excel 上传到 ditto 配置」「ditto 配置页链接 + 上传/配置/更新」时触发本 skill。
allowed-tools:
  - Bash
---

# ditto-material-config

## 何时触发

- 用户提供 ditto 配置页链接并提到「上传」「配置」「更新」
- 用户说「帮我配置物料」「更新模块数据」「把图片/Excel 写入 ditto」
- 用户提供 config_id / module_id 并提到图片上传或物料配置

**不触发**：仅查询配置内容、仅浏览模块信息

---

## 前置依赖

依赖两套认证，均存储在 `{workspace}/.redInfo`：

| 认证 | 用途 | 获取方式 |
|------|------|---------|
| SSO token | configsdk MCP 查询/提交 | `run-sso.sh <workspace>` 自动获取 |
| porch session | 图片上传到 fe.devops | 手动从浏览器复制，运行 `set-porch-session.sh <workspace> <value>` 存储，有效期约 7 天 |

**首次使用必须先存储 porch session。**

---

## 模型交互流程

### 第一步：获取 config_id

**方式一：用户提供 ditto 链接**

从 URL 末尾提取数字作为 config_id：
```
https://ditto.devops.xiaohongshu.com/ditto-dataconfig-center/data-configuration/preview/699
                                                                                         ^^^
                                                                                    config_id = 699
```

**方式二：用户直接提供 config_id**

直接使用。

---

### 第二步：查询并选择目标模块

```bash
bash <skill_dir>/script/query-module.sh <workspace> <config_id>
```

输出所有模块（`id\tname`），展示给用户，由用户选择目标 `module_id`。

---

### 第三步：读取模块现有数据，理解结构

```bash
bash <skill_dir>/script/query-module.sh <workspace> <config_id> <module_id>
```

stdout 输出该模块 `data` 字段的 JSON。模型必须：
- 分析前 1~3 条数据，理解字段名、嵌套结构、图片字段的格式
- **不得臆造字段**，所有字段名和结构以现有数据为准
- 记录图片字段的键名（如 `plantImage`、`image`、`cover` 等）及其格式（`{url, width, height}` 或纯字符串等）

---

### 第四步：获取用户数据

**方式 A：图片目录**
- 获取本地图片目录路径
- 逐个调用 `upload-image.sh` 上传，收集 `url width height`

```bash
bash <skill_dir>/script/upload-image.sh <workspace> <file_path>
# stdout: <url> <width> <height>
```

**方式 B：Excel + 图片目录**
- 获取 Excel 文件路径（`.xlsx`）和图片目录路径
- 用 Python 读取表格（`import openpyxl`），根据表头和现有数据结构映射列
- 有图片列（文件名）则调用 `upload-image.sh` 上传；留空则图片字段为 null

---

### 第五步：模型构造新数据

基于第三步理解的数据结构，将第四步获得的内容填充进去，生成完整 JSON 数组，写入临时文件：

```bash
# 模型将构造好的 JSON 数组写入临时文件
TMPFILE="/tmp/new_data_$(date +%s).json"
# 写入后调用 submit
```

**原则：**
- 以现有第一条数据为模板，逐字段填充新内容
- 不确定的字段保持与现有数据相同的默认值
- Excel 列名不固定，模型自行根据表头判断映射关系

---

### 第六步：确认后提交

展示将要写入的数据条数和 config_id/module_id，确认后执行：

```bash
bash <skill_dir>/script/submit-module.sh \
  <workspace> <config_id> <module_id> <data_file> [draft|submit]
```

- 默认 `draft`（保存草稿，operationType=1）
- 需要提交审核时用 `submit`（operationType=2）
- 提交时自动包含全部模块，只有目标模块被替换，其余原样保留

---

## 脚本说明

| 脚本 | 用法 | 输出 |
|------|------|------|
| `upload-image.sh <workspace> <file>` | 上传单张图片 | stdout: `<url> <width> <height>` |
| `query-module.sh <workspace> <config_id>` | 列出所有模块 | stdout: 每行 `<id>\t<name>` |
| `query-module.sh <workspace> <config_id> <module_id>` | 查询模块现有数据 | stdout: data JSON 字符串 |
| `submit-module.sh <workspace> <config_id> <module_id> <data_file> [draft\|submit]` | 提交数据 | 成功输出确认信息 |

---

## 注意事项

- 提交时脚本自动包含**全部模块**，不会丢失其他模块数据
- 配置非草稿态时 `draft` 会报错，需改用 `submit`
- SSO 登录态失效时脚本输出登录 URL，提示用户登录后重试
- porch session 失效时提示运行 `set-porch-session.sh` 更新
- config_id 从 ditto 链接末尾数字提取

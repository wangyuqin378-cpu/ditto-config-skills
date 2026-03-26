# ditto-config-skills

> 用 Claude Code 操作小红书内部 Ditto 数据配置中心的 Claude Skills 集合。

## 是什么

`ditto-config-skills` 是一套 [Claude Code](https://claude.ai/claude-code) Skills，让你可以用自然语言完成原本需要手动在 Ditto 数据配置中心反复操作的工作——批量上传图片、从 Excel 写入物料数据，支持任意模块的任意数据结构。

---

## 包含的 Skills

### `ditto-material-config`

将本地图片或 Excel 数据批量写入 Ditto 物料配置平台指定模块。

**触发方式：**
- "帮我配置物料"
- 粘贴 Ditto 配置页链接 + 说"上传/更新"
- "把这个 Excel 写入 ditto 某个模块"

**工作方式：**

模型先读取模块现有数据，理解字段结构，再基于用户提供的内容生成新数据——无需预设任何字段，适配任意物料类型。

| 输入方式 | 说明 |
|---------|------|
| 图片目录 | 批量上传目录下图片，收集 CDN URL 和尺寸 |
| Excel + 图片目录 | 读取表格，图片列填文件名，自动匹配上传 |

底层由三个独立脚本支撑：

| 脚本 | 功能 |
|------|------|
| `upload-image.sh` | 上传单张图片，返回 `url width height` |
| `query-module.sh` | 查询模块列表或读取模块现有数据 |
| `submit-module.sh` | 提交数据到指定模块（其余模块原样保留） |

---

### `data-fe-sso`

小红书内网统一登录态管理。访问 `*.xiaohongshu.com` 前自动获取并维护 Cookie。

同时管理图片上传所需的 `porch_beaker_session_id`（存储后约 7 天内自动复用）。

---

## 安装

```bash
# 克隆到本地
git clone https://github.com/wangyuqin378-cpu/ditto-config-skills.git

# 软链接到 Claude skills 目录
ln -s $(pwd)/ditto-config-skills/ditto-material-config ~/.claude/skills/ditto-material-config
ln -s $(pwd)/ditto-config-skills/data-fe-sso ~/.claude/skills/data-fe-sso
```

重启 Claude Code 后生效。

---

## 首次使用

**1. 存储 porch session**（图片上传专用，只需一次，7 天内有效）

在浏览器打开 `fe.devops.xiaohongshu.com`，DevTools → Network，复制任意请求头中的 `porch_beaker_session_id`：

```bash
bash data-fe-sso/script/set-porch-session.sh /path/to/workspace <porch_beaker_session_id>
```

**2. 直接对话**

```
帮我更新 ditto 这个配置里的物料数据
https://ditto.devops.xiaohongshu.com/ditto-dataconfig-center/data-configuration/preview/699
```

Claude 会自动查询模块列表、读取现有数据结构，引导你完成剩余步骤。

---

## 依赖

- [Claude Code](https://claude.ai/claude-code)
- `jq`（`brew install jq`）
- `python3` + `openpyxl`（`pip3 install openpyxl`，Excel 模式需要）
- 小红书内网访问权限

---

## License

MIT

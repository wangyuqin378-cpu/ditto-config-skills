# ditto-config-skills

> 用 Claude Code 操作小红书内部 Ditto 数据配置中心的 Claude Skills 集合。

## 是什么

`ditto-config-skills` 是一套 [Claude Code](https://claude.ai/claude-code) Skills，让你可以用自然语言完成原本需要手动在 Ditto 数据配置中心上点来点去的工作——比如批量上传植物图片、从 Excel 更新物料数据。

---

## 包含的 Skills

### `configsdk-plant-image`

批量上传图片并配置到 Ditto 物料配置平台指定模块。

**触发方式：**
- "帮我配置植物图片"
- 粘贴 Ditto 配置页链接 + 说"上传图片"
- "从 Excel 更新物料数据"

**支持两种输入模式：**

| 模式 | 说明 |
|------|------|
| 图片目录 | 批量上传目录下所有图片，自动构造植物数据 |
| Excel + 图片目录 | 从 `.xlsx` 读取植物属性，「植物图片」列填文件名，自动匹配上传 |

Excel 列格式（A-E）：植物id / 植物名称 / 植物类型 / 价格 / 植物图片（文件名）

---

### `data-fe-sso`

小红书内网统一登录态管理。访问 `*.xiaohongshu.com` 域名前自动获取并维护 Cookie。

同时管理图片上传所需的 `porch_beaker_session_id`（存储后 7 天内自动复用）。

---

## 安装

```bash
# 克隆到本地
git clone https://github.com/wangyuqin378-cpu/ditto-config-skills.git

# 软链接到 Claude skills 目录
ln -s $(pwd)/ditto-config-skills/configsdk-plant-image ~/.claude/skills/configsdk-plant-image
ln -s $(pwd)/ditto-config-skills/data-fe-sso ~/.claude/skills/data-fe-sso
```

重启 Claude Code 后生效。

---

## 首次使用

**1. 存储 porch session**（图片上传专用，只需一次）

在浏览器打开 `fe.devops.xiaohongshu.com`，DevTools → Network，复制任意请求头中的 `porch_beaker_session_id`：

```bash
bash data-fe-sso/script/set-porch-session.sh /path/to/workspace <porch_beaker_session_id>
```

**2. 直接对话**

```
帮我把这个目录的图片配置到 ditto 上
https://ditto.devops.xiaohongshu.com/ditto-dataconfig-center/data-configuration/preview/699
```

Claude 会自动引导你完成剩余步骤。

---

## 依赖

- [Claude Code](https://claude.ai/claude-code)
- `jq`（`brew install jq`）
- `python3` + `openpyxl`（`pip3 install openpyxl`，Excel 模式需要）
- 小红书内网访问权限

---

## License

MIT

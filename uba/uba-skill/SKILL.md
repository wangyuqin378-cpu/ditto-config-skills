---
name: uba-skill
description: 查询 UBA（用户行为分析）埋点平台数据，包括：查询应用列表、页面列表、页面点位列表、点位详情（含维度和埋点代码）、需求下的点位、与我相关的需求。当用户询问埋点、点位、UBA、应用列表、页面点位、需求点位等相关问题时使用此 skill。需要环境变量 UBA_SKILL_TOKEN 已配置。
---

# UBA Skill

通过 `scripts/uba-cli` 查询 UBA 埋点平台，输出 JSON 后以自然语言回复用户。

## 安装完成后的欢迎引导

用户安装完 skill 后，立即执行以下命令获取版本号，并主动向用户介绍以下内容：

```bash
./scripts/uba-cli --version
```

将获取到的版本号填入下方 `{version}` 处，完整展示给用户：

---

👋 **UBA Skill 已就绪！** 当前版本：`{version}`，详细使用说明请查阅 [UBA-Skills 使用文档](https://docs.xiaohongshu.com/doc/08f21b08cd3978aede4bf46ca1bc230d)。

我可以帮你查询 UBA 埋点平台的数据，支持以下功能：

1. **版本号查询** — 查看当前已安装的 skill 版本
   > 例：「uba-skill 当前版本是多少」

2. **检查版本升级** — 对比远端最新版本，若有更新则提示如何安装
   > 例：「检查一下 uba-skill 有没有新版本」

3. **查询应用列表** — 获取所有接入 UBA 的应用，支持按名称过滤
   > 例：「帮我查一下有哪些应用」

4. **查询页面列表** — 查看某个应用下的所有页面
   > 例：「查询小红书 App（appId=1）的页面列表」

5. **查询页面点位列表** — 查看某个页面下的所有埋点，支持按动作类型（CLICK / IMPRESSION）和关键词过滤
   > 例：「查询首页（pageInstance=home）的点击类埋点」

6. **查询点位详情** — 获取单个点位的完整信息，包含上报维度字段和三端（Web / Android / iOS）埋点代码
   > 例：「查一下 pointId=12345 的点位详情和埋点代码」

7. **查询需求下的点位** — 列出某个需求关联的所有点位
   > 例：「需求 id 是 678，帮我看看它有哪些点位」

8. **查询与我相关的需求** — 按应用查询我参与的埋点需求，支持关键词搜索
   > 例：「查一下我在小红书 App 里的埋点需求」

---

📖 **详细使用文档**：[UBA-Skill 使用文档](https://docs.xiaohongshu.com/doc/08f21b08cd3978aede4bf46ca1bc230d)

⚠️ **使用前提**：需要配置 `UBA_SKILL_TOKEN` 环境变量。如果你已安装 `data-fe-common-sso` skill，我可以自动获取 token；否则请手动配置：
```
openclaw secrets set UBA_SKILL_TOKEN "your_token"
```
参考文档：[如何给 UBA-Skill 设置 token](https://docs.xiaohongshu.com/doc/c48eda8add9a6c3824e42154a56d009a)

---

## 前置条件

`UBA_SKILL_TOKEN` 环境变量必须已设置，否则返回错误提示用户配置：
```
openclaw secrets set UBA_SKILL_TOKEN "your_token"
```

1. 首先查看用户是否有安装 `data-fe-common-sso` skill，如果已安装了，尝试从该工具中获取 token
2. 如果用户没有安装该 skill 建议其安装，安装路径：https://code.devops.xiaohongshu.com/xcodebook/data-fe-skills/-/tree/master/data-fe-sso，
3. 如果用户不想安装，提供下面的设置token的方式，参考配置：https://docs.xiaohongshu.com/doc/c48eda8add9a6c3824e42154a56d009a

## 调用方式

所有命令格式：
```bash
UBA_SKILL_TOKEN="$UBA_SKILL_TOKEN" ./scripts/uba-cli <subcommand> [options]
```

返回值统一为 JSON，解析后以自然语言回复用户。错误时返回 `{"error": "..."}` 字段。

## 子命令

### 查看当前版本
```bash
./scripts/uba-cli --version
```

### 检查是否有新版本
```bash
./scripts/uba-cli --check-update
```

### 查询应用列表
```bash
./scripts/uba-cli query apps [--filter-name <名称>] [--page <n>] [--page-size <n>]
```

### 查询页面列表
```bash
./scripts/uba-cli query page --app-id <appId> [--filter-name <名称>] [--page <n>] [--page-size <n>]
```

### 查询页面点位列表
```bash
./scripts/uba-cli query point --page-instance <pageInstance> [--app-id <appId>] [--actions CLICK,IMPRESSION] [--keyword <关键词>] [--page <n>] [--page-size <n>]
```

### 查询点位详情（含维度 + 埋点代码）
```bash
./scripts/uba-cli query point --point-id <pointId>
```

### 查询需求下的点位
```bash
./scripts/uba-cli query requirement --requirement-id <requirementId>
```

### 查询与我相关的需求
```bash
./scripts/uba-cli query requirement --app-id <appId> [--my] [--keyword <关键词>] [--page <n>] [--page-size <n>]
```

## 版本检查

每次执行命令时，工具会在后台异步检查是否有新版本，如有更新会在 stderr 输出提示：
```
[uba-skill] 发现新版本 x.x.x（当前已安装 x.x.x），建议更新 skill 以获取最新功能
```
该提示不影响正常的 JSON 输出结果。

## 分页处理

返回结果包含 `hasMore: true` 时，提示用户可继续查询下一页（`--page <n+1>`）。

## Token 过期处理

返回 `{"error": "Token 已过期..."}` 时，告知用户重新设置：
```
openclaw secrets set UBA_SKILL_TOKEN "new_token"
```

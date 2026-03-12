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

9. **事件分析** — 对指定埋点按时间范围做多维度分析，支持 5 种指标类型（次数 PV、人数 UV、渗透率、人均次数、次日留存率），可多点位、每点位单独指定指标。若用户只有**事件名称**没有点位 ID，引导其先通过「查询页面点位列表」用 `--keyword <事件名称>` 或按页面查找到点位 ID，再调用事件分析命令。
   > 例：「查一下点位 2187 在 2026-03-05 到 2026-03-11 的 UV 趋势」「点位 2187、2106 分别按 PV 和 UV 分析」「按事件名称查某埋点的 UV」→ 先查点位 ID 再分析

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

### 事件分析（按时间范围查询埋点指标）

对指定点位在时间范围内做指标分析，支持多点位、每点位单独指定指标类型（quota）。

**按事件名称查询时：** 事件分析接口仅支持按**点位 ID**（`--point-id` / `--point-ids`）查询，不支持直接传事件名称。若你只有事件名称，请先通过「查询页面点位列表」按关键词或页面查找到对应点位的 ID，再使用该 ID 调用事件分析。步骤如下：

1. **先查点位 ID**（二选一或组合使用）  
   - 按页面查该页面下所有点位，再从结果中根据名称找到 ID：  
     `./scripts/uba-cli query point --page-instance <页面实例名> [--app-id <appId>]`  
   - 按关键词搜索点位（名称/描述等）：  
     `./scripts/uba-cli query point --page-instance <页面实例名> [--app-id <appId>] --keyword <事件名称或关键词>`  
2. **再调用事件分析**：用上一步得到的点位 ID 执行事件分析命令（见下方命令格式与示例）。

**命令格式：**
```bash
./scripts/uba-cli query analysis --point-ids <id1,id2,...> --start-date <YYYY-MM-DD> --end-date <YYYY-MM-DD> [选项]
# 或单点位简写
./scripts/uba-cli query analysis --point-id <pointId> --start-date <YYYY-MM-DD> --end-date <YYYY-MM-DD> [选项]
```

**参数说明：**

| 参数 | 必填 | 说明 |
|------|------|------|
| `--point-ids` / `--point-id` | 是 | 点位 ID，多个用逗号分隔：`--point-ids 2187,2106` |
| `--start-date` | 是 | 开始日期，格式 `YYYY-MM-DD` |
| `--end-date` | 是 | 结束日期，格式 `YYYY-MM-DD` |
| `--app-id` | 否 | 应用 ID，用于自动解析事件名；不传时从首个点位推断 |
| `--granularity` | 否 | 时间粒度：`day`（默认） / `week` / `month` / `hour`。按周（week）时默认以**近七天为一周** |
| `--quota` | 否 | 所有点位共用的指标类型，默认 `UV`（见下表） |
| `--quotas` | 否 | 按点位顺序分别指定指标类型，逗号分隔，与 `--point-ids` 一一对应 |

**指标类型（quota）可选值：**

| 值 | 含义 |
|----|------|
| `PV` | 次数 |
| `UV` | 人数 |
| `PERMEABILITY` | 渗透率 |
| `PV_PER_UV` | 人均次数 |
| `RETENTION` | 次日留存率 |

若同时传 `--quota` 与 `--quotas`，以 `--quotas` 为准；`--quotas` 个数少于点位个数时，多出的点位使用默认 `UV`。

**功能限制：**

⚠️ 当前版本暂时不支持以下功能：
- **点位筛选**：暂不支持对单个点位添加额外筛选条件
- **点位分组**：暂不支持按维度分组查询
- **全局筛选修改**：默认自动添加全局筛选条件「spam 级别 = 正常」，暂不支持修改
- **应用限制**：目前仅支持小红书标准流程（appId=1）查询，轻量化流程暂不支持事件分析

**调用示例：**

```bash
# 单点位、默认 UV（人数）
./scripts/uba-cli query analysis --point-id 2187 --start-date 2026-03-05 --end-date 2026-03-11

# 单点位、指定 PV（次数）
./scripts/uba-cli query analysis --point-id 2187 --start-date 2026-03-05 --end-date 2026-03-11 --quota PV

# 多点位、全部用 UV
./scripts/uba-cli query analysis --point-ids 2187,2106 --start-date 2026-03-05 --end-date 2026-03-11 --quota UV

# 多点位、每个点位不同指标：2187 用 PV，2106 用 UV
./scripts/uba-cli query analysis --point-ids 2187,2106 --start-date 2026-03-05 --end-date 2026-03-11 --quotas PV,UV

# 按周粒度、渗透率
./scripts/uba-cli query analysis --point-id 2187 --start-date 2026-03-01 --end-date 2026-03-11 --quota PERMEABILITY --granularity week

# 指定 app-id 以自动解析事件名
./scripts/uba-cli query analysis --point-ids 2187,2106 --start-date 2026-03-05 --end-date 2026-03-11 --app-id 1 --quotas PV_PER_UV,RETENTION
```

**仅知道事件名称时（先查 ID 再分析）：**

```bash
# 步骤 1：按关键词或页面查点位，从返回结果中确认目标点位的 pointId
./scripts/uba-cli query point --page-instance home --app-id 1 --keyword "页面曝光"

# 步骤 2：用得到的 pointId 调用事件分析
./scripts/uba-cli query analysis --point-id <上一步查到的 pointId> --start-date 2026-03-05 --end-date 2026-03-11
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

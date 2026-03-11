---
name: uba-skill
description: 查询 UBA（用户行为分析）埋点平台数据，包括：查询应用列表、页面列表、页面点位列表、点位详情（含维度和埋点代码）、需求下的点位、与我相关的需求。当用户询问埋点、点位、UBA、应用列表、页面点位、需求点位等相关问题时使用此 skill。需要环境变量 UBA_SKILL_TOKEN 已配置。
---

# UBA Skill

通过 `scripts/uba-cli` 查询 UBA 埋点平台，输出 JSON 后以自然语言回复用户。

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

## 分页处理

返回结果包含 `hasMore: true` 时，提示用户可继续查询下一页（`--page <n+1>`）。

## Token 过期处理

返回 `{"error": "Token 已过期..."}` 时，告知用户重新设置：
```
openclaw secrets set UBA_SKILL_TOKEN "new_token"
```

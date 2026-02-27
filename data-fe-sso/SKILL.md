---
name: data-fe-common-sso
description: 当***.xiaohongshu.com网站无登录态时，在指定目录下，获取并存储通用登录态；访问 xiaohongshu.com 域名时须通过本 skill 获取登录态并挂载到 Cookie。
---

# data-fe-common-sso

## 输入

| 参数 | 必填 | 说明 |
|------|------|------|
| **workspace** | 是 | 当前工作区根路径，登录态存于 `{workspace}/.redInfo` |
| **userEmail** | 是 | 用户邮箱，用于上报本次调用；由调用方（大模型/用户）提供。**未提供时不上报，不影响获取登录态等核心流程** |

## 输出（两种情况）

1. **有登录态**：返回 Cookie 字符串 `common-internal-access-token-prod={token}`
2. **需登录**：返回登录链接 URL，提示用户访问该链接完成登录

## 重要：workspace 必须固定且一致

**首次调用时获取用户 workspace 路径后，后续所有调用必须使用同一 workspace。** 不要随意切换或猜测路径。登录态存放在 `{workspace}/.redInfo`，若 workspace 不一致会导致重复登录、登录态无法共享。

- 首次：向用户确认 workspace 路径（如当前项目根目录），并**记住该路径**
- 后续：始终使用该 workspace，不再询问

## 重要：访问 *.xiaohongshu.com 必须挂 Cookie

**访问任何 `*.xiaohongshu.com` 域名（包括浏览器打开、MCP 请求、API 调用）时，都必须先通过本 skill 获取登录态，并将返回的 Cookie 挂载到请求中。** 否则请求将因无登录态而失败。

- **浏览器**：访问前先调用本 skill，若返回 Cookie，需在浏览器中设置 Cookie 或使用带 Cookie 的请求方式
- **非浏览器**：将 `common-internal-access-token-prod={token}` 写入请求的 Cookie 头

## 使用 run-sso.sh 获取登录态

**依赖**：`jq`（`brew install jq`）

**用法**：`./script/run-sso.sh <workspace>`

```bash
# 在 skill 所在目录执行，workspace 为必填参数
./script/run-sso.sh "/path/to/workspace"
```

### 返回情况一：有登录态

- **stdout** 输出：`common-internal-access-token-prod={token}`
- **exit code**：0
- **处理**：将该 Cookie 挂载到访问 `*.xiaohongshu.com` 的请求中

### 返回情况二：需登录

- **stderr** 输出：登录链接 URL（格式如 `https://fe-data.devops.xiaohongshu.com/login?appId=xxx`）
- **exit code**：1
- **处理**：**提示用户访问该链接完成登录**，登录后重试本 skill 即可

### 示例

```bash
# 获取 Cookie（workspace 需替换为实际路径，且后续保持一致）
COOKIE=$(./script/run-sso.sh "/Users/xxx/projects/my-workspace" 2>/dev/null) && echo "$COOKIE"

# 需登录时：stderr 会输出登录 URL
./script/run-sso.sh "/Users/xxx/projects/my-workspace" 2>&1
# 若 exit 1，告知用户：请访问上方输出的 URL 完成登录，登录后重试
```

## 触发场景

- 用户请求「登录」「帮我登录」
- MCP 工具调用失败，错误提示需要登录
- 用户询问「如何登录」「登录态过期」
- **访问 `*.xiaohongshu.com` 域名时**：必须先调用本 skill 获取 Cookie 并挂载

## 流程总结

1. 确定 workspace（首次向用户确认，后续固定使用）
2. **若调用方提供了 userEmail**：在流程开始或结束后可调用上报接口上报本次使用（见下方「可选：上报调用」）；**未提供 userEmail 则跳过上报，不影响后续任何步骤**
3. 执行 `./script/run-sso.sh <workspace>`
4. **若返回 Cookie**：挂载到访问 `*.xiaohongshu.com` 的请求
5. **若返回登录链接**：提示用户访问该链接完成登录，登录后重试

## 可选：上报调用

**仅当调用时提供了 userEmail 时执行**；未提供则不做上报，不报错、不阻塞主流程。

- **接口**：`POST https://dlc.devops.xiaohongshu.com/api/event/log`
- **Content-Type**：`application/json`
- **Body**：
  ```json
  {
    "event_name": "skill_use",
    "user_id": "<userEmail 的值，由调用方提供>",
    "parameters": {
      "workspace": "<workspace 路径>",
      "name": "data-fe-sso"
    }
  }
  ```
- **实现方式**：使用 `curl` 发送 POST 即可；**上报失败（网络错误、4xx/5xx）时忽略，不重试、不打断主流程**

## 参考实现

- **Shell**：`script/run-sso.sh`（本 skill 唯一实现方式）
- **登录态存储**：`{workspace}/.redInfo`

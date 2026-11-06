# scripts 说明

| 脚本 | 作用 | 是否需要设备 / DevEco |
| ---- | ---- | ---- |
| `run.sh` | 一键检查并构建 | 检查部分不需要；构建需要 `devecocli` |
| `check_strings.mjs` | 资源 JSON 语法、zh_CN / en_US key、`$r('app.string.*')` 引用检查 | 不需要 |
| `check_format.mjs` | 行尾空格、CRLF、文件末尾换行、Tab 缩进检查 | 不需要 |

## 快速运行

```bash
# 只做检查，任何装有 Node.js 的机器都能跑
bash scripts/run.sh --check-only

# 检查后构建，需要已安装 DevEco 命令行工具（devecocli）
bash scripts/run.sh
```

未找到 `devecocli` 时，脚本会完成检查并打印用 DevEco Studio 手动构建运行的步骤。

## 运行与验证的边界

- **无设备可验证**：资源一致性、格式检查，也是 CI 中自动执行的部分。
- **需要真机或模拟器**：应用本身的运行、端侧识别、云同步（需要华为账号环境）。构建后请在设备上走一遍主要流程，演示流程见演示视频。

## 前置依赖

- Node.js 18 及以上
- DevEco Studio 5.0 及以上（或 DevEco 命令行工具）
- 云同步为可选功能，配置步骤见根目录 README

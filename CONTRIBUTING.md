# 贡献指南

本项目为课程设计的团队协作仓库。为保证内部质量与可评审性，协作遵循以下规范。

## 分支模型

| 分支 | 用途 |
| ---- | ---- |
| `main` | 开发主线。包含训练数据采集等开发期工具功能，日常开发在此推进。 |
| `release` | 发行分支。面向最终用户，剥离开发期工具，仅保留用户可见功能。 |
| `feat/*` | 功能分支。较大特性先开分支开发，完成后合回 `main`。 |
| `backup/*` | 历史快照分支（如 `backup-before-squash`），仅作备份不参与开发。 |

**发行流程**：`main` 功能稳定后，将用户可见特性整理进 `release`，打版本 tag（`v*.*.*`）发布。

## 提交规范

统一使用 **`类型(范围): 详细中文说明`** 单行格式，全文中文，不中英混用。

| 类型 | 用途 |
| ---- | ---- |
| `功能` | 新增功能或页面 |
| `修复` | 缺陷修复 |
| `优化` | 性能、体验、精度等非功能性改进 |
| `重构` | 结构调整，不改变外部行为 |
| `测试` | 新增或修改测试用例 |
| `文档` | README、docs 等文档变更 |
| `构建` | 构建、依赖、CI 配置变更 |

示例：

```
功能(识别): 实现图片识别记账全流程（流水线、智能分类、批量导入去重）
修复(预算): 消费额度输入与下方预览不一致——effectiveLimit原要求输入不超上限才生效…
```

**粒度要求**：每个 commit 只做一件事（单一职责）。功能、格式化、重构、文档分开提交，便于评审与回溯。提交信息说明「为什么」和「影响范围」，能量化时给出数据（如准确率变化、命中数）。

## 提交前检查

1. **静态检查**：通过 DevEco Studio（`codelinter`）或 `devecocli check arkts` 检查 ArkTS 严格模式违规。
2. **资源检查**：新增/修改 `$r('app.string.*')` 引用后运行 `node scripts/check_strings.mjs`，保证引用有定义且 zh_CN / en_US 无无效 key。
3. **构建**：`devecocli build`（或 IDE 构建）通过后才可提交。
4. **测试**：触及识别流水线、分类、去重、解析等逻辑时，运行 `entry/src/ohosTest` 单元测试。
5. **格式**：遵循 `.editorconfig`（2 空格缩进、UTF-8、LF），提交前消除冗余空格与未使用导入。可运行 `node scripts/check_format.mjs` 检查已暂存的文件（检查行尾空格、CRLF、文件末尾换行、Tab 缩进），或安装 pre-commit 钩子在每次提交前自动检查：`pip install pre-commit && pre-commit install`。CI 会对每次 push / PR 改动的文件执行同样的格式检查，历史遗留文件不受影响。

## 代码风格

- ArkTS 严格模式：不使用 `any` / `unknown` / `as` 断言 / 结构化类型；对象字面量必须显式类型上下文。
- 命名：页面/组件 `UpperCamelCase`，方法与变量 `lowerCamelCase`，常量 `UPPER_SNAKE_CASE`；布尔成员用 `is/has/can` 前缀。
- 分层：页面不直接访问数据库；UI → service → data（Repository）单向依赖；跨层通信用事件/Store 通知（如 `LedgerStore.notifyChanged()`）。
- 注释：解释「为什么」而非「是什么」；公开导出接口写用途注释。
- 资源：文案一律进 `string.json`（base / zh_CN / en_US 三份同步），不硬编码中文到代码。

## Issue 与 PR

- 功能与缺陷以 GitHub Issue 跟踪，标题前缀 `[功能]` / `[缺陷]`。
- PR 标题与 commit 同规范，正文说明动机、改动点、自测方式；大改动附截图或录屏。
- PR 评审通过后合入，主分支保持随时可构建。

## 工作量度量

工作量以 git 度量为准（`git shortlog -sn`、`git log --author --numstat`），分工与证据见 [docs/工作量分配与KPI.md](./docs/工作量分配与KPI.md)。

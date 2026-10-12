# HyperOS 适配日志

## v0 — 2026-10-12

- 建立「系统兼容」仓库结构（`docs/compat/`、`config/<系统>/`、`tools/`）
- 实测设备：Redmi K50 Pro · HyperOS OS3.0.309.0 · Android 16 · APatch(FolkPatch) + LSPosed v2.2.1
- 配置层：
  - `block_rules` 移除 `athena`（ColorOS 专属，HyperOS 无此组件）→ `o-stop,frozen,cached,empty,cpu`
  - 白名单建议：微信 / QQ / 抖音 / 代理类 / 校园类 / 本地自动化（按需增删）
- 安装层：
  - 记录 COSGuard 手动安装方案（部分机型自动安装不触发）
  - LSPosed 作用域：系统框架
- 验证层：
  - 新增 `tools/hyperos-healthcheck.sh`（只读体检）
- 实测结论：引擎全天 `FAILED=0`；KEEPADJ 保活正常；防线 observe 数据正常；与 millet 共存无冲突

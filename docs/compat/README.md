# 系统兼容适配（compat）

COSMemory 官方主要面向 ColorOS 15/16。本目录收集各系统的兼容适配资料与工具。
（COSMemory system-compatibility fork — HyperOS first. Docs are in Chinese for now.）

## 状态矩阵

| 系统 | 状态 | 说明 |
|---|---|---|
| ColorOS 15/16 | ✅ 官方原生 | 见上游 README |
| 小米 HyperOS（2/3） | ✅ 已适配（v0） | 实测：Redmi K50 Pro · HyperOS OS3.0.309.0 · Android 16 · APatch(FolkPatch) + Zygisk + LSPosed |
| 其它系统 | 🧪 待验证 | 欢迎提交反馈 |

## 适配层级

1. **配置层**：`config/<系统>/` 下的推荐配置（如 block_rules 去 ColorOS 专属项）
2. **安装层**：`docs/compat/<系统>/install-guide.md`
3. **验证层**：`tools/hyperos-healthcheck.sh`（本仓库新增）
4. **代码层**：暂未需要（如需，将以最小补丁 + 上游 PR 方式进行，避免长期分叉）

## HyperOS 入口

- [适配总览](hyperos/overview.md)
- [安装指南](hyperos/install-guide.md)
- [已知问题](hyperos/known-issues.md)
- [适配日志](hyperos/changelog-hyperos.md)

## 许可与致谢

- 本仓库与上游一致遵循 **GPLv3**（继承自 A1Memory / COSMemory）
- 致谢：HChai · OneB1ank（A1Memory）／ 是你吗薰儿（COSMemory 上游作者）

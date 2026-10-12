# HyperOS 适配总览（v0）

> 实测环境：Redmi K50 Pro（mt6983）· HyperOS OS3.0.309.0（Android 16）· APatch 系（FolkPatch v115356）+ Zygisk + LSPosed v2.2.1

## 目标

- **装得上**：模块 + COSGuard 防线在 HyperOS 正常安装、启用
- **跑得稳**：引擎连续运行、`FAILED=0`、无异常重启/风暴
- **可回滚**：任何改动可一键还原

## 适配要点（v0，以配置层为主）

1. **block_rules 去掉 `athena`**
   athena（雅典娜）是 ColorOS 专属组件，HyperOS 上不存在；保留只会产生误报噪音。
   推荐：`"block_rules": "o-stop,frozen,cached,empty,cpu"`
2. **白名单按需定制**
   如代理（v2ray 等）、校园类、本地自动化工具（Operit 等）；
   白名单进程的 `oom_score_adj` 会被引擎保持在 200。
3. **COSGuard 防线**
   LSPosed 作用域勾选「系统框架」即可（列表里没有“雅典娜”是正常的）；
   若 zip 自动安装未触发，手动 `pm install` 即可（见安装指南）。
4. **观察模式先行**
   建议先用 `"guard": {"mode": "observe"}` 收集数据，再考虑升级为主动拦截，避免误杀。

## 实测结果（2026-10-11 ~ 10-12）

- 引擎全天稳定：`FAILED=0`、看门狗 0 重启、哨兵 0 中止
- 白名单保活：全天 KEEPADJ 护航（微信 / QQ 等子进程 adj 保持 200）
- 防线 observe：全天判定入库，真实杀因库已建立
  （normal_mem_pressure / system loading too high / from process:system / SwipeUpClean 等）
- 与小米 **millet**（内核内存体系）共存无冲突

## 已知边界

见 [known-issues.md](known-issues.md)

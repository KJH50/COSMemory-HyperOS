# HyperOS 已知差异与判读

| 现象 | 判读 | 处置 |
|---|---|---|
| 能力探测 `CAP_OPLUS=0` | 正常：ColorOS 专属能力，与 HyperOS 无关 | 忽略 |
| `startProcess=0`（签名差异） | 引擎 fail-open（探测失败=放行），无害 | 忽略 |
| block_rules 里保留 `athena` | 噪音来源（HyperOS 无“雅典娜”组件） | 移除（本仓库默认配置已处理） |
| COSGuard 未自动安装 | 部分机型 zip 脚本未触发（实测：zip 内 apk 名与脚本 glob 不一致） | 手动 `pm install`（见安装指南） |
| 面板 / WebUI 打不开或显示受限 | 显示层依赖管理器 WebUI 支持；引擎独立运行 | 不影响功能，可选装 |
| “内存看起来还是满的” | 安卓常态：缓存占满 ≠ 内存不足 | 看 PSI：`cat /proc/pressure/memory`，some 值低即为健康 |
| 与小米 millet 冲突？ | 无：实测共存（millet_monitor / 内核模块照常） | — |
| stats 行数不连续增长 | 按轮/按天滚动或重启会话属正常 | 以 `FAILED=0` 与引擎存活为准 |
| 微信/QQ 被杀仍发生 | 观察模式下只记录不拦截 | 收集足够数据后升级 guard 模式 |

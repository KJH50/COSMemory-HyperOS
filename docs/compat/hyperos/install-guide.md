# HyperOS 安装指南

## 前置

- 已 root：APatch / FolkPatch（本仓库实测）或 KernelSU / Magisk
- LSPosed（用于 COSGuard 防线；**不装防线引擎也能独立运行**）

## 一、安装模块

1. 下载 zip（本仓库 Releases 或上游 v1.2.x）
2. 安装方式二选一：
   - 管理器（FolkPatch 等）→「从本地安装」→ 选择 zip
   - 命令行（APatch 系）：`apd module install /sdcard/xxx/COSMemory_vX.Y.Z.zip`
3. 重启生效（管理器里会显示“待重启”，重启后自动转正）

## 二、安装 COSGuard（防线组件）

1. 从 zip 内取出 COSGuard APK（`assets/cosguard_*.apk` 或 `lsp/*.apk`），手动安装：
   `pm install -r /data/local/tmp/cosguard_vXXX.apk`
   （本仓库实测：官方 zip 的自动安装脚本在部分机型不触发，手动安装等效）
2. 打开 LSPosed → 模块 → 启用「COSGuard / COSMemory守卫」，
   作用域勾选 **系统框架**（HyperOS 无“雅典娜”，如列表没有属正常）
3. 重启

## 三、配置

- 名单文件：`/sdcard/Android/COSMemory/名单列表.conf`（每行 `WHITE 包名`）
- 主配置：模块目录 `config/memory.json`（参考 `config/hyperos/memory.json`）
- 改完后约 30 秒内桥自动重建（`/data/system/cosmem/`），无需重启

## 四、验收

- 一键体检：`sh tools/hyperos-healthcheck.sh`
- 或手动核对：
  - 引擎进程：`ps -A | grep engine/memory.sh`
  - 统计：`tail -3 /data/adb/modules/COSMemory/data/stats.log`（FAILED=0）
  - 桥：`cat /data/system/cosmem/guard.conf`（有 MODE/BLOCK/WHITE）
  - 防线日志：`/data/adb/modules/COSMemory/data/guard/<日期>.log`（有 PASS_OBSERVE）

## 五、回滚

- 管理器禁用 / 卸载模块 → 重启
- 或运行模块内 `uninstall.sh`
- 建议保留原始 zip 备份；配置改动均有 `.bak` 副本

<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { detectBridge, execRead, execReadBatch, type KsuBridge } from './composables/ksu'
import { buildDiagCmd } from './composables/diagnostics'
import { parseStats, parseCaps, whiteStatus, CAP_LABELS, type DayStats } from './composables/stats'
import { parseGuard, guardDate, type GuardStats } from './composables/guard'
import { initTheme, applyModuleTheme } from './composables/theme'
import { parseMemtop, parseFrozen, type MemRow } from './composables/memview'
import DashboardView from './views/DashboardView.vue'
import DefenseView from './views/DefenseView.vue'
import SystemView from './views/SystemView.vue'
import ListView from './views/ListView.vue'
import SettingsView from './views/SettingsView.vue'

const MOD = '/data/adb/modules/COSMemory'
const LIST = '/sdcard/Android/COSMemory/名单列表.conf'
/* panel-perf: 内存观测改为"后台执行 + 轮询取回" —— dumpsys(~3s)不再阻塞 UI 线程 */
const MEM_OUT = '/data/local/tmp/.cosmem_panel_mem.out'
const MEM_BUSY = '/data/local/tmp/.cosmem_panel_mem.busy'
/* panel-perf3: 防线数据后台刷新 —— guard_stats(~0.5s) 不再进同步批 */
const GUARD_OUT = '/data/local/tmp/.cosmem_panel_guard.json'
const GUARD_BUSY = '/data/local/tmp/.cosmem_panel_guard.busy'

const bridge = ref<KsuBridge | null>(detectBridge())
const stats = ref<DayStats | null>(null)
const caps = ref<Record<string, number>>({})
const white = ref<{ pkg: string; adj: number | null; states: string[] }[]>([])
const logTail = ref<string[]>([])
const engineUp = ref<boolean | null>(null)
const error = ref('')
const guard = ref<GuardStats | null>(null)
const listRaw = ref('')
const memtop = ref<MemRow[]>([])
const frozen = ref<{ count: number; pkgs: string[] } | null>(null)
const memLoading = ref(false)
const freeing = ref(false)
const diagBusy = ref(false)
const toastMsg = ref('')
const toastOk = ref(false)
let toastTimer: number | undefined
function toast(msg: string, ok = true, duration = 2600) {
  toastMsg.value = msg; toastOk.value = ok
  if (toastTimer) clearTimeout(toastTimer)
  toastTimer = window.setTimeout(() => { toastMsg.value = '' }, duration)
}
type Tab = 'dash' | 'defense' | 'system' | 'list' | 'set'
const activeTab = ref<Tab>('dash')
function goTab(id: Tab) { activeTab.value = id; document.querySelector('.wrap')?.scrollTo({ top: 0 }) }
let timer: number | undefined

/* ---- panel-perf 基础设施 ---- */
let refreshing = false          // 防重入: 上一轮未回不再发起
let memPending = false          // 内存后台任务在途
let memPendingTs = 0
let memStuck = false            // STUCK 提示只弹一次
let memFallback = false         // 后台分离被管理器杀掉 → 本会话回退直读
let tick = 0
let guardFallback = false
let guardStuckOff = false
const lastJSON = new Map<string, string>()
/** 值未变则跳过赋值 → 跳过整棵组件重渲染 (稳态 5s 轮询几乎零重绘) */
function setIfChanged(key: string, value: unknown, set: (v: any) => void) {
  const s = JSON.stringify(value)
  if (lastJSON.get(key) === s) return
  lastJSON.set(key, s)
  set(value)
}

/* onPickDate: 模板里 guardDate 会被解包成字符串, .value 赋值在严格模式抛错导致选日期无效 */
function onPickDate(d: string) { guardDate.value = d; void startGuardRefresh(); void refresh() }
/* exportDiag: 诊断包一次桥往返导出到 /sdcard/Download */
async function exportDiag() {
  const b = bridge.value
  if (!b) { toast("无 KSU 桥", false); return }
  diagBusy.value = true
  try {
    const r = await execRead(b, buildDiagCmd(MOD, LIST))
    const path = r.trim().split("\n").pop() ?? ""
    if (path.startsWith("/sdcard/")) toast("✓ 已导出 " + path, true, 6000)
    else toast("导出失败: " + (path.slice(0, 40) || "空回读"), false)
  } catch (e) { toast("导出失败: " + String(e).slice(0, 60), false) } finally { diagBusy.value = false }
}

const MODE: Record<string, string> = {
  CAP_LRU: '进程快照', CAP_LRU_FALLBACK: '备用快照源', CAP_PSI: '内存压力',
  CAP_ADJ: 'adj 写入', CAP_LMKD_CFG: 'lmkd 调参', CAP_OPLUS: 'Oplus 扩展',
}

// 能力 → Solar sprite 图标(与显示增强模块同款组件包)
const CAP_ICON: Record<string, string> = {
  CAP_LRU: 'i-apps-2-fill', CAP_LRU_FALLBACK: 'i-stack-fill', CAP_PSI: 'i-dashboard-2-fill',
  CAP_ADJ: 'i-tools-fill', CAP_LMKD_CFG: 'i-cpu-fill', CAP_OPLUS: 'i-smartphone-fill',
}

async function refresh() {
  const b = bridge.value
  if (!b) { error.value = '未检测到 KSU 桥（请在 KernelSU 管理器中打开）'; return }
  if (refreshing) return
  refreshing = true
  tick++
  try {
    // panel-perf: 单次同步往返内完成全部刷新; 白名单 adj 由 shell 聚合(不再二次 exec);
    // 主题/内存卡状态并入同批; 结果按 setIfChanged 去抖, 稳态几乎零重绘。
    const seg = await execReadBatch(b, [
      `printf '\\n@@SEG:log@@\\n'; tail -60 ${MOD}/data/stats.log 2>/dev/null`,
      `printf '\\n@@SEG:caps@@\\n'; cat ${MOD}/data/caps.conf 2>/dev/null`,
      `printf '\\n@@SEG:list@@\\n'; cat "${LIST}" 2>/dev/null`,
      `printf '\\n@@SEG:pid@@\\n'; pgrep -f engine/memory.sh 2>/dev/null || true`,
      `printf '\\n@@SEG:guard@@\\n'; if [ '${guardFallback ? 1 : 0}' = "1" ]; then sh ${MOD}/engine/guard_stats.sh ${guardDate.value || ''} 2>/dev/null || true; else cat ${GUARD_OUT} 2>/dev/null; fi`,
      `printf '\\n@@SEG:gst@@\\n'; if [ '${guardFallback ? 1 : 0}' = "1" ]; then echo OK; elif [ -f ${GUARD_BUSY} ]; then a=$(( $(date +%s) - $(stat -c %Y ${GUARD_BUSY} 2>/dev/null || echo 0) )); if [ "$a" -gt 20 ]; then mv -f ${GUARD_BUSY} ${GUARD_BUSY}.stale 2>/dev/null; echo STUCK; else echo RUNNING; fi; elif [ -f ${GUARD_OUT} ]; then echo OK; else echo EMPTY; fi`,
      `printf '\\n@@SEG:theme@@\\n'; cat ${MOD}/data/theme 2>/dev/null`,
      `printf '\\n@@SEG:mem@@\\n'; if [ -f ${MEM_BUSY} ]; then a=$(( $(date +%s) - $(stat -c %Y ${MEM_BUSY} 2>/dev/null || echo 0) )); if [ "$a" -gt 15 ]; then mv -f ${MEM_BUSY} ${MEM_BUSY}.stale 2>/dev/null; echo STUCK; else echo RUNNING; fi; elif [ -f ${MEM_OUT} ]; then cat ${MEM_OUT}; else echo NONE; fi`,
      `printf '\\n@@SEG:white@@\\n'; awk -F'|' 'FNR==NR{n=split($0,a," ");if(a[1]=="WHITE"&&a[2]!=""){wl[a[2]]=1};next}{st=$1;pid=$3;pkg=$4;if(pkg==""||pid=="")next;hit=0;for(w in wl){if(pkg==w||(index(w,":")==0&&index(pkg,w":")==1)){hit=1;break}}if(hit)print st"|"pid"|"pkg"}' "${LIST}" ${MOD}/data/parsed.txt 2>/dev/null | while IFS='|' read -r st pid pkg; do a=$(cat /proc/$pid/oom_score_adj 2>/dev/null); [ -n "$a" ] && printf '%s|%s|%s\\n' "$st" "$a" "$pkg"; done`,
    ].join('; '))
    const log = seg.log ?? ''
    const capsTxt = seg.caps ?? ''
    const listTxt = seg.list ?? ''
    const livePid = seg.pid ?? ''
    const guardTxt = seg.guard ?? ''
    const themeTxt = seg.theme ?? ''
    const memTxt = (seg.mem ?? '').trim()

    setIfChanged('stats', parseStats(log), v => { stats.value = v as DayStats })
    const guardSt = (seg.gst ?? '').trim()
    if (guardFallback) {
      if (guardTxt) setIfChanged('guard', parseGuard(guardTxt), v => { guard.value = v as GuardStats | null })
    } else if (guardSt === 'STUCK') {
      if (!guardStuckOff) { guardStuckOff = true; guardFallback = true; toast('防线数据后台读取超时，已切回直读模式', false) }
    } else if (guardSt === 'OK') {
      if (guardTxt) setIfChanged('guard', parseGuard(guardTxt), v => { guard.value = v as GuardStats | null })
    }
    setIfChanged('caps', parseCaps(capsTxt), v => { caps.value = v as Record<string, number> })
    setIfChanged('list', listTxt, v => { listRaw.value = v as string })
    const wl = listTxt.split('\n').filter(l => l.startsWith('WHITE ')).map(l => l.slice(6).trim()).join(' ')
    setIfChanged('white', whiteStatus(seg.white ?? '', wl), v => { white.value = v as typeof white.value })
    applyModuleTheme(themeTxt)
    const lt = log.split('\n').filter(Boolean).slice(-50).reverse()
    setIfChanged('logtail', lt, v => { logTail.value = v as string[] })
    engineUp.value = livePid.trim().length > 0
    // 防线数据：后台刷新（每 ~10s 触发一次；busy 文件自去重）
    if (!guardFallback && tick % 2 === 1) { void startGuardRefresh() }

    // 内存卡状态机（后台任务 / 超时回退 / 结果回填）
    if (memTxt === 'RUNNING') {
      memLoading.value = true
    } else if (memTxt === 'STUCK') {
      memLoading.value = false
      if (!memStuck) {
        memStuck = true; memFallback = true
        if (memPending) { memPending = false; toast('内存数据后台读取超时，已切回直读模式（再点一次刷新）', false) }
      }
    } else if (memTxt.startsWith('OK:')) {
      const lines = memTxt.split('\n')
      const rows = parseMemtop(lines[0] ?? '')
      if (rows.length) setIfChanged('memtop', rows, v => { memtop.value = v as MemRow[] })
      const fz = parseFrozen(lines[1] ?? '')
      if (fz.count >= 0) setIfChanged('frozen', fz, v => { frozen.value = v as typeof frozen.value })
      if (memPending) {
        memPending = false
        toast(`✓ 已刷新 · TOP${rows.length} · 墓碑 ${fz.count >= 0 ? fz.count : '—'} 个`)
      }
      memLoading.value = false
    } else {
      // NONE/空: 后台启动后暂无产物
      if (memPending && Date.now() - memPendingTs > 12000) { memPending = false; memLoading.value = false }
    }
    error.value = ''
  } catch (e) { error.value = String(e) } finally { refreshing = false }
}

const TABS: { id: Tab; label: string; icon: string }[] = [
  { id: 'dash', label: '总览', icon: 'i-dashboard-2-fill' },
  { id: 'defense', label: '防线', icon: 'i-lock-unlock-fill' },
  { id: 'system', label: '系统', icon: 'i-cpu-fill' },
  { id: 'list', label: '名单', icon: 'i-user-smile-fill' },
  { id: 'set', label: '设置', icon: 'i-tools-fill' },
]

const capsOk = computed(() => Object.values(caps.value).filter(v => v === 1).length)
const capsEntries = computed(() => Object.entries(caps.value))

/** 后台启动内存观测（dumpsys ~3s 不再阻塞 UI）; 结果由 refresh 轮询取回 */
async function startMemRefresh() {
  const b = bridge.value
  if (!b) return
  if (memFallback) { await syncMemRefresh(); return }
  if (memPending) return
  memPending = true
  memPendingTs = Date.now()
  memLoading.value = true
  try {
    await execRead(b, `{ [ -f ${MEM_BUSY} ] && exit 0; touch ${MEM_BUSY}; if command -v setsid >/dev/null 2>&1; then setsid sh -c 'sh ${MOD}/engine/memtop.sh 2>/dev/null; sh ${MOD}/engine/frozencap.sh 2>/dev/null' > ${MEM_OUT}.tmp 2>&1; else sh -c 'sh ${MOD}/engine/memtop.sh 2>/dev/null; sh ${MOD}/engine/frozencap.sh 2>/dev/null' > ${MEM_OUT}.tmp 2>&1; fi; mv -f ${MEM_OUT}.tmp ${MEM_OUT}; mv -f ${MEM_BUSY} ${MEM_BUSY}.done; } >/dev/null 2>&1 & echo STARTED`)
  } catch { /* 忽略：由 refresh 轮询兜底 */ }
}

/** 防线数据后台刷新（guard_stats ~0.5s，不再阻塞 UI）；结果由 refresh 轮询取回 */
async function startGuardRefresh() {
  const b = bridge.value
  if (!b || guardFallback) return
  try {
    await execRead(b, `{ [ -f ${GUARD_BUSY} ] && exit 0; touch ${GUARD_BUSY}; if command -v setsid >/dev/null 2>&1; then setsid sh -c 'sh ${MOD}/engine/guard_stats.sh ${guardDate.value || ''} 2>/dev/null' > ${GUARD_OUT}.tmp 2>&1; else sh -c 'sh ${MOD}/engine/guard_stats.sh ${guardDate.value || ''} 2>/dev/null' > ${GUARD_OUT}.tmp 2>&1; fi; mv -f ${GUARD_OUT}.tmp ${GUARD_OUT}; mv -f ${GUARD_BUSY} ${GUARD_BUSY}.done; } >/dev/null 2>&1 & echo STARTED`)
  } catch { /* 忽略：由 refresh 轮询兜底 */ }
}

/** 直读模式（同步阻塞 ~3s）：仅当后台分离失败/被管理器杀掉时使用 */
async function syncMemRefresh() {
  const b = bridge.value
  if (!b || memLoading.value) return
  memLoading.value = true
  try {
    const mb = await execReadBatch(b,
      `printf '\\n@@SEG:m@@\\n'; sh ${MOD}/engine/memtop.sh 2>/dev/null; printf '\\n@@SEG:f@@\\n'; sh ${MOD}/engine/frozencap.sh 2>/dev/null`)
    const rows = parseMemtop(mb.m ?? '')
    if (rows.length) memtop.value = rows
    const fz = parseFrozen(mb.f ?? '')
    if (fz.count >= 0) frozen.value = fz
    if (rows.length) toast(`✓ 已刷新 · TOP${rows.length} · 墓碑 ${fz.count >= 0 ? frozen.value?.count : '—'} 个`)
    else toast('刷新完成，但未读到内存数据', false)
  } catch (e) { toast('刷新失败: ' + String(e).slice(0, 60), false) } finally { memLoading.value = false }
}

/** 刷新按钮/开屏入口：默认后台模式 */
function loadMem() { if (memFallback) { void syncMemRefresh() } else { void startMemRefresh() } }

/** v1.1.0 一键释放: touch force_reclaim 旗标, 回读验证, 引擎≤8s执行; 9s后再拉观测 */
async function releaseNow() {
  const b = bridge.value
  if (!b) { error.value = '无 KSU 桥'; return }
  freeing.value = true
  try {
    const r = await execRead(b, `touch ${MOD}/data/force_reclaim && echo TRIG`)
    if (r.includes('TRIG')) {
      toast('✓ 已触发释放，引擎 ≤8 秒执行')
      window.setTimeout(() => { loadMem() }, 9000)
    } else toast('触发失败: ' + (r.trim() || '空回读'), false)
  } catch (e) { toast(String(e), false) } finally { freeing.value = false }
}

/** 设置页模式开关: 写 memory.json mode → 30s 桥自动生效(热加载) */
async function setGuardMode(toGuard: boolean) {
  const b = bridge.value
  if (!b) { error.value = '无 KSU 桥'; return }
  const target = toGuard ? 'guard' : 'observe'
  try {
    await execRead(b, `sed -i 's/"mode": *"[a-z]*"/"mode": "${target}"/' ${MOD}/config/memory.json`)
    const back = await execRead(b, `grep -o '"mode": "[a-z]*"' ${MOD}/config/memory.json`)
    if (back.includes(target)) {
      if (guard.value) guard.value = { ...guard.value, mode: target }
      error.value = ''
      alert(`已切换为 ${target}，30 秒内经配置桥生效`)
    } else error.value = '模式切换失败: ' + (back.trim() || '空回读')
  } catch (e) { error.value = String(e) }
}

/** 设置页激进回收: sed节内定向写(引擎每轮热读≤8s), 回读验证(防空回读教训) */
async function setReclaim(patch: { aggressive?: boolean; depth?: string }) {
  const b = bridge.value
  if (!b) { error.value = '无 KSU 桥'; return }
  try {
    if (patch.aggressive !== undefined) {
      const to = patch.aggressive ? 'true' : 'false'
      const from = patch.aggressive ? 'false' : 'true'
      await execRead(b, `sed -i '/"reclaim"/,/}/s/"aggressive": ${from}/"aggressive": ${to}/' ${MOD}/config/memory.json`)
    }
    if (patch.depth !== undefined) {
      await execRead(b, `sed -i '/"reclaim"/,/}/s/"depth": "[a-z]*"/"depth": "${patch.depth}"/' ${MOD}/config/memory.json`)
    }
    const back = await execRead(b, `sed -n '/"reclaim"/,/}/p' ${MOD}/config/memory.json`)
    const ok = patch.depth !== undefined
      ? back.includes(`"depth": "${patch.depth}"`)
      : back.includes(`"aggressive": ${patch.aggressive ? 'true' : 'false'}`)
    if (ok) {
      error.value = ''
      if (guard.value) guard.value = { ...guard.value,
        reclaimAggressive: back.includes('"aggressive": true'),
        reclaimDepth: (back.match(/"depth": "([a-z]*)"/) ?? [])[1] ?? 'cached' }
    } else error.value = '激进回收写入失败: 回读不符'
  } catch (e) { error.value = String(e) }
}

/** URO 桥接开关：写开关文件（URO 每个策略边界热读），回读验证 */
const URO_CONF = '/sdcard/Android/UnifiedRootOptimizer/uro.conf'
async function setUroBridge(v: boolean) {
  const b = bridge.value
  if (!b) { error.value = '无 KSU 桥'; return }
  const val = v ? 1 : 0
  try {
    await execRead(b, `mkdir -p /sdcard/Android/UnifiedRootOptimizer && echo BRIDGE_ENFORCE=${val} > ${URO_CONF}`)
    const back = await execRead(b, `grep '^BRIDGE_ENFORCE=' ${URO_CONF} 2>/dev/null`)
    if (back.trim() === `BRIDGE_ENFORCE=${val}`) {
      error.value = ''
      alert(v ? '已开启：URO 下个策略事件起接管回收策略' : '已关闭：URO 停止写入，本页手动控制生效')
    } else error.value = 'URO 桥接开关写入失败: 回读不符'
  } catch (e) { error.value = String(e) }
}

/* boot-after-paint: ksu.exec 同步阻塞 JS 线程, 若在 onMounted 直接跑多条桥命令
   (含 memtop ~3s), WebView 首帧会被推迟 5s+ (灰屏根因)。
   panel-perf: 首帧后先拉一次主数据; 内存观测延后 1.2s 且后台执行; 轮询在页面隐藏时暂停。 */
function onVis() { if (!document.hidden) void refresh() }
onMounted(() => {
  initTheme()
  document.addEventListener('visibilitychange', onVis)
  requestAnimationFrame(() => setTimeout(() => {
    void refresh()
    void startGuardRefresh()
    window.setTimeout(() => { loadMem() }, 1200)
    window.setTimeout(() => { void refresh() }, 1600)
    timer = window.setInterval(() => { if (!document.hidden) void refresh() }, 5000)
  }, 0))
})
onUnmounted(() => {
  if (timer) clearInterval(timer)
  document.removeEventListener('visibilitychange', onVis)
})

</script>

<template>
  <div class="hd">
    <div>
      <h1>COSMemory</h1>
      <div class="sub">
        <template v-if="engineUp === null">连接中…</template>
        <template v-else-if="engineUp">内存管理 · 引擎运行中</template>
        <template v-else>内存管理 · 引擎未运行</template>
      </div>
    </div>
    <div class="dot" :class="engineUp ? 'on' : 'off'" />
  </div>

  <div class="wrap">
    <div v-if="error" class="alert" :class="{ ok: error.includes('已切换') }">{{ error }}</div>

    <DashboardView v-if="activeTab === 'dash'"
      :stats="stats" :engine-up="engineUp" :caps-ok="capsOk" :white="white" :guard="guard"
      :memtop="memtop" :frozen="frozen" :mem-loading="memLoading" :freeing="freeing"
      @refresh-mem="loadMem" @release="releaseNow" />
    <DefenseView v-else-if="activeTab === 'defense'"
      :guard="guard" @pick="onPickDate"
      :listRaw="listRaw" :mod="MOD" @edited="refresh" />
    <SystemView v-else-if="activeTab === 'system'"
      :stats="stats" :caps-entries="capsEntries" />
    <ListView v-else-if="activeTab === 'list'"
      :white="white" :list-raw="listRaw"
      :freezeList="guard?.freezeList ?? []"
      :mod="MOD" @edited="refresh" />
    <SettingsView v-else
      :log-tail="logTail" :guard="guard" :diag-busy="diagBusy" @set-guard-mode="setGuardMode" @set-reclaim="setReclaim" @set-uro-bridge="setUroBridge" @export-diag="exportDiag" />
  </div>

  <div v-if="toastMsg" class="toast" :class="{ ok: toastOk }">{{ toastMsg }}</div>

  <!-- 底部导航 5 键 -->
  <nav class="tabbar">
    <button v-for="t in TABS" :key="t.id" :class="{ on: activeTab === t.id }"
      @click="goTab(t.id)">
      <svg class="si" viewBox="0 0 24 24"><use :href="'#' + t.icon" /></svg>
      <span>{{ t.label }}</span>
    </button>
  </nav>
</template>
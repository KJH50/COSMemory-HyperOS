#!/system/bin/sh
# COSMemory HyperOS 健康体检（只读，不改动任何东西）
# 用法：sh hyperos-healthcheck.sh 2>&1 | tee /sdcard/cosmem-healthcheck.txt

MOD=/data/adb/modules/COSMemory

echo '==== COSMemory 健康体检 ===='
echo "时间: $(date)"
echo

echo '[1] 引擎进程:'
if pgrep -f 'engine/memory.sh' >/dev/null 2>&1; then
    ps -A -o PID,ETIME,ARGS 2>/dev/null | grep 'engine/memory.sh' | grep -v grep
else
    echo '  !! 引擎未运行'
fi
echo

echo '[2] 统计:'
S="$MOD/data"
if [ -f "$S/stats.log" ]; then
    echo "  总行数: $(wc -l < "$S/stats.log")"
    echo "  FAILED=1/2 次数: $(grep -c 'FAILED=[12]' "$S/stats.log")"
    echo "  KEEPADJ 次数: $(grep -c 'KEEPADJ' "$S/stats.log")"
    echo '  最后3条:'
    tail -3 "$S/stats.log" | sed 's/^/    /'
else
    echo '  !! 无 stats.log'
fi
echo

echo '[3] 防线桥:'
if [ -f /data/system/cosmem/guard.conf ]; then
    grep -E 'MODE|BLOCK' /data/system/cosmem/guard.conf | sed 's/^/  /'
    echo "  白名单条数: $(grep -c 'WHITE' /data/system/cosmem/guard.conf)"
else
    echo '  !! 桥未生成'
fi
echo

echo '[4] 防线日志（最近3条）:'
G="$MOD/data/guard/$(date +%F).log"
if [ -f "$G" ]; then
    tail -3 "$G" | sed 's/^/  /'
else
    echo '  (今日无日志)'
fi
echo

echo '[5] 名单文件:'
L='/sdcard/Android/COSMemory/名单列表.conf'
if [ -f "$L" ]; then
    echo "  条数: $(grep -c . "$L")"
else
    echo '  (未找到)'
fi
echo

echo '[6] 内存与压力:'
free -m 2>/dev/null | head -3 | sed 's/^/  /'
sed 's/^/  /' /proc/pressure/memory
echo

echo '==== 完 ===='

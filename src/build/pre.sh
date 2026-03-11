#!/bin/sh

wk="$1"
mm="$2"
yyyy="$3"

# 辅助函数：检查路径中是否包含斜杠
hasfwslash() {
    case "$1" in
    */*) echo yes ;;
    *)   echo no ;;
    esac
}

burl="https://cfstore.rethinkdns.com/blocklists"
codec="u6"
f="basicconfig.json"
f2="filetag.json"
cwd=$(pwd)

# 输出路径
out="./src/${codec}-${f}"
out2="./src/${codec}-${f2}"
name=$(uname)

# --- 1. 获取默认日期变量 ---
if [ "$name" = "Darwin" ]; then
    now=$(date -u +"%s")
    day=$(date -r "$now" "+%d")
    yyyydef=$(date -r "$now" "+%Y")
    mmdef=$(date -r "$now" "+%m")
else
    now=$(date --utc +"%s")
    day=$(date -d "@$now" "+%d")
    yyyydef=$(date -d "@$now" "+%Y")
    mmdef=$(date -d "@$now" "+%m")
fi

day=${day#0}
mmdef=${mmdef#0}
wkdef=$(((day + 7 - 1) / 7))

# 如果没传参数，使用默认值
: "${wk:=$wkdef}" "${mm:=$mmdef}" "${yyyy:=$yyyydef}"

# --- 2. 核心尝试循环 ---
max=4
for i in $(seq 0 $max)
do
    # 构造当前尝试的时间戳路径格式：YYYY/MM-WK (例如 2023/10-1)
    current_ts="${yyyy}/${mm}-${wk}"
    
    echo "x=== pre.sh: $i try $current_ts at $now from $cwd"

    # 如果文件已存在则跳过（除非你想每次强制更新）
    if [ -f "${out}" ] || [ -L "${out}" ]; then
        echo "=x== pre.sh: file already exists ${out}"
        exit 0
    fi

    # 尝试下载配置文件
    # 使用 curl 替代 wget: -f (失败报错), -s (静默), -L (重定向), -o (输出文件)
    curl -fsSL "${burl}/${current_ts}/${codec}/${f}" -o "${out}"
    wcode=$?

    if [ $wcode -eq 0 ]; then
        # 从刚下载好的 $out (basicconfig.json) 中提取更精确的时间戳
        # 原逻辑通过逗号分隔提取第 9 或第 8 个字段
        fulltimestamp=$(cut -d"," -f9 "$out" | cut -d":" -f2 | tr -dc '0-9/')
        
        if [ "$(hasfwslash "$fulltimestamp")" = "no" ]; then
            fulltimestamp=$(cut -d"," -f8 "$out" | cut -d":" -f2 | tr -dc '0-9/')
        fi

        echo "==x= pre.sh: $i ok; extracted fulltimestamp: ${fulltimestamp}"

        # 使用提取到的精确时间戳下载 filetag.json
        curl -fsSL "${burl}/${fulltimestamp}/${codec}/${f2}" -o "${out2}"
        wcode2=$?

        if [ $wcode2 -eq 0 ]; then
            echo "===x pre.sh: $i filetag download success"
            exit 0
        else
            echo "===x pre.sh: $i filetag download failed, cleaning up"
            rm -f "${out}" "${out2}"
        fi
    else
        # 如果下载失败，清理可能产生的空文件或残余
        rm -f "${out}"
        echo "==x= pre.sh: $i not found ($current_ts)"
    fi

    # --- 3. 日期回溯逻辑 ---
    wk=$((wk - 1))
    if [ $wk -le 0 ]; then
        wk="5"
        mm=$((mm - 1))
    fi
    if [ $mm -le 0 ]; then
        mm="12"
        yyyy=$((yyyy - 1))
    fi
done

echo "FAILED: Could not find a valid blocklist in the last 5 attempts."
exit 1

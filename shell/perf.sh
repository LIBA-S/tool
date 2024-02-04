#!/bin/bash

if (($# != 1))
then
  echo "usage: pid"
  exit 1
fi

pid=$1
max_disk_usage=16            #以MB为单位
max_file_age=30              #以秒为单位
max_nohup_size=1             #以MB为单位
nohup_out_file="nohup.out"

# 初始化 perf_files 数组为当前已有的 perf 文件列表
if ls perf.${pid}.* 1> /dev/null 2>&1; then
  perf_files=($(ls -1 perf.${pid}.* | sort -t. -k3 -n))
  truncate_index=${perf_files[0]##*.}
  write_index=${perf_files[-1]##*.}
  current_disk_usage=$(du -b --total perf.${pid}.* | grep total | awk '{print $1}')
  current_disk_usage_mb=$((current_disk_usage / 1024 / 1024))
  echo "perf文件起始编号为: ${truncate_index}, 最新编号为: ${write_index}, 文件总数为: ${#perf_files[@]}, 磁盘空间占用为: ${current_disk_usage_mb}MB."
else
  truncate_index=0
  write_index=-1
fi

write_index=$((write_index + 1))

while true
do
  perf_file="perf.${pid}.${write_index}"
  perf record -p $pid -g -o $perf_file sleep 5 || { echo "Error: Process ID $pid does not exist."; exit 1; }
  perf_file_size=$(stat -c%s $perf_file)
  current_disk_usage=$((current_disk_usage + perf_file_size))
  current_disk_usage_mb=$((current_disk_usage / 1024 / 1024))
  write_index=`expr $write_index + 1`

  # 当满足以下两个条件时，删除最旧的perf文件:
  # 1. 当前目录磁盘空间，超过了指定阈值
  # 2. perf文件创建时间，超过了指定保存时间上限
  oldest_perf_file=
  should_delete_oldest_perf_file=false

  # 文件编号可能不连续，查找第一个存在的perf文件
  for ((i = ${truncate_index}; i < ${write_index}; i++))
  do
    oldest_perf_file="perf.${pid}.${i}"
    if [ -f $oldest_perf_file ]
    then
      if ((current_disk_usage_mb > max_disk_usage))
      then
        should_delete_oldest_perf_file=true
        reason="磁盘使用量超过设定阈值: ${max_disk_usage}MB, 当前磁盘使用量为: ${current_disk_usage_mb}MB."
      else
        file_age=$(expr $(date +%s) - $(stat -c %Y $oldest_perf_file))
        if ((file_age > max_file_age))
        then
          should_delete_oldest_perf_file=true
          reason="文件留存时间超过设置阈值: ${max_file_age}s."
        fi
      fi
      break
    fi
  done

  if $should_delete_oldest_perf_file
  then
    echo "${reason} 清理文件: ${oldest_perf_file}."
    oldest_perf_file_size=$(stat -c%s $oldest_perf_file)
    rm $oldest_perf_file

    truncate_index=$((truncate_index + 1))
    current_disk_usage=$((current_disk_usage - oldest_perf_file_size))
  fi

  # 检查并控制nohup输出文件大小
  if [ -f $nohup_out_file ]
  then
    nohup_file_size=$(du -m ${nohup_out_file} | awk '{print $1}')
    if ((nohup_file_size > max_nohup_size))
    then
      echo "nohup文件大小超过阈值: ${max_nohup_size}MB, 清理历史数据" > $nohup_out_file
    fi
  fi
done

#!/bin/bash
# RK3566 / RK3568 (RKNN Lite) performance tuning – based on rknn_model_zoo scaling_frequency.sh
set -e

echo 1 > /sys/devices/system/cpu/cpu0/cpuidle/state1/disable
echo 1 > /sys/devices/system/cpu/cpu1/cpuidle/state1/disable
echo 1 > /sys/devices/system/cpu/cpu2/cpuidle/state1/disable
echo 1 > /sys/devices/system/cpu/cpu3/cpuidle/state1/disable

CPU_freq=1800000
NPU_freq=800000000
DDR_freq=1056000000

echo "CPU available frequencies:"
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies 2>/dev/null || true
echo "Fix CPU max frequency:"
echo userspace > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
echo ${CPU_freq} > /sys/devices/system/cpu/cpufreq/policy0/scaling_setspeed
cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq

if [ -e /sys/class/devfreq/fde40000.npu/governor ]; then
    echo "NPU available frequencies:"
    cat /sys/class/devfreq/fde40000.npu/available_frequencies
    echo "Fix NPU max frequency:"
    echo userspace > /sys/class/devfreq/fde40000.npu/governor
    echo ${NPU_freq} > /sys/class/devfreq/fde40000.npu/userspace/set_freq
    cat /sys/class/devfreq/fde40000.npu/cur_freq
elif [ -e /sys/kernel/debug/rknpu/freq ]; then
    echo "Fix NPU max frequency (debugfs):"
    echo ${NPU_freq} > /sys/kernel/debug/rknpu/freq
    cat /sys/kernel/debug/rknpu/freq
else
    echo "Warning: RK3566 NPU devfreq node not found (check device-tree / rknpu driver)"
fi

echo "DDR available frequencies:"
cat /sys/class/devfreq/dmc/available_frequencies 2>/dev/null || true
echo "Fix DDR max frequency:"
echo userspace > /sys/class/devfreq/dmc/governor
echo ${DDR_freq} > /sys/class/devfreq/dmc/userspace/set_freq
cat /sys/class/devfreq/dmc/cur_freq

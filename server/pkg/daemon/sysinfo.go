package daemon

import (
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

var cpuSampleState struct {
	mu       sync.Mutex
	havePrev bool
	prevIdle uint64
	prevTot  uint64
}

// ReadSystemUsage samples host CPU and RAM utilization percentages (0..100).
func ReadSystemUsage() (cpuPercent int, ramPercent int) {
	ramPercent = readMemPercent()
	cpuPercent = readCPUPercent()
	return cpuPercent, ramPercent
}

func readMemPercent() int {
	data, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return 0
	}
	var totalKB, availKB uint64
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		switch fields[0] {
		case "MemTotal:":
			totalKB, _ = strconv.ParseUint(fields[1], 10, 64)
		case "MemAvailable:":
			availKB, _ = strconv.ParseUint(fields[1], 10, 64)
		}
	}
	if totalKB == 0 || availKB > totalKB {
		return 0
	}
	usedPct := int(((totalKB - availKB) * 100) / totalKB)
	if usedPct < 0 {
		return 0
	}
	if usedPct > 100 {
		return 100
	}
	return usedPct
}

func readProcStatTotals() (idle uint64, total uint64, ok bool) {
	data, err := os.ReadFile("/proc/stat")
	if err != nil {
		return 0, 0, false
	}
	for _, line := range strings.Split(string(data), "\n") {
		if !strings.HasPrefix(line, "cpu ") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 5 {
			return 0, 0, false
		}
		for i := 1; i < len(fields); i++ {
			v, err := strconv.ParseUint(fields[i], 10, 64)
			if err != nil {
				continue
			}
			total += v
			if i == 4 || i == 5 { // idle + iowait
				idle += v
			}
		}
		return idle, total, total > 0
	}
	return 0, 0, false
}

func readCPUPercent() int {
	cpuSampleState.mu.Lock()
	defer cpuSampleState.mu.Unlock()

	if !cpuSampleState.havePrev {
		idle1, tot1, ok1 := readProcStatTotals()
		if !ok1 {
			return 0
		}
		time.Sleep(80 * time.Millisecond)
		idle2, tot2, ok2 := readProcStatTotals()
		if !ok2 || tot2 <= tot1 {
			cpuSampleState.prevIdle = idle1
			cpuSampleState.prevTot = tot1
			cpuSampleState.havePrev = true
			return 0
		}
		cpuSampleState.prevIdle = idle2
		cpuSampleState.prevTot = tot2
		cpuSampleState.havePrev = true
		return calcCPUPct(idle1, tot1, idle2, tot2)
	}

	idleNow, totNow, ok := readProcStatTotals()
	if !ok || totNow <= cpuSampleState.prevTot {
		return 0
	}
	pct := calcCPUPct(cpuSampleState.prevIdle, cpuSampleState.prevTot, idleNow, totNow)
	cpuSampleState.prevIdle = idleNow
	cpuSampleState.prevTot = totNow
	return pct
}

func calcCPUPct(idle1, tot1, idle2, tot2 uint64) int {
	dTot := tot2 - tot1
	if dTot == 0 {
		return 0
	}
	var dIdle uint64
	if idle2 > idle1 {
		dIdle = idle2 - idle1
	}
	if dIdle > dTot {
		dIdle = dTot
	}
	pct := int(((dTot - dIdle) * 100) / dTot)
	if pct < 0 {
		return 0
	}
	if pct > 100 {
		return 100
	}
	return pct
}

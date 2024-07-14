//go:build darwin

package gpu

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework Foundation -framework CoreGraphics -framework Metal
#include "gpu_info_darwin.h"
*/
import "C"
import (
	"runtime"

	"github.com/ollama/ollama/format"
)

const (
	metalMinimumMemory = 512 * format.MebiByte
)

func GetGPUInfo() GpuInfoList {
	gpu_info := GpuInfo{ID: "0"}
	if runtime.GOARCH == "amd64" {
		gpu_info.Library = "vulkan"
	} else {
		gpu_info.Library = "metal"
	}
	gpu_info.TotalMemory = uint64(C.getRecommendedMaxVRAM())

	// TODO is there a way to gather actual allocated video memory? (currentAllocatedSize doesn't work)
	gpu_info.FreeMemory = gpu_info.TotalMemory

	gpu_info.MinimumMemory = metalMinimumMemory
	return []GpuInfo{gpu_info}
}

func GetCPUInfo() GpuInfoList {
	mem, _ := GetCPUMem()
	return []GpuInfo{
		{
			Library: "cpu",
			Variant: GetCPUCapability(),
			memInfo: mem,
		},
	}
}

func GetCPUMem() (memInfo, error) {
	return memInfo{
		TotalMemory: uint64(C.getPhysicalMemory()),
		FreeMemory:  uint64(C.getFreeMemory()),
		// FreeSwap omitted as Darwin uses dynamic paging
	}, nil
}

func (l GpuInfoList) GetVisibleDevicesEnv() (string, string) {
	// No-op on darwin
	return "", ""
}

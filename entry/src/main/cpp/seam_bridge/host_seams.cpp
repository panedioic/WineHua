// ============================================================================
// host_seams — entry 侧的接缝适配器与弱符号定义 (方案 B1b)
//
// entry.so 在此定义并填充两个弱符号 (libhgs.so 弱引用消费, registry.h):
//   Hgs_zeroCopyBackend — GraphicsBroker 适配器 (ZC 查询/挂载/ready marker)
//   Hgs_hostHooks       — wine_process 适配器 (桌面 shell 进程簿记)
// Hgs_sessionControl 由 libhgs.so 定义 (entry 经同一弱符号消费, 见
// wine_launch.cpp / napi_init.cpp 的 stopClient/stopAll)。
//
// 注入机制: 链接期弱符号绑定 (同进程 NAPI so 互解析, smoke_napi 先例),
// 无 dlopen/dlsym。
// ============================================================================
#include "seam/registry.h"

#include "graphics/graphics_broker.h"
#include "proc/wine_process.h"

#include <cstddef>

namespace {

// ── ZeroCopyBackend → GraphicsBroker 转发 ──────────────────────────────────
class BrokerZeroCopyBackend : public hgs::seam::ZeroCopyBackend
{
public:
    bool IsZeroCopyActive() const override
    {
        return winehua::GraphicsBroker::GetInstance().GetState().active ==
               winehua::GraphicsBackend::Virgl;
    }
    bool IsVulkanPresentMode() const override
    {
        return winehua::GraphicsBroker::GetInstance().IsVulkanPresentMode();
    }
    bool QueryZeroCopySurfaces(std::vector<hgs::seam::ZeroCopySurfaceInfo> &surfaces) const override
    {
        std::vector<winehua::ZeroCopySurfaceInfo> in;
        if (!winehua::GraphicsBroker::GetInstance().QueryZeroCopySurfaces(in)) {
            return false;
        }
        // POD 布局契约一致 (registry 契约), 逐字段拷贝
        surfaces.clear();
        surfaces.reserve(in.size());
        for (const auto &e : in) {
            hgs::seam::ZeroCopySurfaceInfo o;
            o.surfaceKey = e.surfaceKey;
            o.clientPid = e.clientPid;
            o.surfaceId = e.surfaceId;
            o.width = e.width;
            o.height = e.height;
            o.serial = e.serial;
            o.attached = e.attached;
            o.vulkan = e.vulkan;
            surfaces.push_back(o);
        }
        return true;
    }
    bool AttachZeroCopyTarget(uint64_t surfaceKey, OHNativeWindow *producerWindow,
                              uint64_t framePeriodNs) override
    {
        return winehua::GraphicsBroker::GetInstance().AttachZeroCopyTarget(
            surfaceKey, producerWindow, framePeriodNs);
    }
    void DetachZeroCopyTarget(uint64_t surfaceKey) override
    {
        winehua::GraphicsBroker::GetInstance().DetachZeroCopyTarget(surfaceKey);
    }
    void SetZeroCopyFramePeriod(uint64_t surfaceKey, uint64_t framePeriodNs) override
    {
        winehua::GraphicsBroker::GetInstance().SetZeroCopyFramePeriod(surfaceKey, framePeriodNs);
    }
    void SetZeroCopySurfaceReady(uint64_t surfaceKey, bool ready) override
    {
        winehua::GraphicsBroker::GetInstance().SetZeroCopySurfaceReady(surfaceKey, ready);
    }
};

// ── HostLifecycleHooks → wine_process 转发 ─────────────────────────────────
class WineHostHooks : public hgs::seam::HostLifecycleHooks
{
public:
    void OnDesktopRootAppeared() override
    {
        // 桌面 root 首次出现: 标记桌面 shell 基础进程 (ArkTS 防误操作结束)
        MarkDesktopShellProcesses();
    }
    void OnDesktopSessionEnded() override
    {
        // 桌面会话由 explorer 主动结束: ProcMon 按 state:stopped 收口
        MarkDesktopSessionEnded();
    }
};

BrokerZeroCopyBackend g_zcBackend;
WineHostHooks g_hostHooks;

} // namespace

// ── 弱符号强定义 (libhgs.so 加载期绑定) ────────────────────────────────────
extern "C" {
hgs::seam::ZeroCopyBackend *Hgs_zeroCopyBackend = &g_zcBackend;
hgs::seam::HostLifecycleHooks *Hgs_hostHooks = &g_hostHooks;
// SessionControl 槽位: libhgs.so 加载时经构造器写入 (registry.h 槽位模式)
void *Hgs_sessionControlSlot = nullptr;
}

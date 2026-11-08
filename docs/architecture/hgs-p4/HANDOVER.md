# HGS 双协议服务交接

更新于 2026-11-08。P3 和 P4 的主要实现与真机验收已完成，接手从 P5 双宿主收口开始。[迁移规划与 P4 验收](../hgs-dual-protocol-service-plan.md) · [P3 实施记录](../hgs-p3/README.md)

## 1. 仓库和版本

| 仓库 | 发布位置 | 工作树 | 实现基点 |
| --- | --- | --- | --- |
| HGS | `panedioic/hgs:main` | `/workspace/WineHua-root/WineHua/hgs` | `b6c71ef70f014f402f491abd190eea6d063b7d21` |
| WineHua | `panedioic/WineHua:feature/hgs-dual-protocol` | `/workspace/WineHua-root/hgs-integration` | 应用和 gitlink `1c24d249d`，P3/P4 验收文档 `262d2b912` |
| 上游对照 | WineHua 冻结快照 | `/workspace/WineHua-root/hgs-upstream-baseline` | `a001e6d0c`，仅作行为和补丁对照 |
| BetterSH | `feature/hgs-migration` | `/workspace/BetterSH` | P5 接手时重新核对 HEAD、HGS gitlink 和本地修改 |

HGS 的发布批次为 `3f0fc15` 服务核心、`23a9763` 默认窗口宿主、`03b34b8` API 文档。合并提交 `b6c71ef` 同时保留了远端 `a388c9e` 的 XKB 资源路径修复。WineHua 的 `hgs` gitlink 已指向该合并提交。发布新 HGS 提交时，先推 HGS `main` 并确认对象能从远端获取，再更新宿主 gitlink。WineHua 本轮通过 SSH 向既有集成分支推送，`origin` 保留原配置。

本地的 `hgs-integration/hgs` 是 HGS 仓库的 detached linked worktree，与 `WineHua/hgs` 共用对象库。在已有工作区先查看 `git worktree list` 和各树的 `git status`，把 HGS 实现提交放在 `WineHua/hgs` 的 `main`。全新 clone 可直接按 WineHua gitlink 初始化 HGS。旧 `feature/hgs-har-scaffold` 工作树及其未跟踪的原交接文档是历史输入，和这份发布记录对应不同阶段。第三方子模块中的本地修改也要在独立工作树处理。

## 2. 图形栈与职责

1. **服务生命周期和端点。** `HgsService.start({ protocols, runtimeDir, ... })` 通过 NAPI 在后台启动 Runtime。Wayland 注册实际 Unix socket，X11 启动 HGS 自己的 Xwayland NCP，待 XWM 和可选 XIM 就绪后发布端点。宿主用 `HgsSession.clientEnvironment(protocol)` 给每个子进程设置或清除显示变量。两套监听可在同一进程并行，客户端退出后仍可重连，服务通过显式 stop 回收线程、socket 和自身的 helper。
2. **窗口身份与输入。** Runtime 将后端、连接、原生对象、对象代次和会话 epoch 映射到不透明字符串 WindowId。ArkTS 页面和宿主使用 WindowId + epoch，避免 XID 或 Wayland 对象编号复用后误操作。OHOS 焦点变化通过 `controlWindow` 路由给对应后端，切换时先向原窗口投递 blur 并释放输入归属。X11 popup 有独立 ID，优先使用 transient 父窗，同连接的 override-redirect 菜单可关联当前焦点窗。动态模态更新来自 XWM 的 EWMH 请求。
3. **OHOS 默认窗口宿主。** `HgsWindowHostService.startService(stage, options)` 使用 per-window 组合。Wayland 继续用 multiton Ability 与旧的 XComponent 渲染路径，服务模式以每个实例的 LocalStorage 传递 toplevel ID，规避异步加载顺序。X11 顶层窗使用 launcher Stage 的子窗，popup 或 transient 子窗挂到其父宿主窗口。两类包装页在服务模式均使用 `@Entry({ useSharedStorage: true })`。OHOS 在提升 X11 子窗时可能同时提升 launcher 主窗，做并排操作验证时应让 GTK 不被 launcher 覆盖。[默认宿主接入](https://github.com/panedioic/hgs/blob/b6c71ef70f014f402f491abd190eea6d063b7d21/docs/api/service-api.md)
4. **X11 CPU 与 GPU 帧。** 常规 Xwayland 缓冲经 pixman 写入绑定的 OHOS Surface。WineHua 在启动服务前把 GraphicsBroker 适配为可选 `ExternalFrameProvider`。HGS 用 XID、客户端 PID 和窗口代次匹配 producer，经 OH_NativeImage 和 EGL 呈现。帧源未就绪、出错或解绑时使用 CPU 路径。首次成功提交将该 Surface 代次的 `framePresented` 设为 true，旧 Surface 的解绑带自身 ID，防止误解绑新绑定。
5. **WineHua 特有策略。** WineHua 集成包的 X11 仍由 `winehua.hgsX11Probe=1` 选择，常规入口仍使用 Wayland。Wine 子进程经 broker 获取真实端点的环境。虚拟桌面按物理屏幕与 Wine 有效缩放计算逻辑输出，Wine explorer 的 `/desktop=shell,WxH` 使用该值。真正绘制窗口的 explorer 可能是 launcher 再经 broker 派生的 NCP。WineHua 用 Unix socket 对端 PID 记录这层关系，匹配标题与窗口进程，并等待首帧后发出 `evt:desktop-ready`。X11 中文输入经系统 IME 确认文本、HGS XIM 和 Wine 编辑控件，候选及预编辑界面由系统 IME 管理。

### 查代码时从这些入口开始

| 位置 | 作用 |
| --- | --- |
| `hgs/src/main/ets/api/HgsService.ets`、`hgs/src/main/cpp/runtime/service_runtime.cpp` | 启停、端点、事件、窗口与输入分发 |
| `hgs/src/main/cpp/backends/xwayland/runtime/{session.c,x11_endpoint.cpp}` | XWM、X11 seat、父窗、模态、首帧、认证与监听 |
| `hgs/src/main/cpp/backends/wayland/legacy_wayland_backend.cpp` | Wayland 兼容后端及事件到服务窗口的映射 |
| `hgs/src/main/ets/service/{HgsWindowHostService,HgsServiceWindowHost}.ets` | 默认宿主、OHOS 窗口创建及控制回路 |
| `hgs/src/main/cpp/include/hgs/external_frames.h`、`hgs/src/main/cpp/backends/xwayland/external_frame_bridge.cpp` | 外部帧提供者契约、匹配和回退 |
| `entry/src/main/cpp/seam_bridge/host_seams.cpp`、`entry/src/main/cpp/graphics/graphics_broker.cpp` | Wine 端 GPU 适配 |
| `entry/src/main/ets/service/{WineEnvService,X11ProbeWindowHost}.ets`、`entry/src/main/cpp/proc/{broker,wine_process}.cpp` | Wine 会话、环境、桌面就绪和 launcher 关系 |

## 3. 本地复现

### 主机测试

```sh
make -C /workspace/WineHua-root/WineHua/hgs/tests test
make -C /workspace/WineHua-root/hgs-integration test
```

发布前两套主机测试均通过。HGS 的 `socket_listener_test` 使用真实 Unix socket。在禁止 bind 的沙箱中，该用例会在 `one.Open(path)` 失败，需要在允许本地 socket 的环境中复验。发布前也检查了两个 XKB 打包脚本的语法和目录契约。

### 构建输入

- Harmony SDK 在本机 `/workspace/harmony-sdk`。P2 SDK 的 ARM64 OHOS 构建前缀为 `WineHua/build/hgs-p2/deps`，包含 wlroots 0.20.2 和 Xwayland 24.1.13 的配套头库。XIM 前缀为 `WineHua/build/hgs-p3/xim-verify/prefix`，含 xcb-imdkit 1.0.9。复用目录前核对 [P0 依赖锁](../hgs-p0/dependencies.json) 和 [HGS X11 构建说明](https://github.com/panedioic/hgs/blob/b6c71ef70f014f402f491abd190eea6d063b7d21/docs/integration/x11.md)。
- HAR 的 native CMake 参数需显式传 `-DHGS_BUILD_X11=ON -DHGS_X11_DEPS_ROOT=<ARM64 SDK>`。启用 XIM 时再传 `-DHGS_BUILD_XIM=ON -DHGS_XIM_DEPS_ROOT=<XIM SDK>`。打包 HGS 的原生 helper 和 ELF 运行依赖时，同一 SONAME 只保留一套匹配库。Wine 的 Box64 动态加载还需通过 `stage_runtime.py --dlopen-library` 加入 `libXext.so.6` 和 `libX11-xcb.so.1`。
- 远端合入的 `pack_xkb_data.sh` 产物现在使用标准大写 `usr/share/X11/xkb`。BetterSH 和 GTK 测试如复用旧的 tar/sysroot，需重打资源并核对实际 `XKB_CONFIG_ROOT`。X11 的 `pack_resources.sh` 输入是包含 `rules/evdev` 的 xkb 目录，输出独立的 `hgs-x11/xkb/` 和 `hgs-x11/keymap.xkm`。Wine XIM 测试还需 guest Xlib locale 数据。
- 应用包在独立 stage 中构建。P3 桌面复验的 `stage-build.sh` 与 `input-x11.txt` 位于下表桌面证据目录。P4 的独立宿主工程、HAR、GTK/Xlib NCP 探针及构建日志位于 `both-verify/minimal/` 与其父目录。GTK 探针需配套 GTK/GLib、可用的 Fontconfig 配置和字体。GTK 缺字体时曾产生非法几何和 Cairo surface 错误，应先排除资源问题。
- 本地 HAP 用现有测试签名材料签名，签名材料和产物保存在本机。真机测试使用隔离 Wine prefix。更换测试包前记录设备上的基线包，结束后恢复并启动基线，避免把最小宿主留在 WineHua 的测试包身份上。

### 真机证据

下表路径相对本机 `/workspace/WineHua-root/WineHua/build/`，同一行中省略目录的文件沿用前一个目录。这是原始日志、截图及隔离构建产物的位置，Git 中保存对应的阶段验收摘要。不同用例使用各自签名的测试包。

| 用例 | 证据及判断 |
| --- | --- |
| P2 X11 最小宿主 | `hgs-p2/minimal-final-report.log`。无 Wine 引擎的最小宿主启动 X11，真实客户端连接、输入、关闭、重连，覆盖双端点启动与失败回滚。 |
| P3 GDI 与常规输入 | `hgs-p3/input-win32-messages.txt`、`surface-screen-pixels.txt`、`surface-wayland-gdi-result.txt`。X11 记录 Win32 键鼠和屏幕像素；Wayland 对照记录 GDI 读回。 |
| P3 OpenGL/Vulkan | `hgs-p3/gpu-verify/wgl-flip-screen.jpeg`、`flip-trace.log`、`vulkan-fixed-final.json`、`gdi-fixed-result.txt`。OpenGL 四象限方向正确，Vulkan 呈现 840 帧，GDI 回退通过。Vulkan 图案为单色，方向未单独验证。 |
| P3 XIM | `hgs-p3/xim-verify/minimal-device-report.log`、`wine-e2e-result.txt`、`wine-e2e-editor.jpeg`。Xlib 验证焦点与重连，Wine 编辑控件收到两次系统拼音确认，最终 UTF-16 内容匹配。 |
| P3 虚拟桌面 | `hgs-p3/desktop-verify-pidmatch-20261108/device-coldstart-notepad-full.log`、`p3-notepad-coldstart.jpeg`。2880×1920 屏幕以 2 倍缩放得到 1440×960 逻辑输出，日志顺序为桌面首帧、desktop-ready、Notepad 接受启动，截图见可见子窗。 |
| P4 双协议输入和缩放 | `hgs-p4/both-verify/interactive-final.log`、`interactive-alternate2.jpeg`、`reconnect-x11-final.log`、`reconnect-gtk-resize.jpeg`。GTK 与 X11 同屏，X11 → GTK → X11 交替输入，X11 ConfigureNotify 记录 480×280 → 705×430。 |
| P4 popup、modal 与重连 | `hgs-p4/both-verify/interactive-popup-modal-final.log`、`modal-fix-final.log`、`modal-dynamic-{add,remove}-events.log`。点击命中 popup XID，模态窗拦截父窗输入并收到 WM_DELETE。重复映射及重连后模态标志一致，同一窗口动态切换模态后完成 Surface 重绑定。两路全关后仍在原 epoch 重新建窗。 |
| 设备恢复 | `hgs-p4/both-verify/modal-dynamic-restore-install.log`、`modal-dynamic-restore-start.log`。最后一轮后安装并启动了 `hgs-p1/2026-11-06/winehua-p1-final-signed.hap`。 |

## 4. 已知边界

- 目前支持同进程双监听和各自独立窗口。X11 的 Wine 虚拟桌面由 Wine 自己组合在一个 X11 顶层窗内。HGS 的 X11/both `desktop-root` 仍拒绝启动，两协议共享画布属于 P6。
- X11 默认监听本地 abstract AF_UNIX，并为会话生成 Xauthority。跨应用沙箱的监听可达性、权限和认证需要独立设计。
- Wayland data-device 当前提供 GTK 初始化 seat 所需的最小实现。跨协议剪贴板、完整 data transfer 和 DnD 还没有实现。P4 的 GTK 关闭通过客户端 CSD 验证，X11 的关闭通过 OHOS 标题栏和 WM_DELETE 验证。两协议同屏用例验证了物理键鼠切换，系统 IME 的中文回归在 P3 WineHua X11 用例完成。
- Wayland Vulkan 的稳定性仍沿用 [P1 对照记录](../hgs-p1/README.md#vulkan-对照) 的开放项。此次 X11 外部帧的结果不能替代 Wayland Vulkan 多轮对照。
- WineHua 的测试路径仍依赖 X11 probe 开关和应用侧适配。旧 Wayland 窗口 ID、默认 host 的兼容入口、BetterSH 的旧窗口桥仍存在，留给 P5 按调用方逐项迁移。

## 5. P5 建议执行顺序

1. 从表中的已发布 HGS 和 WineHua 基点开始，确认 BetterSH 现有分支及 gitlink。用新 HGS 先构建 BetterSH 的纯 Wayland 包，核对大写 X11 资源路径，然后复跑 P1 的 GTK 窗口、键鼠、几何和关闭回归。
2. BetterSH 改用 HGS 会话返回的真实 endpoint/env 启动客户端，保留自己的进程与沙箱策略。等默认 host 的 Wayland 回归通过，再迁移旧 WaymonyService 和 ClientWindow 的调用方。
3. WineHua 将 X11 probe 配置逐步收口成启动客户端的协议偏好。保留 Wine 侧 GraphicsBroker、进程 broker 和虚拟桌面就绪策略。清理旧桥前，分别运行 WineHua 的 Wayland 与 X11 回归，确保旧 NAPI、DesktopRoot 和进程启停调用仍有替代路径。
4. 把独立 minimal-host 的通用测试与资源说明迁入 HGS，锁定可重建的 GTK 和 Xlib 探针。退出条件是 HGS 单独构建可复现、两宿主都只消费公共接口与自有 adapter，`wayland`、`x11`、`both` 三种服务配置都有实际端点及客户端回归。
5. 上游冻结树用于逐文件核对，原始冲突分类见 [P0 基线账本](../hgs-p0/README.md)。处理旧 compositor 的 modify/delete 冲突时，把行为变更迁到 HGS 对应后端，避免重新引入 entry 内的第二份显示实现。

# P3 WineHua 接回 HGS

本批把 Wine 进程的显示配置改为 HGS 会话端点。WineHua 启动 HGS 后读取 `clientEnvironment`。进程 broker 将这份环境追加到每次 NCP 启动请求中，覆盖 wineboot、wineserver、程序直启和 Wine 内部子进程自启的显示配置。显示变量以空值表达删除，子进程在应用环境时调用 `unsetenv`。Wayland 使用 HGS 返回的 XDG_RUNTIME_DIR 和 socket 名，X11 使用 HGS 返回的 DISPLAY 和 XAUTHORITY。

默认会话走 Wayland。开发验证通过 Want 参数 `winehua.hgsX11Probe=1` 显式启动 X11，需要 HGS 编译开启 `HGS_BUILD_X11`，HAP 包含 `hgs-x11-res.zip`、ARM64 X11 运行库和支持 winex11 的 Wine guest。X11 运行独立的逻辑输出，WineHua 为可见的顶层窗口创建 OHOS 子窗口。

测试使用单独的 HAP 构建目录和应用内隔离 prefix。X11 guest 基于 P0 已构建运行时，按 P0 记录移除 Mono MSI 和 .cpl 条目。WineHua 和 HGS 源码分别基于 `98fd63f98` 和 `85b8dd1`。打包 X11 ARM64 依赖时，除 HGS 服务的 ELF NEEDED 闭包外，还需包含 Box64 动态加载的 `libXext.so.6` 和 `libX11-xcb.so.1`。HGS 打包脚本的 `--dlopen-library` 可显式补入这些 SONAME。

证据位于 `/workspace/WineHua-root/WineHua/build/hgs-p3/`。X11 包的 `probe-x11-final.log` 显示 HGS 监听 `:0`、Wine 就绪、记事本和 GDI 探针均在 HGS 窗口表注册。探针的 Win32 `GetPixel` 读回值与 GDI 填色一致，见 `probe-x11-gdi-result.txt`。这一验证覆盖 headless 窗口和 GDI 读回。WineHua `make test` 通过，包括显示环境路由、清除对侧变量以及拒绝混合路线和 broker 分隔符。

Wayland 对照包使用原 P1 Wine guest 和新的 broker，在独立的干净 prefix 上完成 wineboot。`wayland-control-session.log` 记录 HGS 发布 `wine-wayland` 和 Wine 就绪，`wayland-control-gdi-result.txt` 记录 `GDI PASS expected=aa5218 actual=aa5218`。使用 P0 Wine guest 的双协议测试包也能在 Wayland 模式启动引擎，但该次运行未取得探针结果，原因待查。设备随后覆盖安装并成功启动测试前的 P1 签名包，见 `restore-p1-install.log` 和 `restore-p1-start.log`。

## X11 顶层窗口呈现

WineHua 根据 HGS 的窗口事件创建和销毁 OHOS 子窗口，并将会话 epoch 和 WindowId 传给 HAR 的 `HgsWindowSurface`。组件将 XComponent Surface 绑定到 HGS。绑定命令在 X11 事件线程执行，并校验窗口代次。HGS 读取 Xwayland 已提交的 CPU 缓冲，经 pixman 转为 RGBA，写入 OHOS Surface 队列。WindowId 失效时释放 Surface，迟到的解绑只作用于同一个 Surface ID。Wayland 继续使用原窗口宿主。

签名测试包在真机同时显示了记事本和 GDI 探针。探针的窗口先绘制 RGB(24,82,170)，随后绘制 RGB(32,178,94)，退出后露出原来的记事本内容。屏幕 JPEG 采样分别为 (25,82,171)、(32,178,95) 和白色。采样与截图见 `surface-screen-pixels.txt`、`surface-blue.jpeg`、`surface-green.jpeg`、`surface-closed.jpeg`。HGS 主机测试覆盖错误 epoch、窗口销毁和 Wayland 对该绑定接口的拒绝。

禁用 X11、沿用 P1 Wine guest 的对照包也通过了真机 GDI 回归，见 `surface-wayland-device.log` 和 `surface-wayland-gdi-result.txt`。回归后已覆盖安装并启动 P1 签名包，见 `surface-restore-p1-install.log` 和 `surface-restore-p1-start.log`。

## X11 子窗口输入

WineHua 的 X11 子窗口启用了 `HgsWindowSurface.interactive`。组件复用 HGS 键码和鼠标键映射，把 OHOS 键盘、鼠标、滚轮和单指触摸送入会话的输入路由。Xwayland 在事件线程按当前 surface 尺寸转换归一化坐标。组件失焦时归还按键和按钮，窗口销毁时输入路由清除其所有权。

真机测试使用 `uitest` 和 `uinput` 注入 OHOS 事件。Win32 探针收到触屏点击 (220,150)、字符 `a`、鼠标拖动至 (300,210)、左右键以及正反两个方向的滚轮消息。消息与断言见 `input-win32-messages.txt` 和 `input-verification.txt`。主机测试覆盖归一化坐标范围，以及窗口销毁后按键可在其他窗口重新按下。

禁用 X11 的 Wayland 对照包通过 Win32 建窗验证，见 `input-wayland-device.log` 和 `input-wayland-result.txt`。随后已恢复 P1 签名包。

## XIM 中文输入

HGS 在启用 `HGS_BUILD_XIM` 并为会话设置 `imeServerName` 时启动独立的 XIM 子进程。子进程通过认证的 X11 端点注册输入法，HGS 随端点发布 `XMODIFIERS`。WineHua 为 Wine 提供其 guest Xlib locale 目录。HGS 以当前会话、窗口代次和 XIM 焦点校验文本提交，WineHua 在 `textInputActive` 变化时切换系统输入法目标。

最小宿主真机验证覆盖 Xlib 握手、两个 X11 窗口的焦点切换、拒绝失焦和过期 ID 的提交，以及 `both` 重启后的重新连接和中文提交。WineHua 真机通过系统拼音键盘选词，Win32 编辑控件记录两次 `WM_IME_COMPOSITION` 的 `GCS_RESULTSTR`，最终内容逐字符匹配。证据见 `xim-verify/minimal-device-report.log`、`xim-verify/wine-e2e-result.txt` 和 `xim-verify/wine-e2e-editor.jpeg`。

XIM 当前提交已确认文本，预编辑和候选由系统输入法管理。

## X11 外部 GPU 帧

WineHua 将 GraphicsBroker 注册成 HGS 的可选帧提供者。HGS 根据 XID、客户端 PID 和窗口代次选择帧源，使用 OH_NativeImage 和 EGL 在绑定的 OHOS Surface 上呈现。帧源尚未就绪、失败或解绑时回到 pixman CPU 路径。

同设备签名包完成 WGL 四象限方向校验、Vulkan 840 帧呈现以及 GDI 回退。证据见 `gpu-verify/flip-trace.log`、`gpu-verify/wgl-flip-screen.jpeg`、`gpu-verify/vulkan-fixed-final.json` 和 `gpu-verify/gdi-result.txt`。Vulkan 探针使用单色图案，覆盖上屏与帧计数。

## X11 虚拟桌面

虚拟桌面沿 X11 顶层窗口路径呈现。WineHua 从屏幕尺寸与有效缩放计算 HGS 逻辑输出，再把端点的尺寸交给 Wine explorer。Wine loader 可通过 broker 另起实际的 explorer.exe。Broker 从 Unix socket 的对端凭据记录请求者 PID，WineHua 用这份关系校验 X11 窗口的所属进程，并等到其 OHOS Surface 首帧后发出桌面就绪事件。

在 2880×1920、缩放为 2 的设备上，桌面按 1440×960 上屏。早期包在 launcher 和实际 explorer PID 不同时一直等待，见 `desktop-verify-retry-20261108/device-diagnostic-mainpid-53991.log`。修复后，首帧与 `evt:desktop-ready` 同刻出现，即使 launcher 和实际窗口 PID 不同。

冷启动携带 Notepad 请求时，引擎启动一次，14:33:48.285 发出首帧就绪，14:33:48.510 受理 Notepad 启动。截图显示 Notepad 位于 Wine 桌面内。证据见 `desktop-verify-pidmatch-20261108/device-coldstart-notepad-full.log` 和 `desktop-verify-pidmatch-20261108/p3-notepad-coldstart.jpeg`。

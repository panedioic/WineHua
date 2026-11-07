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

本批使用每顶层窗口 CPU 拷贝呈现。键鼠的 OHOS 窗口回接、XIM、弹出层、窗口管理策略和外部 GPU 帧属于后续工作。

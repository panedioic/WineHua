# P5 双宿主接入

## BetterSH

BetterSH 的 EntryAbility 使用 `HgsWindowHostService.startService` 启动 Wayland。服务返回实际的运行目录和 socket 名后，BetterSH 将端点发布到自身的终端进程环境，IEC 将其随启动请求传给客户端。终端页面和调试终端都在环境发布后启动。HGS 使用异步服务入口，桌面窗口的关闭与服务监听独立。

手机和平板产品各自注册 `HgsWindowPage`，用共享 LocalStorage 把窗口 ID 传给对应的 multiton Ability 页面。已移除旧 WaymonyService、ClientWindow 及其图形 NAPI 声明。BetterSH 的 `bshutil set win-scale` 经现有 UI 事件调用 HGS 的 `setWaylandWindowScale`，影响随后创建的 Wayland 窗口。

XKB 资源与 HGS tar 使用同一目录 `usr/share/X11/xkb`，启动文件中的旧 Wayland 常量已去除。调试签名验证使用 BetterSH 的 release 构建流程、debug/JIT Profile 和保留应用数据的覆盖安装。

## WineHua

Wine 设置页的显示协议偏好在重启引擎时生效。选择 X11 需要构建中包含 X11 后端，部署包包含键盘资源与支持 winex11 的 Wine guest。自动化可通过 Want 指定 `winehua.displayProtocol=wayland|x11`。既有 `winehua.hgsX11Probe=1` 仍映射到 X11，当新旧参数都存在时采用新的协议参数。Want 覆盖仅作用于本次应用运行，界面选择持久写入 `wine_settings`。

Wine 仍通过 HGS 的客户端环境为 broker 下发协议端点，WineHua 保有自己的窗口策略、虚拟桌面和 GraphicsBroker 适配。主动停止时，ArkTS 分别等待 HGS 服务停止和 Wine 进程退出，然后才回到 idle。原生 `stopAll()` 的无参调用仍保留同步停止图形服务的兼容语义。

## 独立宿主

HGS 的 `tests/integration/gtk` 和 `tests/integration/x11` 包含独立的 Wayland GTK、Xlib 探针、NCP 入口及测试宿主。使用同一套包，通过 Want 的 `protocols=wayland|x11|both` 切换配置。HGS 仓库的 `tests/integration/README.md` 记录构建与验证输入。

## 验证记录

- HGS 主机测试通过，GTK NCP 与 launcher 通过 OHOS ARM64 交叉编译和链接。包含三个启动模式的独立 HAP 已构建并通过签名验证。
- 独立 HAP 在同一平板上跑过三种启动模式。`wayland` 日志记录了就绪端点和 GTK 建窗；`x11` 的 Xlib 探针记录了拒绝无认证连接、认证连接成功及绘制成功；`both` 同时发布两个端点，GTK 和 Xlib 都建窗，X11 的 `framePresented` 为 true。Xlib 两轮最终均为 `FAIL`：没有采集到探针要求的成对鼠标事件及 A 键输入，因此不能算作输入验收。证据在 `/workspace/WineHua-root/WineHua/build/hgs-p5/device-matrix/`。
- WineHua 的 `make test` 通过。X11 包使用新 Want 参数在平板启动并发出 `evt:desktop-ready`，Wayland 对照包也完成桌面启动。随后从设置页选 X11、结束应用进程，再省略协议覆盖参数启动；`p5-wine-final.log` 记录新进程使用 `protocol=x11 display=:0`，确认偏好跨进程保存。应用内停止再重启仍待独立回归。日志和截图位于 `/workspace/WineHua-root/WineHua/build/hgs-p5/wine-verify/`。
- BetterSH 首轮对照中，旧版 GTK 未找到设备上的 XKB 数据后退出；迁移版 GTK 显示 Wayland 变量未设置。后续设备日志 `bettersh-p5-device-hilog.txt` 定位到测试包里的旧 `libentry.so` 缺少 `setWaylandClientEnvironment`。清理隔离构建的 HAR、HAP 中间产物后重新执行 release 构建，确认新签名 HAP 内有该导出和 GTK 探针。旧包截图保留为诊断记录。产物及日志在 `/workspace/WineHua-root/build/`。
- 清理旧产物后，BetterSH 与旧版出现相同的 GTK XKB 崩溃。新进程日志 `bettersh-p5-fresh-device-hilog.txt` 显示 IEC 解包 XKB 和字体时因 `libarchive.so.13` 中未定义的 `__wrap_posix_spawnp` 而失败。IEC 的独立 libarchive 只链接文件系统 shim，构建脚本去掉不适用的 spawn 包装，并启用 `--no-undefined`。重新构建的 `bettersh-p5-archivefix.hap` 已检查两个 libarchive 文件都不再含该未定义符号，且包含新的端点发布导出。
- 修复包在平板 BetterSH 的正常终端内执行 `gtksmoke` 后成功创建和绘制 Wayland 窗口，点按计数从 0 到 1，最大化及恢复有效，关闭后从同一终端再次启动可绘制新窗口。截图位于 `/workspace/WineHua-root/build/`，分别为 `bsh-p5-archivefix.jpeg`、`bsh-p5-input.jpeg`、`bsh-p5-max.jpeg`、`bsh-p5-closed.jpeg`、`bsh-p5-listener-reopen.jpeg`。未取得含实际输入文字的 `gtksmoke: entry=` 日志。测试包专用启动器只放在隔离目录，未进入 BetterSH 产品源码。
- 平板测试期间通过 HDC 执行 `power-shell wakeup` 和 `power-shell timeout -o 86400000`。用 `hidumper -s PowerManagerService -a "-a"` 核对 `Current State` 与 `OverrideTimeout`，测试结束用 `power-shell timeout -r` 恢复原有 600000 ms。

## 接续验证

1. BetterSH 先用 `hilog -x` 确认 `HGS Wayland ready` 以及实际目录和 socket，再用同一终端打印 `XDG_RUNTIME_DIR`、`WAYLAND_DISPLAY`、`XKB_CONFIG_ROOT`。若 ready 日志不存在，先查服务启动或 NAPI 发布失败；若终端变量正确而 GTK 仍报未设置，再对照 IEC 客户端请求与 NCP 实际环境。GTK 能连接后，再验证输入、缩放、关闭和下一客户端重连。
2. 独立 HAP 用 Want 参数分别启动 `wayland`、`x11`、`both`，每次在 force-stop 后重新启动。在应用私有目录中查看本轮 `hgs-matrix.log` 的 endpoint 和窗口事件，以及各自的客户端日志。HDC 的普通 shell 无权直接读应用私有文件；调试包用 `hdc file recv -b app.hackeris.winehua` 导出。端点就绪、窗口绘制、用户输入分别记结果。
3. WineHua 用含 X11 后端的包验证应用内停止：等待 Wine 进程和 HGS 清理后再启动引擎，确认应用不退出也可重新建立会话。
4. 真机回归使用覆盖安装保留数据。WineHua 恢复包为 `WineHua/build/hgs-p1/2026-11-06/winehua-p1-final-signed.hap`，BetterSH 恢复包为 `build/bettersh-p5-restore.hap`（均相对于 `/workspace/WineHua-root`）。P5 依赖 HGS `main` 的 `aaf76fa` 和 IEC `main` 的 `2b664f4`，后续发布同样先更新依赖，再提交宿主的子模块指针。

如果默认 HDC 连接在 `tconn` 成功后立即掉线，在独立终端以前台方式启动 SDK 的 `hdc -s 18710 -m`，后续 `tconn`、`shell`、`file recv` 和 `install` 均加 `-s 18710`。设备调试结束后清除临时屏幕超时覆盖。

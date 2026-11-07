# HGS 双协议迁移 P0 基线账本

日期：2026-11-06。状态：**源码冻结、主机测试、HGS ARM64 新编译和 Wayland 未签名 HAP 已完成；签名、X11 构建及真机图形基线待补，P0 尚未满足全部退出条件。**

本阶段不修改图形栈实现。依据 [迁移规划](../hgs-dual-protocol-service-plan.md) 的 P0，建立后续变更可对照的来源、依赖、冲突和测试记录。

## 冻结版本与工作树

| 对象 | 版本 / 位置 |
|---|---|
| WineHua 分支基线 | `3355dab96b968cd7e6d3da1e01e1a9c7c0b831fc` |
| HGS 实际基线 | `bad402da1a8bdb56c87c2010a2727c09fc58251b` |
| 上游 X11 基线 | `a001e6d0ca277d5a5fb2b4bd6a030ac52e5e132e` |
| merge base | `3eecbd732d79bf6d306fdb48eee734771eb58147` |
| BetterSH 基线 | `7392c3dba391151b69810d80d03b805af05ab879`，实际 HGS 同为 bad402d |
| 集成工作树 | `/workspace/WineHua-root/hgs-integration` |
| 集成 HGS 工作树 | `/workspace/WineHua-root/hgs-integration/hgs` |
| 两仓库同名功能分支 | `feature/hgs-dual-protocol` |
| 上游只读对照工作树 | `/workspace/WineHua-root/hgs-upstream-baseline`，detached HEAD |

原工作区保持在 `feature/hgs-har-scaffold`。集成树的外层 gitlink 在 HEAD 中仍是 bad4d5f，HGS 工作树为 bad402d，因此外层 `M hgs` 是已记录的基线差异，不是迁移实现。尚未提交/推送子模块指针。

集成工作树内的 HGS 是通过 `git worktree` 创建的共享对象库工作树；P0 阶段不要在这里执行 `git submodule update hgs` 覆盖它。其他第三方子模块未批量初始化。上游测试只补齐了其锁定 Wine 提交中的两个验证输入文件，不代表完整 Wine checkout 已准备好。

`baseline-lock.json` 固定完整 SHA、两份 clone 的远程跟踪状态、所有 gitlink、初始工作区状态及公共头/.d.ts 哈希。它是 P0 证据锁，尚未接入 HGS 构建系统。

WineHua 的 HGS clone 本地 `origin/main` 是 bad4d5f，领先计数为 **11**；BetterSH 的 HGS clone 本地 `origin/main` 是 b316deb，领先计数为 **7**。这是两份 clone 的跟踪引用不同；本次未联网刷新或核实远程发布情况。不能将任一领先计数直接解释为实际未推送数量。

## 保存已有修改

备份位置：`/workspace/WineHua-root/WineHua/build/hgs-p0/2026-11-06/`。

- `snapshot/<repo>/index.patch`：暂存区二进制补丁。
- `snapshot/<repo>/worktree.patch`：未暂存二进制补丁。
- `snapshot/<repo>/head.patch`：相对 HEAD 的完整二进制补丁。
- `snapshot/<repo>/untracked.tar.gz`：Git 未忽略的未跟踪文件，包含原交接文档和迁移规划。
- `hgs-baseline.bundle`：HGS bad402d 的完整提交历史，已通过 `git bundle verify`。
- `SHA256SUMS`：本阶段原始证据的校验清单。

覆盖 WineHua、HGS、glib、gstreamer、pcre2、dxvk-modern、BetterSH、BetterSH 内 HGS。备份保留了 BetterSH 已有 EntryAbility 修改。未 stash、reset 或改写原分支；也未备份被 Git 忽略的整套 build/SDK 缓存，避免把可再生产物当成源码状态。

恢复时先核对原始 HEAD，在单独工作树应用补丁并解包未跟踪文件；不要直接对正在工作的目录覆盖。bundle 可用于从本地重新取回 HGS 基线提交。

## 上游变更与迁移清单

本次 `git merge-tree --write-tree --name-only HEAD upstream/master` 返回 1，表示存在预期合并冲突。它没有执行真实 merge，也没有修改任何工作树或 index。

- 上游相对 merge base：**313 个提交**，详见 `upstream-commits.tsv`。
- 冲突：**42 个**，其中 **28 个 modify/delete、14 个 content**，详见 `merge-conflicts.tsv`。
- X11 display 栈：**22 个文件**，详见 `migration-inventory.tsv`，逐文件记录目标域与原始内容 SHA256。
- 原始合并输出、上游全部文件变更清单保存在 build 证据目录。

modify/delete 文件继续保持 entry 删除状态，将上游 delta 移植进 HGS 对应文件。X11 新栈迁入独立 backend；窗口/输入调用点改为按窗口所属 backend 分发。具体逐文件目标在 TSV 中，不提前实施。

## 依赖基线

`dependencies.json` 记录上游全部子模块 gitlink、7 个关键构建脚本哈希、8 个 OHOS 补丁哈希、wlroots 补丁应用次序、15 个源码归档 URL/hash，以及另外 2 个通过脚本变量配置的 host 归档。

已锁定的主要版本：wlroots 0.20.2、Xwayland 24.1.13、Wayland 1.26.0、host pixman 0.46.4、host libdrm 2.4.134。xkbcommon 等按 upstream 精确 gitlink 固定。

当前 HGS/Wayland 分支仍使用原依赖，尚未升级。后续 P1/P2 应区分“旧基线依赖”和“目标后端依赖”，处理 host arm64 / guest x86_64、相同 SONAME 的唯一打包来源。此次没有运行会重置第三方源码并应用补丁的依赖构建脚本。

## 本次测试

| 项目 | 结果 | 范围 |
|---|---|---|
| HGS/Wayland 集成树 `make test` | **PASS，exit 0** | 16 个测试程序；包括 HGS endpoint/event/window manager/native keymap、几何、输入和 controller |
| 上游树 `make test` | **PASS，exit 0** | 12 个测试程序，以及 WHGP v2 host/Wine 一致性验证 |
| merge-tree | **预期冲突，exit 1** | 42 个冲突，与交接数量一致 |
| HGS bundle verify | **PASS** | bad402d 完整历史可读取 |
| HGS ARM64 native 新构建 | **PASS** | 干净目录编译 62 步，生成 libhgs.so 和 libsmoke_napi.so |
| WineHua Wayland 未签名 HAP | **PASS** | Hvigor 43 个任务全部执行；entry/HGS 原生层和 ArkTS 均重新编译 |
| 上游 X11 HAP | **NOT_BUILT** | 尚缺独立 wlroots/xserver 源码 checkout 与完整 host 依赖区 |
| 签名工具 doctor / selftest | **PASS** | Java、keytool、签名工具可用；本地回调和临时密钥生成通过 |
| 真机图形 smoke | **NOT_RUN** | 在线设备未安装 WineHua，未形成与源码对应的设备基线 |

详细命令、测试程序列表、日志路径和哈希在 `baseline-tests.json`。

上游首次测试因新工作树未初始化 Wine 子模块而缺少验证输入。补齐 `025656dfd3920ea11aaab9e8ac6d905ec35963fe` 的 `dlls/winebus.sys/winehua_gamepad_protocol.h` 和 `bus_ohos.c` 后，完整重跑通过；没有修改测试或被测源码。

主机测试复现：

```bash
make -C /workspace/WineHua-root/hgs-integration test
make -C /workspace/WineHua-root/hgs-upstream-baseline test
```

上游测试树重建时，可以初始化锁定 Wine 子模块；若只复现当前纯主机验证，也可从原 Wine clone 用 `git show <锁定提交>:<上述文件路径>` 导出这两个文件。导出目标必须在隔离工作树内，不能覆盖原 Wine 源码。

## 真机条件与历史问题账本

HDC 在沙箱内连接 server 失败；使用沙箱外只读检查发现在线设备 `192.168.3.9:46071`。包查询与成功的应用列表核查表明，该设备未安装 `app.hackeris.winehua`。这里只记录任务相关结论，不保存设备完整应用列表。

本次已在隔离集成树生成新的 unsigned HAP：`/workspace/WineHua-root/hgs-integration/entry/build/default/outputs/default/entry-default-unsigned.hap`，398,098,027 字节，SHA256 `398cb72be3a16103b8a1e1d1a1f35d8b6aaefe6e49698f86e66f50de91784428`。应用原生层和 ArkTS 为本次编译；Wine 引擎 zip 与第三方运行库复用原工作区产物，**没有重编 guest 引擎，也未验证其完整源码来源**。38 个复用文件的哈希与 HAP 内主要 ARM64 原生库的哈希记录于 `build-artifacts.json`，不能把此包描述为全链从源码重新构建。

原 HGS CMake cache 指向旧路径，本次独立 native 构建使用全新证据目录，不复用旧对象文件。`build-baseline.mk` 保存实际构建入口，可与根 Makefile 一起使用：

```bash
cd /workspace/WineHua-root/hgs-integration
make -f Makefile -f /workspace/WineHua-root/WineHua/docs/architecture/hgs-p0/build-baseline.mk ROOT="$PWD" p0-hgs-native
make -f Makefile -f /workspace/WineHua-root/WineHua/docs/architecture/hgs-p0/build-baseline.mk ROOT="$PWD" p0-hap-unsigned
```

未签名 HAP 的准备步骤包括：复制并记录既有 ARM64 runtime libs/rawfile；复用 oh_modules 的依赖包和相对本地链接；仅在隔离树去掉签名配置并设置 ARM64 ABI。原工作区签名配置未修改。Hvigor 需要写用户缓存，已通过沙箱外构建完成。

已阅读 `/workspace/signer/hapsign_auto.py` 与 `devsign_material.py`。前者负责浏览器登录、云端调试证书/设备/Profile 申请和本地 HAP 签名；后者只生成 Hvigor 密码加密材料，不能替代有效的签名证书/Profile。工具链检查与自检均已通过。用户最新要求为“稍后生成签名文件”，因此尚未登录账号、申请真实云端材料或安装应用。后续优先使用 hapsign_auto，避免旧 sign.py 把含口令的签名命令打印到日志；私钥和令牌不得写入本证据账本或版本库。

后续补全设备门禁需要：准备两套与锁定提交对应的可安装 HAP，记录包和 native 库哈希，分别执行 Wayland、X11 的单窗口/多窗口/输入/IME/GPU/重复启停验证。所有套件都要显式固定 route、backend 与 desktopMode；不能继承设备上的持久化设置。按设备、来源提交和每个 case 记录结果。

以下是上游 `a001e6d0c:docs/engineering/display-route-known-issues.md` 的历史记录，**本次没有重新验证，也不直接豁免后续失败**：

| 历史事项 | 后续处理 |
|---|---|
| X11 GL 启动期 `rel_unsynced_presented=3`，记录为尚未查清 | 记录每次运行计数和帧阶段；不能把它无条件改判 PASS |
| 最后一键间歇未进入控件、pending key 单槽 | 单独记录输入场景与丢键情况 |
| XIM static spawned 提前置位、会话重启存活行为未定 | 覆盖失败重试和 start/stop/start |
| dxvk-legacy 初始化失败与设备能力相关 | 按实际设备记录，不跨设备照搬结论 |
| 曾标记为 opengl-x86 D49 的部分失败，后续被重新判定为测试归属问题 | 不能沿用早期“3/4 即合格”的口径；按最新判定与原始数据重新评估 |

## 下一步与 P0 退出门

- [x] 冻结 WineHua、HGS、上游三个版本，记录 BetterSH 对照。
- [x] 保存已有本地修改与 HGS 离线提交历史。
- [x] 创建主仓库与 HGS 同名功能分支、隔离集成树及上游对照树。
- [x] 生成依赖、补丁、上游提交、冲突和迁移清单。
- [x] 两套主机测试通过并保留日志。
- [x] HGS ARM64 新编译、应用原生层/ArkTS 新编译和未签名 HAP 打包，记录复用 runtime 输入哈希。
- [x] 阅读 signer 流程并验证工具链及本地回调/临时密钥生成。
- [ ] 为锁定版本完成新的 native/HAP 构建，保留可安装包及来源哈希。
- [ ] 完成同设备上的 Wayland / X11 图形回归，并填写实际失败基线。

P1 的公共契约开发已有隔离工作树和主机基线可用；设备相关行为的等价性验收仍以上述未完成项为前置条件。

# CI 构建环境镜像

本目录存放 GitHub Actions 使用的构建环境镜像定义。
镜像**不由 CI 自动构建**，需要维护者在本地一次性构建并推送到 GHCR。

## 目录内容

- `Dockerfile.buildenv` — 构建环境镜像定义（Ubuntu 24.04 + 依赖 + HarmonyOS SDK）
- `README.md` — 本文档

## 一次性准备流程

### 1. 准备 HarmonyOS SDK 目录

把 HarmonyOS 命令行工具 + SDK 复制到项目根下的 `./harmony-sdk/`，
结构与生产机上的 `/apps/harmony/` 一致：

```
harmony-sdk/
├── bin/hvigorw
├── tool/node/bin/node
└── sdk/default/openharmony/
    └── native/llvm/bin/clang
    └── ...
```

> `harmony-sdk/` 已在 `.gitignore` 中，不会被提交。
> 请勿把 SDK 内容以任何形式提交到公开仓库，遵守华为 SDK 授权协议。

### 2. 登录 GHCR

需要一个有 `write:packages` 权限的 GitHub Personal Access Token（Classic 或 Fine-grained 均可）：

```bash
echo "$GITHUB_PAT" | docker login ghcr.io -u <your-github-user> --password-stdin
```

### 3. 构建镜像

```bash
cd <项目根目录>
TAG=$(date +%Y%m%d)

docker build \
    -f ci/Dockerfile.buildenv \
    --build-arg SDK_SRC=./harmony-sdk \
    -t ghcr.io/winehua/winehua-buildenv:${TAG} \
    -t ghcr.io/winehua/winehua-buildenv:latest \
    .
```

镜像大约 6–8 GB，构建时间视机器和网络 20–40 分钟。

### 4. 推送到 GHCR

```bash
docker push ghcr.io/winehua/winehua-buildenv:${TAG}
docker push ghcr.io/winehua/winehua-buildenv:latest
```

### 5. 配置镜像可见性和权限

在 GitHub 上：

1. 打开 `https://github.com/orgs/winehua/packages/container/winehua-buildenv/settings`
   （个人账号是 `https://github.com/users/<user>/packages/container/winehua-buildenv/settings`）
2. 把 **Visibility** 设为 **Private**
3. 在 **Manage Actions access** 里把 `WineHua` 仓库加进去
   （这样 workflow 里的 `GITHUB_TOKEN` 才能拉这个镜像）

### 6. 更新 workflow 中的镜像 tag

编辑 `.github/workflows/build.yml`，把 `image:` 一行的 tag 改成本次推送的 `${TAG}`。

## 更新镜像

有 SDK 升级、依赖变更或需要修 Dockerfile 时，重复第 3–6 步即可。
推荐用日期 tag（如 `20260801`），并同步更新 workflow。

## 在个人 fork 上验证

fork 出来做 PR 的贡献者可以先推到个人 GHCR：

```bash
docker build -f ci/Dockerfile.buildenv \
    --build-arg SDK_SRC=./harmony-sdk \
    -t ghcr.io/<your-user>/winehua-buildenv:test .
docker push ghcr.io/<your-user>/winehua-buildenv:test
```

然后临时修改 workflow 中 `image:` 指向个人镜像验证，
PR 前再改回 `ghcr.io/winehua/...`。
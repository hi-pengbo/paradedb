# ParadeDB + VectorChord

基于官方 [ParadeDB](https://github.com/paradedb/paradedb) 镜像，额外安装 [VectorChord](https://github.com/supervc-stack/VectorChord)（`vchord`），并写入 `shared_preload_libraries`。一份 Postgres 镜像同时覆盖全文检索（`pg_search`）和向量检索（`vchord`）。

<!-- VERSIONS:START -->
- ParadeDB: `v0.25.7`
- VectorChord: `1.1.1`
- PostgreSQL: `18`
<!-- VERSIONS:END -->

# GitHub Actions

只使用 `main` 分支，不另开 PR / 功能分支。仓库包含三个 workflow。

## 1. 自动更新版本（`.github/workflows/update-versions.yml`）

每天 UTC 03:17 检查：

- [ParadeDB GitHub Releases](https://github.com/paradedb/paradedb/releases) 的 latest
- [VectorChord GitHub Releases](https://github.com/supervc-stack/VectorChord/releases) 的 latest

确认 Docker Hub 上已有 `paradedb/paradedb:<tag>-pg18`，以及对应 Postgres 版本的 VectorChord `.deb` 后，直接把 `Dockerfile` / README 提交到 `main`，并触发镜像发布。

也可在 Actions → **Update versions** → **Run workflow** 手动触发，并可填写指定版本。

## 2. 构建并发布到 GitHub Packages（`.github/workflows/publish.yml`）

| 事件 | 行为 |
| --- | --- |
| 推送到 `main`（`Dockerfile` 变更） | 构建 `linux/amd64` + `linux/arm64`，推送到 `ghcr.io/OWNER/REPO` |
| 推送 `v*` tag | 额外打上对应 git tag |
| `workflow_dispatch` | 手动发布 |

自动版本更新也是通过 `workflow_dispatch` 触发本 workflow（`GITHUB_TOKEN` 的直接 push 不会再触发其他 workflow）。

## 3. 清理旧镜像（`.github/workflows/cleanup-packages.yml`）

每周日 UTC 04:47（也可手动触发）删除 GHCR 上 **超过 2 个月** 的镜像，包括未打 tag 的残留层。`latest` 和 `pg*` 会保留。

## 仓库设置

推送使用 `GITHUB_TOKEN`，无需额外 secret。第一次发布后，到仓库的 **Packages** 里把该 Container package 设为 Public（若仓库是公开的、希望匿名拉取）。

**Settings → Actions → General → Workflow permissions** 选 **Read and write permissions**。

`main` **不要** 开启 “Require a pull request before merging”，否则 bot 无法直推。若已开 branch protection，把 `github-actions[bot]` 加进允许 push 的名单。


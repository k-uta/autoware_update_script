# autoware_update_script

<!-- License -->
<p align="center">
  <a href="https://github.com/k-uta/autoware_update_script/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/k-uta/autoware_update_script?style=flat&label=License" alt="License" />
  </a>
</p>

A single-command script that keeps an [Autoware][autoware]™ workspace in sync with the latest upstream, following the [official source installation documentation][src-install].

Designed to be run regularly — for example, every morning before starting work — so you can always develop against the latest codebase without manual steps.

This script is intended to be cloned into the home directory and run from there:

```
~/autoware_update_script/update_autoware.sh   # this script
~/autoware/                                   # Autoware workspace (default target)
```

> **Safety:** This script is **read-only** with respect to remotes. It will **never** `git push`, force-push, or modify any remote repository. All operations are local fetches, checkouts, and builds only.

## What it does

The script mirrors the [How to update a workspace][update-ws] workflow from the official documentation, adding safety rails (stash, dirty-tree detection) and a few convenience options.

| # | Step | Default command |
|:-:|------|-----------------|
| **1** | Update the Autoware root repository to the target branch | `git fetch && git merge --ff-only origin/<branch>` *(dirty tree auto-stashed)* |
| **2** | *(opt-in)* Refresh build tools / CUDA / cuDNN / TensorRT | `./setup-dev-env.sh -y` |
| **3** | Upgrade system & ROS packages | `sudo apt-get update && sudo apt-get upgrade -y` |
| **4** | Source the [ROS 2][ros2] environment (Humble / Jazzy auto-detected) | `source /opt/ros/$ROS_DISTRO/setup.bash` |
| **5** | Sync `src/` repositories | `vcs import src < repositories/autoware.repos` + `vcs pull src` |
| **6** | Resolve ROS dependencies | `rosdep update && rosdep install -y --from-paths src ...` |
| **7** | Build with [`colcon`][colcon] (ccache-aware, incremental by default) | `colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release` |

Step 2 runs only when `SETUP_DEV_ENV=1`. Every other step runs on every invocation.

### Two sync modes

| Mode | Trigger | Behavior |
|------|---------|----------|
| **Update** *(default)* | `FRESH_INSTALL=0` | `vcs import` + `vcs pull` — fast, reuses existing clones, incremental build |
| **Fresh** | `FRESH_INSTALL=1` | Deletes `src/` entirely, then `vcs import`. Forces a clean build. Also performs the **initial clone** of the Autoware root repository when `~/autoware` does not yet exist. |

> **When to use fresh mode?**
> The official documentation [notes][update-ws] that dependencies imported via `vcs import` may have been moved or removed, and vcs2l does not currently handle those cases. Use `FRESH_INSTALL=1` when a normal update fails, or after a major upstream restructuring.

### What is preserved vs. discarded

| Location | Update mode | Fresh mode |
|----------|:-----------:|:----------:|
| Autoware root repo — committed history | kept | kept |
| Autoware root repo — uncommitted changes | auto-stashed (`git stash list` to recover) | auto-stashed |
| `src/<repo>/` — committed changes | kept | **deleted** |
| `src/<repo>/` — uncommitted changes | prompt before `vcs pull` | **deleted** (prompt before) |
| `build/`, `install/`, `log/` | kept (incremental build) unless `CLEAN_BUILD=1` | **deleted** |

### Uncommitted change detection

Before any `src/` operation, the script scans every nested repository and lists those with uncommitted work. You are prompted to confirm before proceeding — this prevents accidental loss of yesterday's work-in-progress. Changes in the Autoware root repository are handled automatically by `git stash`.

## Prerequisites

- Ubuntu 22.04 with [ROS 2 Humble][humble] (or [Jazzy][jazzy]).
- [Git][git] with [SSH keys registered on GitHub][ssh-keys] (recommended).
- For **updates**: an existing Autoware workspace set up per the [source installation guide][src-install].
- For **initial installation**: no existing workspace needed — use `FRESH_INSTALL=1` (the script clones the repository automatically).
- Optional: [`ccache`][ccache] (`sudo apt install ccache`) — the script auto-detects and enables it.

## Quick start

Clone this repository into your home directory:

```bash
cd ~
git clone https://github.com/k-uta/autoware_update_script.git
```

**First-time installation** (no existing `~/autoware`):

```bash
SETUP_DEV_ENV=1 FRESH_INSTALL=1 bash ~/autoware_update_script/update_autoware.sh
```

**Daily update** (existing `~/autoware`):

```bash
bash ~/autoware_update_script/update_autoware.sh
```

After the script finishes, source the workspace:

```bash
source ~/autoware/install/setup.bash
```

## Configuration

Behavior is controlled entirely through environment variables — no flags, no config files.

| Variable | Default | Description |
|----------|---------|-------------|
| `AUTOWARE_DIR` | `~/autoware` | Path to the Autoware root directory |
| `AUTOWARE_BRANCH` | `main` | Branch or tag to track (e.g. `main`, `release/v1.0`) |
| `FRESH_INSTALL` | `0` | `1` = delete `src/` and re-import all repositories. Also triggers the initial clone when `AUTOWARE_DIR` is absent, and implies `CLEAN_BUILD=1`. |
| `SETUP_DEV_ENV` | `0` | `1` = run [`setup-dev-env.sh`][setup-dev-env] to refresh build tools, CUDA, cuDNN, TensorRT, etc. |
| `INCLUDE_NIGHTLY` | `0` | `1` = also import [nightly repositories][nightly-repos]. ⚠️ May be unstable. |
| `CLEAN_BUILD` | `0` | `1` = remove `build/`, `install/`, `log/` before building (full rebuild). |
| `BUILD_JOBS` | `nproc / 2` | Parallel workers for `colcon build`. Lower this on low-memory machines. |

### Examples

**Track a specific release:**

```bash
AUTOWARE_BRANCH=release/v1.0 bash ~/autoware_update_script/update_autoware.sh
```

**Fresh re-clone** — when a normal update fails or after a major upstream change:

```bash
FRESH_INSTALL=1 bash ~/autoware_update_script/update_autoware.sh
```

**Weekly deep update** — also refresh system-level dependencies (Ansible):

```bash
SETUP_DEV_ENV=1 bash ~/autoware_update_script/update_autoware.sh
```

**Force a clean rebuild** without re-cloning `src/`:

```bash
CLEAN_BUILD=1 bash ~/autoware_update_script/update_autoware.sh
```

**Include nightly (bleeding-edge) packages:**

```bash
INCLUDE_NIGHTLY=1 bash ~/autoware_update_script/update_autoware.sh
```

**Custom workspace location & limited parallelism** (e.g. on a laptop):

```bash
AUTOWARE_DIR=/mnt/data/autoware BUILD_JOBS=4 \
    bash ~/autoware_update_script/update_autoware.sh
```

## Suggested workflow

| Frequency | Command | What it covers |
|-----------|---------|----------------|
| Daily | `bash ~/autoware_update_script/update_autoware.sh` | Code + ROS package updates, incremental build |
| Weekly | `SETUP_DEV_ENV=1 bash ~/autoware_update_script/update_autoware.sh` | Also refreshes Ansible-managed dependencies |
| On build failure after upstream change | `FRESH_INSTALL=1 bash ~/autoware_update_script/update_autoware.sh` | Wipes `src/` + `build/` and re-imports |

## Important notes

> [!NOTE]
> **Builds are incremental by default.** `build/`, `install/`, and `log/` are preserved across runs. Pass `CLEAN_BUILD=1` (or `FRESH_INSTALL=1`) when you need a full rebuild — for example after a toolchain change or when you suspect stale artifacts.

> [!NOTE]
> **Root repository updates use `git merge --ff-only`.** If your local `main` has diverged from upstream (because of local commits or a rebase), the script aborts rather than rewriting history. Rebase manually, then re-run.

> [!NOTE]
> **Uncommitted changes in `src/`** trigger a confirmation prompt. On `FRESH_INSTALL=1` they will be deleted; in update mode they may conflict with `vcs pull`. **Uncommitted changes at the root** are auto-stashed (`git stash list` → `git stash pop` to recover).

> [!WARNING]
> Before installing NVIDIA libraries via `SETUP_DEV_ENV=1`, ensure you have reviewed and agreed to the licenses for [CUDA][cuda-eula], [cuDNN][cudnn-sla], and [TensorRT][tensorrt-sla].

## Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| `merge --ff-only` fails on root | Your root branch has diverged. Rebase/reset manually. |
| `vcs pull` fails or reports conflicts | Uncommitted changes or upstream rebase in a sub-repo. Retry with `FRESH_INSTALL=1`. |
| `rosdep install` cannot find a key | Outdated rosdep cache. Re-run — the script refreshes it every time. |
| Build fails after a big upstream change | Stale `build/install/` artifacts. Retry with `CLEAN_BUILD=1`, or `FRESH_INSTALL=1` for a full reset. |
| OOM during build | Lower `BUILD_JOBS`, e.g. `BUILD_JOBS=2`. |

For Autoware-specific build errors, consult the official [Troubleshooting][troubleshoot] page.

## Disclaimer

**Use this script at your own risk.**

- This is an **unofficial** community utility and is **not** affiliated with or endorsed by the [Autoware Foundation][aw-foundation].
- The author assumes no responsibility for any data loss, build failures, or damage to your development environment resulting from the use of this script.
- Always review the script contents before execution to ensure it suits your specific setup.

## Trademarks

Autoware™ is a registered trademark of the [Autoware Foundation][aw-foundation]. All other trademarks are the property of their respective owners. Use of these names in this repository is for identification purposes only and does not imply endorsement.

## Useful resources

- [Autoware Documentation][docs]
- [Source Installation Guide][src-install]
- [autowarefoundation/autoware][autoware] — meta-repository containing the `.repos` files
- [Troubleshooting][troubleshoot]
- [Autoware Q&A Discussions][qa]

## License

This project is licensed under the [Apache License 2.0](LICENSE).

<!-- Link references -->
[autoware]: https://github.com/autowarefoundation/autoware
[aw-foundation]: https://www.autoware.org/
[docs]: https://autowarefoundation.github.io/autoware-documentation/main/
[src-install]: https://autowarefoundation.github.io/autoware-documentation/main/installation/autoware/source-installation/
[update-ws]: https://autowarefoundation.github.io/autoware-documentation/main/installation/autoware/source-installation/#how-to-update-a-workspace
[troubleshoot]: https://autowarefoundation.github.io/autoware-documentation/main/community/support/troubleshooting/
[qa]: https://github.com/autowarefoundation/autoware/discussions/categories/q-a
[setup-dev-env]: https://github.com/autowarefoundation/autoware/blob/main/setup-dev-env.sh
[nightly-repos]: https://github.com/autowarefoundation/autoware/blob/main/repositories/autoware-nightly.repos
[ros2]: https://docs.ros.org/
[humble]: https://docs.ros.org/en/humble/
[jazzy]: https://docs.ros.org/en/jazzy/
[colcon]: https://colcon.readthedocs.io/
[ccache]: https://ccache.dev/
[git]: https://git-scm.com/
[ssh-keys]: https://github.com/settings/keys
[cuda-eula]: https://docs.nvidia.com/cuda/eula/index.html
[cudnn-sla]: https://docs.nvidia.com/deeplearning/cudnn/sla/index.html
[tensorrt-sla]: https://docs.nvidia.com/deeplearning/tensorrt/sla/index.html

# autoware_update_script

<!-- License -->
<p align="center">
  <a href="https://github.com/k-uta/autoware_update_script/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/k-uta/autoware_update_script?style=flat&label=License" alt="License" />
  </a>
</p>

A single-command script that keeps an [Autoware](https://github.com/autowarefoundation/autoware) workspace in sync with the latest upstream, based on the [official source installation documentation](https://autowarefoundation.github.io/autoware-documentation/main/installation/autoware/source-installation/).

Designed to be run regularly — for example, every morning before starting work — so you can always develop against the latest codebase without manual steps.

This script is intended to be cloned into the home directory and run from there:

```
~/autoware_update_script/update_autoware.sh   # this script
~/autoware/                                   # Autoware workspace (default target)
```

> **Safety:** This script is **read-only** with respect to remotes. It will **never** `git push`, force-push, or modify any remote repository. All operations are local fetches, checkouts, and builds only.

## What it does

The script automates the [How to update a workspace](https://autowarefoundation.github.io/autoware-documentation/main/installation/autoware/source-installation/#how-to-update-a-workspace) workflow described in the official documentation.

| Step | Description |
|------|-------------|
| **1** | Update the Autoware root repository to the target branch/tag (local changes are auto-stashed) |
| **2** | *(opt-in)* Run [`setup-dev-env.sh`](https://github.com/autowarefoundation/autoware/blob/main/setup-dev-env.sh) to update build tools, CUDA, cuDNN, TensorRT, etc. |
| **3** | `apt upgrade` to bring all system & ROS packages up to date |
| **4** | Source the [ROS 2](https://docs.ros.org/) environment (Humble / Jazzy auto-detected) |
| **5** | Sync `src/` repositories and resolve dependencies ([`rosdep`](https://docs.ros.org/en/humble/Tutorials/Intermediate/Rosdep.html) + `pip`) |
| **6** | Clean build with [`colcon`](https://colcon.readthedocs.io/) (Release, ccache-aware) |

### Two sync modes

| Mode | Trigger | Behavior |
|------|---------|----------|
| **Update** *(default)* | `FRESH_INSTALL=0` | `vcs import` + `vcs pull` — fast, keeps existing clones |
| **Fresh** | `FRESH_INSTALL=1` | Deletes `src/` entirely, then `vcs import` — clean re-clone. Also handles **initial installation** by cloning the Autoware repository if `~/autoware` does not yet exist. |

> **When to use fresh mode?**
> The official documentation [notes](https://autowarefoundation.github.io/autoware-documentation/main/installation/autoware/source-installation/#how-to-update-a-workspace) that dependencies imported via `vcs import` may have been moved or removed. Since vcs does not currently handle those cases, cleaning and re-importing all dependencies may be necessary. Use `FRESH_INSTALL=1` when a normal update fails or after a major upstream restructuring.

### Uncommitted change detection

Before making any changes, the script scans `src/` repositories and the root repository for uncommitted work. If any are found, a list of affected repositories is displayed and you are prompted to confirm before continuing. This prevents accidental loss of yesterday's work-in-progress.

## Prerequisites

- Ubuntu 22.04 with [ROS 2 Humble](https://docs.ros.org/en/humble/) (or [Jazzy](https://docs.ros.org/en/jazzy/)).
- [Git](https://git-scm.com/) with [SSH keys registered on GitHub](https://github.com/settings/keys) (recommended).
- For **updates**: an existing Autoware workspace set up per the [source installation guide](https://autowarefoundation.github.io/autoware-documentation/main/installation/autoware/source-installation/).
- For **initial installation**: no existing workspace needed — use `FRESH_INSTALL=1` (the script will clone the repository automatically).

## Quick start

Clone this repository into your home directory:

```bash
cd ~
git clone https://github.com/k-uta/autoware_update_script.git
```

**First-time installation** (no existing `~/autoware`):

```bash
FRESH_INSTALL=1 bash ~/autoware_update_script/update_autoware.sh
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

Behavior can be customized through environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `AUTOWARE_DIR` | `~/autoware` | Path to the Autoware root directory |
| `AUTOWARE_BRANCH` | `main` | Branch or tag to track (e.g. `main`, `release/v1.0`) |
| `FRESH_INSTALL` | `0` | Set to `1` to delete `src/` and re-clone all repositories. If `~/autoware` does not exist, the Autoware root repository is also cloned automatically. |
| `SETUP_DEV_ENV` | `0` | Set to `1` to run [`setup-dev-env.sh`](https://github.com/autowarefoundation/autoware/blob/main/setup-dev-env.sh) |
| `INCLUDE_NIGHTLY` | `0` | Set to `1` to import [nightly repositories](https://github.com/autowarefoundation/autoware/blob/main/repositories/autoware-nightly.repos) |
| `BUILD_JOBS` | `nproc / 2` | Number of parallel build jobs |

### Examples

**Daily update** — fast pull-based sync on `main`:

```bash
bash ~/autoware_update_script/update_autoware.sh
```

**First-time installation** — clone and build from scratch:

```bash
FRESH_INSTALL=1 bash ~/autoware_update_script/update_autoware.sh
```

**Track a specific release:**

```bash
AUTOWARE_BRANCH=release/v1.0 bash ~/autoware_update_script/update_autoware.sh
```

**Fresh re-clone** — when a normal update fails or after a major upstream change:

```bash
FRESH_INSTALL=1 bash ~/autoware_update_script/update_autoware.sh
```

**Weekly deep update** — also refresh system-level dependencies:

```bash
SETUP_DEV_ENV=1 bash ~/autoware_update_script/update_autoware.sh
```

**Include nightly (bleeding-edge) packages:**

```bash
INCLUDE_NIGHTLY=1 bash ~/autoware_update_script/update_autoware.sh
```

## Important notes

> [!WARNING]
> This script **deletes** `build/`, `install/`, and `log/` on every run.
> With `FRESH_INSTALL=1`, `src/` is also deleted.
> Depending on your hardware, a rebuild may take a significant amount of time.

> [!NOTE]
> Uncommitted changes in `src/` repositories are **detected and reported** before any cleanup.
> You will be prompted to confirm before they are lost.
> Uncommitted changes in the root repository are automatically stashed via `git stash`.

> [!NOTE]
> Before installing NVIDIA libraries, please ensure that you have reviewed and agreed to the licenses for [CUDA](https://docs.nvidia.com/cuda/eula/index.html), [cuDNN](https://docs.nvidia.com/deeplearning/cudnn/sla/index.html), and [TensorRT](https://docs.nvidia.com/deeplearning/tensorrt/sla/index.html).

## Disclaimer

**Use this script at your own risk.**

- This is an **unofficial** community utility and is **not** affiliated with or endorsed by the [Autoware Foundation](https://www.autoware.org/).
- The author assumes no responsibility for any data loss, build failures, or damage to your development environment resulting from the use of this script.
- Always review the script contents before execution to ensure it suits your specific setup.

## Useful resources

- [Autoware Documentation](https://autowarefoundation.github.io/autoware-documentation/main/)
- [Source Installation Guide](https://autowarefoundation.github.io/autoware-documentation/main/installation/autoware/source-installation/)
- [autowarefoundation/autoware](https://github.com/autowarefoundation/autoware) — Meta-repository containing `.repos` files to construct an Autoware workspace
- [Troubleshooting](https://autowarefoundation.github.io/autoware-documentation/main/community/support/troubleshooting/)
- [Autoware Q&A Discussions](https://github.com/autowarefoundation/autoware/discussions/categories/q-a)
- [Support Guidelines](https://autowarefoundation.github.io/autoware-documentation/main/community/support/support-guidelines/)

## License

This project is licensed under the [Apache License 2.0](LICENSE).

#!/bin/bash
###############################################################################
# Autoware Update Script
#
# Follows the official workflow:
#   https://autowarefoundation.github.io/autoware-documentation/main/installation/autoware/source-installation/
#
# Read-only with respect to remotes: never pushes, force-pushes, or otherwise
# modifies remote repositories. All operations are local fetches and builds.
#
# Usage:
#   bash ~/autoware_update_script/update_autoware.sh
#   FRESH_INSTALL=1 bash ~/autoware_update_script/update_autoware.sh   # first install or re-clone
#
# Environment variables:
#   AUTOWARE_DIR     Autoware root                     (default: ~/autoware)
#   AUTOWARE_BRANCH  Branch or tag to track            (default: main)
#   FRESH_INSTALL    1 = delete src/ and re-import     (default: 0)
#                    Also handles the initial clone when AUTOWARE_DIR is absent.
#   SETUP_DEV_ENV    1 = install dev env via Ansible   (default: 0)
#                    (install-ansible.sh + install_dev_env playbook;
#                     replaces the deprecated setup-dev-env.sh — see
#                     https://github.com/orgs/autowarefoundation/discussions/7065)
#   SKIP_NVIDIA      1 = pass --skip-tags nvidia       (default: 0)
#   INCLUDE_NIGHTLY  1 = import nightly repos          (default: 0)
#   INCLUDE_EXTRA    1 = import extra-packages.repos   (default: 0)
#                    (hardware-specific drivers; deps may need manual install)
#   CLEAN_BUILD      1 = remove build/install/log      (default: 0, forced on FRESH_INSTALL)
#   BUILD_JOBS       parallel build jobs               (default: nproc/2)
###############################################################################
set -euo pipefail

# ─── Logging ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()   { echo -e "${GREEN}[ OK ]${NC}  $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_err()  { echo -e "${RED}[FAIL]${NC}  $*"; }
log_step() { echo -e "\n${BOLD}── Step $1/$TOTAL_STEPS: $2${NC}"; }

elapsed() { local s=$(( $(date +%s) - $1 )); printf '%dm%02ds' $((s/60)) $((s%60)); }

# ─── Configuration ─────────────────────────────────────────────────────────
AUTOWARE_DIR="${AUTOWARE_DIR:-$HOME/autoware}"
AUTOWARE_BRANCH="${AUTOWARE_BRANCH:-main}"
FRESH_INSTALL="${FRESH_INSTALL:-0}"
SETUP_DEV_ENV="${SETUP_DEV_ENV:-0}"
SKIP_NVIDIA="${SKIP_NVIDIA:-0}"
INCLUDE_NIGHTLY="${INCLUDE_NIGHTLY:-0}"
INCLUDE_EXTRA="${INCLUDE_EXTRA:-0}"
CLEAN_BUILD="${CLEAN_BUILD:-0}"
BUILD_JOBS="${BUILD_JOBS:-$(( $(nproc) / 2 ))}"
[ "$BUILD_JOBS" -lt 1 ] && BUILD_JOBS=1
[ "$FRESH_INSTALL" = "1" ] && CLEAN_BUILD=1

TOTAL_STEPS=6
[ "$SETUP_DEV_ENV" = "1" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))

# ─── Initial clone (FRESH_INSTALL only) ────────────────────────────────────
if [ ! -d "$AUTOWARE_DIR" ]; then
    if [ "$FRESH_INSTALL" = "1" ]; then
        log_info "Cloning autoware → $AUTOWARE_DIR"
        git clone https://github.com/autowarefoundation/autoware.git "$AUTOWARE_DIR"
    else
        log_err "Autoware workspace not found: $AUTOWARE_DIR"
        log_err "For a new installation, run:"
        log_err "  FRESH_INSTALL=1 bash ~/autoware_update_script/update_autoware.sh"
        exit 1
    fi
fi

cd "$AUTOWARE_DIR"

if [ ! -d ".git" ] || [ ! -d "repositories" ]; then
    log_err "Not a valid Autoware root (missing .git/ or repositories/): $AUTOWARE_DIR"
    exit 1
fi

SCRIPT_START=$(date +%s)
CURRENT_REV=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
UPDATE_MODE=$([ "$FRESH_INSTALL" = "1" ] && echo "fresh (re-clone)" || echo "update (pull)")

echo ""
echo -e "${BOLD}Autoware Update${NC}"
echo -e "  Directory : $AUTOWARE_DIR"
echo -e "  Branch    : $AUTOWARE_BRANCH  (at $CURRENT_REV)"
echo -e "  Mode      : $UPDATE_MODE"
echo -e "  Jobs      : $BUILD_JOBS"
echo -e "  Options   : setup-dev-env=$SETUP_DEV_ENV  skip-nvidia=$SKIP_NVIDIA  nightly=$INCLUDE_NIGHTLY  extra=$INCLUDE_EXTRA  clean-build=$CLEAN_BUILD"
echo ""

# ─── Detect uncommitted work in src/ ───────────────────────────────────────
# vcs pull may fail on dirty repos; FRESH_INSTALL will delete them outright.
# Either way: warn first, let the user abort.
if [ -d "src" ]; then
    DIRTY=()
    while IFS= read -r g; do
        d="$(dirname "$g")"
        if ! git -C "$d" diff --quiet 2>/dev/null || ! git -C "$d" diff --cached --quiet 2>/dev/null; then
            DIRTY+=("$d")
        fi
    done < <(find src -maxdepth 3 -name ".git" -type d 2>/dev/null)

    if [ "${#DIRTY[@]}" -gt 0 ]; then
        log_warn "Uncommitted changes detected in src/:"
        for r in "${DIRTY[@]}"; do echo "    - $r"; done
        if [ "$FRESH_INSTALL" = "1" ]; then
            log_warn "FRESH_INSTALL=1 will REMOVE src/ — these changes will be lost."
        else
            log_warn "vcs pull may conflict with these changes."
        fi
        read -rp "  Continue anyway? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { log_info "Aborted."; exit 0; }
    fi
fi

STEP=0

###############################################################################
# Step: Update root repository
###############################################################################
STEP=$((STEP+1)); log_step $STEP "Updating root repository → $AUTOWARE_BRANCH"
T=$(date +%s)

git fetch --prune --tags

# Stash local changes (never committed or pushed on user's behalf).
if ! git diff --quiet || ! git diff --cached --quiet; then
    STASH_NAME="autoware-update-$(date +%Y%m%d-%H%M%S)"
    log_warn "Stashing local changes as '$STASH_NAME'."
    git stash push -m "$STASH_NAME"
fi

git checkout "$AUTOWARE_BRANCH" 2>/dev/null \
    || git checkout -b "$AUTOWARE_BRANCH" "origin/$AUTOWARE_BRANCH"
git merge --ff-only "origin/$AUTOWARE_BRANCH"

NEW_REV=$(git rev-parse --short HEAD)
log_ok "Root: $CURRENT_REV → $NEW_REV  ($(elapsed $T))"

###############################################################################
# Step (optional): install dev environment via Ansible
#
# As of the deprecation of setup-dev-env.sh (planned removal 2026-05-24), the
# official source-installation guide instructs users to invoke the Ansible
# playbook directly. See:
#   https://github.com/orgs/autowarefoundation/discussions/7065
###############################################################################
if [ "$SETUP_DEV_ENV" = "1" ]; then
    STEP=$((STEP+1)); log_step $STEP "Installing dev environment via Ansible"
    T=$(date +%s)
    if [ -f "ansible/scripts/install-ansible.sh" ] \
        && [ -f "ansible-galaxy-requirements.yaml" ]; then
        if [ "$SKIP_NVIDIA" != "1" ]; then
            log_info "Ensure you have agreed to NVIDIA CUDA / cuDNN / TensorRT licenses."
        fi
        bash ansible/scripts/install-ansible.sh
        ansible-galaxy collection install -f -r ansible-galaxy-requirements.yaml
        if [ "$SKIP_NVIDIA" = "1" ]; then
            log_info "Skipping NVIDIA-tagged roles (--skip-tags nvidia)."
            ansible-playbook autoware.dev_env.install_dev_env --skip-tags nvidia
        else
            ansible-playbook autoware.dev_env.install_dev_env
        fi
        log_ok "Dev env install complete  ($(elapsed $T))"
    else
        log_warn "ansible/scripts/install-ansible.sh or ansible-galaxy-requirements.yaml not found — skipping."
    fi
fi

###############################################################################
# Step: Sync src/ repositories
#
# Matches the doc's "Update the repositories" step — runs before the ROS /
# apt / rosdep block so dependency resolution sees freshly imported sources.
###############################################################################
STEP=$((STEP+1)); log_step $STEP "Syncing src/ ($UPDATE_MODE)"
T=$(date +%s)

if [ "$FRESH_INSTALL" = "1" ] && [ -d "src" ]; then
    rm -rf src
fi
mkdir -p src

vcs import src < repositories/autoware.repos

if [ "$INCLUDE_NIGHTLY" = "1" ] && [ -f "repositories/autoware-nightly.repos" ]; then
    log_warn "Nightly repositories may be unstable."
    vcs import src < repositories/autoware-nightly.repos
fi

if [ "$INCLUDE_EXTRA" = "1" ] && [ -f "repositories/extra-packages.repos" ]; then
    log_warn "Extra packages may require manual dependency installation."
    vcs import src < repositories/extra-packages.repos
fi

# vcs pull is unnecessary after a fresh import.
[ "$FRESH_INSTALL" = "1" ] || vcs pull src

REPO_COUNT=$(find src -maxdepth 3 -name ".git" -type d | wc -l)
log_ok "$REPO_COUNT repositories synced  ($(elapsed $T))"

###############################################################################
# Step: Source ROS 2
###############################################################################
STEP=$((STEP+1)); log_step $STEP "Sourcing ROS 2"

if [ -f "/opt/ros/humble/setup.bash" ]; then
    source /opt/ros/humble/setup.bash
elif [ -f "/opt/ros/jazzy/setup.bash" ]; then
    source /opt/ros/jazzy/setup.bash
else
    log_err "No ROS 2 installation found under /opt/ros/."
    exit 1
fi
log_ok "ROS 2 $ROS_DISTRO sourced."

###############################################################################
# Step: System package upgrade
###############################################################################
STEP=$((STEP+1)); log_step $STEP "Upgrading system packages"
T=$(date +%s)
sudo apt-get update -qq
sudo apt-get upgrade -y -qq
log_ok "apt upgrade complete  ($(elapsed $T))"

###############################################################################
# Step: Resolve ROS dependencies
###############################################################################
STEP=$((STEP+1)); log_step $STEP "Resolving dependencies (rosdep)"
T=$(date +%s)

if [ ! -d "/etc/ros/rosdep/sources.list.d" ]; then
    sudo rosdep init || true
fi
rosdep update --rosdistro "$ROS_DISTRO"
rosdep install -y --from-paths src --ignore-src --rosdistro "$ROS_DISTRO"
log_ok "Dependencies resolved  ($(elapsed $T))"

###############################################################################
# Step: Build workspace
###############################################################################
STEP=$((STEP+1)); log_step $STEP "Building workspace"
T=$(date +%s)

if [ "$CLEAN_BUILD" = "1" ]; then
    rm -rf build/ install/ log/
    log_info "Cleared build/ install/ log/."
fi

if command -v ccache &>/dev/null; then
    export CC="ccache gcc" CXX="ccache g++"
    log_info "ccache enabled."
fi

colcon build \
    --symlink-install \
    --cmake-args -DCMAKE_BUILD_TYPE=Release \
    --parallel-workers "$BUILD_JOBS"

log_ok "Build complete  ($(elapsed $T))"

###############################################################################
# Summary
###############################################################################
echo ""
echo -e "${BOLD}Update Complete${NC}"
echo -e "  Branch    : $AUTOWARE_BRANCH ($NEW_REV)"
echo -e "  Mode      : $UPDATE_MODE"
echo -e "  Repos     : $REPO_COUNT"
echo -e "  Duration  : $(elapsed $SCRIPT_START)"
echo ""
echo -e "  Next:  source $AUTOWARE_DIR/install/setup.bash"
echo ""

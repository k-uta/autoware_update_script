#!/bin/bash
###############################################################################
# Autoware Update Script
#
# Based on the official documentation:
#   https://autowarefoundation.github.io/autoware-documentation/main/installation/autoware/source-installation/
#
# Keeps an Autoware workspace in sync with the latest upstream.
# Designed to be run regularly (e.g. every morning before starting work).
#
# NOTE: This script is READ-ONLY with respect to remotes.
#       It will NEVER push, force-push, or modify any remote repository.
#       All operations are local fetches, checkouts, and builds only.
#
# This script is expected to be placed at:
#   ~/autoware_update_script/update_autoware.sh
# It operates on the Autoware workspace at AUTOWARE_DIR (default: ~/autoware).
#
# Usage:
#   bash ~/autoware_update_script/update_autoware.sh
#   AUTOWARE_BRANCH=release/v1.0 bash ~/autoware_update_script/update_autoware.sh
#   FRESH_INSTALL=1 bash ~/autoware_update_script/update_autoware.sh  # first install or re-clone
#
# Environment variables:
#   AUTOWARE_DIR        : Autoware root directory         (default: ~/autoware)
#   AUTOWARE_BRANCH     : Branch or tag to track          (default: main)
#   FRESH_INSTALL       : Set to "1" to re-clone src/     (default: 0, uses vcs pull)
#                         Also handles initial clone if AUTOWARE_DIR does not exist.
#   SETUP_DEV_ENV       : Set to "1" to run setup-dev-env.sh (default: 0)
#   INCLUDE_NIGHTLY     : Set to "1" to import nightly repos (default: 0)
#   BUILD_JOBS          : Parallel build jobs              (default: nproc/2)
###############################################################################
set -euo pipefail

# ─── Logging helpers ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[FAIL]${NC}  $*"; }
log_step()  { echo -e "\n${BOLD}── Step $1/$TOTAL_STEPS: $2${NC}"; }

elapsed() {
    local secs=$(( $(date +%s) - $1 ))
    printf '%dm %ds' $((secs / 60)) $((secs % 60))
}

# ─── Configuration ───────────────────────────────────────────────────────────
AUTOWARE_DIR="${AUTOWARE_DIR:-$HOME/autoware}"
AUTOWARE_BRANCH="${AUTOWARE_BRANCH:-main}"
FRESH_INSTALL="${FRESH_INSTALL:-0}"
SETUP_DEV_ENV="${SETUP_DEV_ENV:-0}"
INCLUDE_NIGHTLY="${INCLUDE_NIGHTLY:-0}"
BUILD_JOBS="${BUILD_JOBS:-$(( $(nproc) / 2 ))}"
[ "$BUILD_JOBS" -lt 1 ] && BUILD_JOBS=1

# Calculate total steps dynamically
TOTAL_STEPS=6
[ "$SETUP_DEV_ENV" = "1" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))

# ─── Workspace existence check ───────────────────────────────────────────────
# If AUTOWARE_DIR does not exist, clone the autoware repository (FRESH_INSTALL only).
if [ ! -d "$AUTOWARE_DIR" ]; then
    if [ "$FRESH_INSTALL" = "1" ]; then
        log_info "Autoware workspace not found at $AUTOWARE_DIR."
        log_info "Cloning autoware repository..."
        git clone https://github.com/autowarefoundation/autoware.git "$AUTOWARE_DIR"
        log_ok "Repository cloned to $AUTOWARE_DIR."
    else
        log_error "Autoware workspace not found: $AUTOWARE_DIR"
        log_error "For a new installation, run:"
        log_error "  FRESH_INSTALL=1 bash ~/autoware_update_script/update_autoware.sh"
        exit 1
    fi
fi

cd "$AUTOWARE_DIR"

# ─── Pre-flight checks ──────────────────────────────────────────────────────
if [ ! -d ".git" ] || [ ! -d "repositories" ]; then
    log_error "Not a valid Autoware root repository: $AUTOWARE_DIR"
    log_error "Expected .git/ and repositories/ directories."
    log_error "For a new installation, remove the directory and run:"
    log_error "  FRESH_INSTALL=1 bash ~/autoware_update_script/update_autoware.sh"
    exit 1
fi

SCRIPT_START=$(date +%s)
CURRENT_REV=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Determine update mode label
if [ "$FRESH_INSTALL" = "1" ]; then
    UPDATE_MODE="fresh (re-clone)"
else
    UPDATE_MODE="update (pull)"
fi

echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║              Autoware Update                              ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Directory : ${BOLD}$AUTOWARE_DIR${NC}"
echo -e "  Branch    : ${BOLD}$AUTOWARE_BRANCH${NC}"
echo -e "  Current   : ${DIM}$CURRENT_REV${NC}"
echo -e "  Mode      : ${BOLD}$UPDATE_MODE${NC}"
echo -e "  Jobs      : ${BOLD}$BUILD_JOBS${NC}"
echo -e "  Timestamp : $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo -e "  Options   : setup-dev-env=${BOLD}$SETUP_DEV_ENV${NC}  nightly=${BOLD}$INCLUDE_NIGHTLY${NC}"
echo ""

# ─── Check for uncommitted work in src/ repos ───────────────────────────────
# Alert the user about any uncommitted changes BEFORE touching anything.
# This script never pushes or commits on the user's behalf.
if [ -d "src" ]; then
    DIRTY_REPOS=()
    while IFS= read -r git_dir; do
        repo_dir="$(dirname "$git_dir")"
        if ! git -C "$repo_dir" diff --quiet 2>/dev/null || \
           ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
            DIRTY_REPOS+=("$repo_dir")
        fi
    done < <(find src -maxdepth 3 -name ".git" -type d 2>/dev/null)

    if [ "${#DIRTY_REPOS[@]}" -gt 0 ]; then
        echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  Uncommitted changes detected in src/ repositories        ║${NC}"
        echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        for repo in "${DIRTY_REPOS[@]}"; do
            echo -e "  ${YELLOW}●${NC} $repo"
        done
        echo ""
        log_warn "These changes will be LOST when src/ is cleaned."
        log_warn "Please commit or back up your work before continuing."
        echo ""
        read -rp "  Continue anyway? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "Aborted by user."
            exit 0
        fi
        echo ""
    fi
fi

# ─── Check for uncommitted work in root repository ──────────────────────────
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  Uncommitted changes detected in root repository          ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    git -C "$AUTOWARE_DIR" status --short
    echo ""
    log_warn "These changes will be stashed automatically."
    echo ""
fi

STEP=0

###############################################################################
# Step: Update Autoware root repository
###############################################################################
STEP=$((STEP + 1)); log_step $STEP "Updating root repository → $AUTOWARE_BRANCH"
STEP_START=$(date +%s)

# Fetch only — never push
git fetch --all --prune --tags

# Stash local changes (never committed or pushed on user's behalf)
if ! git diff --quiet || ! git diff --cached --quiet; then
    STASH_NAME="autoware-update-$(date +%Y%m%d-%H%M%S)"
    log_warn "Stashing local changes as '$STASH_NAME'."
    git stash push -m "$STASH_NAME"
fi

git checkout "$AUTOWARE_BRANCH" 2>/dev/null \
    || git checkout -b "$AUTOWARE_BRANCH" "origin/$AUTOWARE_BRANCH"
git reset --hard "origin/$AUTOWARE_BRANCH"

NEW_REV=$(git rev-parse --short HEAD)
log_ok "Root updated: $CURRENT_REV → $NEW_REV  ($(elapsed $STEP_START))"

###############################################################################
# Step (optional): Run setup-dev-env.sh
###############################################################################
if [ "$SETUP_DEV_ENV" = "1" ]; then
    STEP=$((STEP + 1)); log_step $STEP "Running setup-dev-env.sh"
    STEP_START=$(date +%s)

    if [ -f "./setup-dev-env.sh" ]; then
        log_info "Installing/updating development dependencies via Ansible..."
        log_info "NVIDIA licenses: CUDA / cuDNN / TensorRT — ensure you have agreed."
        ./setup-dev-env.sh -y
        log_ok "setup-dev-env.sh done.  ($(elapsed $STEP_START))"
    else
        log_warn "setup-dev-env.sh not found — skipping."
    fi
fi

###############################################################################
# Step: Update system packages
###############################################################################
STEP=$((STEP + 1)); log_step $STEP "Updating system packages"
STEP_START=$(date +%s)

sudo apt-get update -qq
sudo apt-get upgrade -y -qq
sudo apt-get autoremove -y -qq

log_ok "System packages up to date.  ($(elapsed $STEP_START))"

###############################################################################
# Step: Source ROS 2 environment
###############################################################################
STEP=$((STEP + 1)); log_step $STEP "Sourcing ROS 2 environment"

if [ -f "/opt/ros/humble/setup.bash" ]; then
    source /opt/ros/humble/setup.bash
    log_ok "ROS 2 Humble sourced (ROS_DISTRO=$ROS_DISTRO)."
elif [ -f "/opt/ros/jazzy/setup.bash" ]; then
    source /opt/ros/jazzy/setup.bash
    log_ok "ROS 2 Jazzy sourced (ROS_DISTRO=$ROS_DISTRO)."
else
    log_error "No ROS 2 installation found under /opt/ros/."
    exit 1
fi

###############################################################################
# Step: Sync source repositories
###############################################################################
STEP=$((STEP + 1)); log_step $STEP "Syncing source repositories ($UPDATE_MODE)"
STEP_START=$(date +%s)

if [ "$FRESH_INSTALL" = "1" ]; then
    # ── Fresh mode: delete src/ entirely and re-clone everything ──
    # Guarantees a completely clean state with no leftover artifacts.
    # The official docs note that moved/removed repos are not handled by vcs:
    #   https://autowarefoundation.github.io/autoware-documentation/main/installation/autoware/source-installation/#how-to-update-a-workspace
    if [ -d "src" ]; then
        log_info "FRESH_INSTALL=1 — removing src/ entirely..."
        rm -rf src
    fi
    mkdir -p src

    log_info "vcs import src < repositories/autoware.repos"
    vcs import src < repositories/autoware.repos

    if [ "$INCLUDE_NIGHTLY" = "1" ] && [ -f "repositories/autoware-nightly.repos" ]; then
        log_info "vcs import src < repositories/autoware-nightly.repos"
        log_warn "Nightly repositories may be unstable."
        vcs import src < repositories/autoware-nightly.repos
    fi
else
    # ── Update mode: keep src/ and pull latest changes ──
    # Faster for daily use; vcs import updates branch/tag pointers,
    # then vcs pull fetches the latest commits.
    mkdir -p src

    log_info "vcs import src < repositories/autoware.repos"
    vcs import src < repositories/autoware.repos

    if [ "$INCLUDE_NIGHTLY" = "1" ] && [ -f "repositories/autoware-nightly.repos" ]; then
        log_info "vcs import src < repositories/autoware-nightly.repos"
        log_warn "Nightly repositories may be unstable."
        vcs import src < repositories/autoware-nightly.repos
    fi

    log_info "vcs pull src"
    vcs pull src
fi

REPO_COUNT=$(find src -maxdepth 3 -name ".git" -type d | wc -l)
log_ok "$REPO_COUNT repositories synced.  ($(elapsed $STEP_START))"

###############################################################################
# Step: Resolve dependencies (rosdep + pip)
###############################################################################
STEP=$((STEP + 1)); log_step $STEP "Resolving dependencies"
STEP_START=$(date +%s)

# rosdep
if [ ! -d "/etc/ros/rosdep/sources.list.d" ]; then
    sudo rosdep init || true
fi
rosdep update --rosdistro "$ROS_DISTRO"
rosdep install -y --from-paths src --ignore-src --rosdistro "$ROS_DISTRO"
log_ok "rosdep dependencies resolved."

# pip
PIP_COUNT=0
while IFS= read -r req_file; do
    log_info "pip3 install --upgrade -r $req_file"
    pip3 install --upgrade -r "$req_file" 2>/dev/null || true
    PIP_COUNT=$((PIP_COUNT + 1))
done < <(find src -name "requirements.txt" -type f)

if [ "$PIP_COUNT" -gt 0 ]; then
    log_ok "$PIP_COUNT requirements.txt file(s) processed."
else
    log_info "No requirements.txt files found."
fi

log_ok "All dependencies resolved.  ($(elapsed $STEP_START))"

###############################################################################
# Step: Build workspace
###############################################################################
STEP=$((STEP + 1)); log_step $STEP "Building workspace"
STEP_START=$(date +%s)

rm -rf build/ install/ log/
log_info "Cleared build/ install/ log/."

# Use ccache if available
if command -v ccache &>/dev/null; then
    export CC="ccache gcc"
    export CXX="ccache g++"
    ccache --zero-stats >/dev/null
    log_info "ccache enabled."
fi

log_info "colcon build --symlink-install --parallel-workers $BUILD_JOBS"
colcon build \
    --symlink-install \
    --cmake-args -DCMAKE_BUILD_TYPE=Release \
    --parallel-workers "$BUILD_JOBS"

if command -v ccache &>/dev/null; then
    CCACHE_STATS=$(ccache --show-stats 2>/dev/null | grep "Hits:" | head -1 || true)
    [ -n "$CCACHE_STATS" ] && log_info "ccache: $CCACHE_STATS"
fi

log_ok "Build complete.  ($(elapsed $STEP_START))"

###############################################################################
# Summary
###############################################################################
TOTAL_ELAPSED=$(elapsed $SCRIPT_START)

echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║              Update Complete                              ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Branch    : ${BOLD}$AUTOWARE_BRANCH${NC}  ($NEW_REV)"
echo -e "  Mode      : ${BOLD}$UPDATE_MODE${NC}"
echo -e "  Repos     : ${BOLD}$REPO_COUNT${NC} repositories"
echo -e "  Duration  : ${BOLD}$TOTAL_ELAPSED${NC}"
echo -e "  Finished  : $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo -e "  ${GREEN}Ready to use:${NC}"
echo -e "    source install/setup.bash"
echo ""

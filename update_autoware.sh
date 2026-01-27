#!/bin/bash
# Stop script on error
set -e

echo "=== 1. Update Autoware Root Repository ==="
# Update the .repos files and other configuration files from the remote.
# Note: If you are working on a feature branch in the root 'autoware' directory,
# you might want to use 'git merge origin/main' or 'git rebase origin/main' instead.
git pull origin main

echo "=== 2. Sync Repository List (vcs import) ==="
# Ensure src directory exists
mkdir -p src

# Import repositories based on autoware.repos
vcs import src < repositories/autoware.repos

# Import nightly repositories (Optional: comment out if not needed) 
vcs import src < repositories/autoware-nightly.repos

echo "=== 3. Pull Latest Changes (vcs pull) ==="
# 'vcs import' switches branches/tags but may not pull the latest commit.
# 'vcs pull' ensures all repositories are up-to-date with the remote. 
# vcs pull src

echo "=== 4. Update Dependencies ==="
# Source ROS 2 environment (assuming humble)
source /opt/ros/humble/setup.bash

# Update system packages
sudo apt update && sudo apt upgrade -y

# Update rosdep database
rosdep update

# Install missing dependencies
rosdep install -y --from-paths src --ignore-src --rosdistro $ROS_DISTRO

echo "=== 5. Clean and Build Workspace ==="
# Clean
rm -rf build install log
# Build with colcon
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release

echo "=== Update Complete ==="

# How to use
# source ./update_autoware.sh
# or
# bash ./update_autoware.sh

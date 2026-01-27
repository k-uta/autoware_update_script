# autoware_update_script

This repository provides a utility script to automate the synchronization and rebuilding process for an existing [Autoware](https://github.com/autowarefoundation/autoware) workspace.

## Overview

Once you have completed the [initial source installation](https://autowarefoundation.github.io/autoware-documentation/main/installation/autoware/source-installation/), keeping the workspace up-to-date with the latest upstream changes requires multiple manual steps. 

This script streamlines the maintenance workflow into a single command, ensuring your environment is always synchronized with the `main` branch and all dependencies are resolved.

## Features

- **Automated Upstream Sync**: Performs `git pull` on the root repository.
- **VCS Management**: Imports latest sub-repository definitions from `.repos` files (including nightly).
- **Dependency Alignment**: Automatically runs `rosdep install` to fetch new dependencies required by updated source code.
- **Clean Build**: Removes previous artifacts and executes a fresh `colcon build` with `Release` optimization.

## Prerequisites

This script assumes that you have already:
1. Set up an Autoware workspace following the [official documentation](https://autowarefoundation.github.io/autoware-documentation/main/installation/autoware/source-installation/).
2. Confirmed that the workspace builds and runs correctly in your environment.

## Usage

Place the script in your Autoware workspace root directory.

```bash
cd ~/autoware
chmod +x update_autoware.sh
./update_autoware.sh

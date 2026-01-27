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
```
## Important Notes

> [!WARNING]
> This script performs a **Clean Build** (`rm -rf build install log`). Depending on your system specifications, the build process may take a significant amount of time.

## Disclaimer

**Use this script at your own risk.**

- This script is an unofficial utility and is not an official Autoware Foundation product.
- The author is not responsible for any data loss, build failures, or damage to your development environment that may occur while using this script.
- Since it performs a clean build, ensure you do not have any unsaved changes in your `build`, `install`, or `log` directories (though these are typically not for manual edits).
- Always verify the script content before execution to ensure it fits your specific workspace configuration.

## License

This project is licensed under the [Apache License 2.0](LICENSE).

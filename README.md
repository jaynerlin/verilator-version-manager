# Verilator Version Manager

A simple yet powerful bash script to build, manage, and switch between multiple Verilator versions on a single system. This tool is especially useful for developers working with hardware description languages and toolchains like [SpinalHDL](https://spinalhdl.github.io/SpinalDoc-RTD/master/index.html), where projects may depend on specific Verilator versions.

The main challenge this script solves is ensuring that the correct Verilator version is discoverable by other tools, which is typically handled by setting the `VERILATOR_ROOT` environment variable permanently in your `.bashrc` file.

## Key Features

-   **Build from Source**: Clones the official Verilator repository and builds any specified version tag.
-   **Permanent Version Switching**: Modifies your `.bashrc` to permanently set the `VERILATOR_ROOT` and `PATH` for all new shell sessions.
-   **Automatic Structure-Fixing**: Intelligently detects pre-compiled Verilator binaries (which have a different directory structure) and creates the necessary symlinks to ensure tool compatibility.
-   **Safe Operations**: Automatically backs up your `.bashrc` before making changes and provides a simple restore command.
-   **User-Friendly Interface**: Simple commands to list available versions, check the current configuration, and switch versions.

## Prerequisites

-   `git`: To clone the Verilator repository.
-   `bash`: To run the scripts.
-   **Verilator Build Dependencies**: To build Verilator from source, you need to install its prerequisites. Please refer to the [official Verilator installation guide](https://verilator.org/guide/latest/install.html#git-quick-install) for the complete list of required packages (e.g., `g++`, `make`, `perl`, `autoconf`, etc.).

## Installation and Usage

### 1. Clone this Repository

```bash
git clone <your-repo-url>
cd <your-repo-name>
```

### 2. Setup Verilator Source Repository

First, you need to clone the official Verilator repository. The script will manage this for you.

```bash
./build_multiple_versions.sh setup
```

This will clone Verilator into a `verilator_repo` directory inside the project folder.

### 3. Build Verilator Versions

You can list all available version tags and then build the ones you need.

```bash
# List available versions (tags)
./build_multiple_versions.sh list

# Build a specific version (e.g., v5.024)
./build_multiple_versions.sh build v5.024

# Build multiple versions at once
./build_multiple_versions.sh build-multiple v5.022 v5.020
```

The compiled versions will be installed into separate directories (e.g., `verilator_v5.024/`).

### 4. Switch Verilator Version

To switch the system's default Verilator version, use the `switch_verilator.sh` script.

```bash
# Switch to version v4.228
./switch_verilator.sh switch v4.228
```

This command will:
1.  Update your `~/.bashrc` to point `VERILATOR_ROOT` to the new version's path.
2.  Automatically fix the directory structure if it detects a pre-compiled binary.

**Important**: After switching, you must restart your shell or source your `.bashrc` for the changes to take effect in your current session.

```bash
source ~/.bashrc
```

### 5. Check Current Configuration

To see which version is currently active in your environment and configured in your `.bashrc`, use the `current` command.

```bash
./switch_verilator.sh current
```

## Command Reference

### `build_multiple_versions.sh`

-   `setup`: Clones or updates the local Verilator source repository.
-   `build <version>`: Builds and installs a single Verilator version.
-   `build-multiple <v1> <v2> ...`: Builds and installs multiple versions.
-   `list`: Lists available Verilator tags from the source repository.
-   `installed`: Lists locally built/installed Verilator versions.
-   `switcher`: (Re)generates the `switch_verilator.sh` script.

### `switch_verilator.sh`

-   `switch <version>` or `<version>`: Switches the default Verilator version by updating `.bashrc`.
-   `current`: Displays the current version configuration.
-   `list`: Lists all locally installed and switchable versions.
-   `restore-bashrc`: Restores the `.bashrc` file from backup.

## License

This project is licensed under the MIT License. Feel free to use, modify, and distribute it. 
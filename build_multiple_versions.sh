#!/bin/bash
# Multi-Version Verilator Build and Management Script

set -e

# Configuration
BASE_DIR="/e/verilator_versions"
REPO_URL="https://github.com/verilator/verilator.git/"
REPO_DIR="$BASE_DIR/verilator_repo"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to setup repository
setup_repo() {
    log "Setting up Verilator repository..."
    
    if [ ! -d "$REPO_DIR" ]; then
        log "Cloning Verilator repository..."
        git clone "$REPO_URL" "$REPO_DIR"
    else
        log "Updating existing repository..."
        cd "$REPO_DIR"
        git fetch --all --tags
    fi
}

# Function to build a specific version
build_version() {
    local version=$1
    local install_dir="$BASE_DIR/verilator_$version"
    
    log "Building Verilator version: $version"
    
    # Check if already built
    if [ -d "$install_dir" ] && [ -f "$install_dir/bin/verilator" ]; then
        log "Version $version already exists at $install_dir"
        return 0
    fi
    
    cd "$REPO_DIR"
    
    # Checkout the specific version
    log "Checking out version $version"
    git checkout "$version" || {
        error "Failed to checkout version $version"
        return 1
    }
    
    # Clean previous build
    make distclean 2>/dev/null || true
    
    # Configure for this version
    log "Configuring build..."
    autoconf
    
    # Set environment for MSYS2 compatibility
    export PATH=/usr/bin:/mingw64/bin:$PATH
    export CPPFLAGS="-I/usr/include"
    
    ./configure --prefix="$install_dir" || {
        error "Configure failed for version $version"
        return 1
    }
    
    # Fix version generation if needed
    if [ -f "src/config_rev" ]; then
        python3 src/config_rev . > src/config_rev.h
    fi
    
    # Build
    log "Compiling version $version..."
    make -j$(nproc) || {
        error "Build failed for version $version"
        return 1
    }
    
    # Install to version-specific directory
    log "Installing to $install_dir..."
    make install || {
        error "Install failed for version $version"
        return 1
    }
    
    # Create version info file
    echo "$version" > "$install_dir/VERSION"
    echo "Built on: $(date)" >> "$install_dir/VERSION"
    echo "Git commit: $(git rev-parse HEAD)" >> "$install_dir/VERSION"
    
    log "Successfully built and installed Verilator $version"
}

# Function to list available versions
list_versions() {
    log "Available Verilator versions in repository:"
    cd "$REPO_DIR"
    git tag | grep -E "^v[0-9]+\.[0-9]+.*" | sort -V | tail -20
}

# Function to list installed versions
list_installed() {
    log "Installed Verilator versions:"
    for dir in "$BASE_DIR"/verilator_v*; do
        if [ -d "$dir" ] && [ -f "$dir/bin/verilator" ]; then
            version=$(basename "$dir" | sed 's/verilator_//')
            if [ -f "$dir/VERSION" ]; then
                info=$(head -1 "$dir/VERSION")
                echo -e "  ${BLUE}$version${NC} - $info"
            else
                echo -e "  ${BLUE}$version${NC}"
            fi
        fi
    done
}

# Function to test a specific version
test_version() {
    local version=$1
    local install_dir="$BASE_DIR/verilator_$version"
    
    if [ ! -f "$install_dir/bin/verilator" ]; then
        error "Version $version not found at $install_dir"
        return 1
    fi
    
    log "Testing Verilator version $version..."
    
    # Test basic functionality
    "$install_dir/bin/verilator" --version
    
    # Create a simple test
    local test_dir="/tmp/verilator_test_$version"
    mkdir -p "$test_dir"
    cd "$test_dir"
    
    cat > simple_test.v << 'VEOF'
module simple_test (
    input clk,
    input rst,
    output reg [7:0] counter
);

always @(posedge clk or posedge rst) begin
    if (rst)
        counter <= 8'b0;
    else
        counter <= counter + 1;
end

endmodule
VEOF
    
    # Try to lint the file
    if "$install_dir/bin/verilator" --lint-only simple_test.v; then
        log "Version $version passed basic test"
        rm -rf "$test_dir"
        return 0
    else
        error "Version $version failed basic test"
        return 1
    fi
}

# Function to create version switcher script
create_switcher() {
    local switcher_script="$BASE_DIR/switch_verilator.sh"
    
    cat > "$switcher_script" << 'SEOF'
#!/bin/bash
# Verilator Version Switcher - Permanent .bashrc Integration

BASE_DIR="/e/verilator_versions"
BASHRC_FILE="$HOME/.bashrc"
BACKUP_DIR="$BASE_DIR/.backups"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Initialize backup directory
init_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
    fi
}

# Backup .bashrc file
backup_bashrc() {
    init_backup_dir
    
    if [ -f "$BASHRC_FILE" ]; then
        if [ ! -f "$BACKUP_DIR/bashrc.backup" ]; then
            echo -e "${YELLOW}Backing up .bashrc file${NC}"
            cp "$BASHRC_FILE" "$BACKUP_DIR/bashrc.backup"
            echo -e "${GREEN}.bashrc backup created${NC}"
        else
            echo -e "${BLUE}.bashrc already backed up${NC}"
        fi
    else
        echo -e "${YELLOW}No .bashrc file found, will create one${NC}"
        touch "$BASHRC_FILE"
    fi
}

# Update VERILATOR_ROOT in .bashrc
update_bashrc_verilator() {
    local version=$1
    local install_dir="$BASE_DIR/verilator_$version"
    
    backup_bashrc
    
    # check if VERILATOR_ROOT is already set
    if grep -q "export VERILATOR_ROOT=" "$BASHRC_FILE" 2>/dev/null; then
        echo -e "${YELLOW}Updating existing VERILATOR_ROOT in .bashrc${NC}"
        # use sed to replace the existing VERILATOR_ROOT setting
        sed -i.tmp "s|^export VERILATOR_ROOT=.*|export VERILATOR_ROOT=\"$install_dir\"|g" "$BASHRC_FILE"
        # update the PATH with the verilator path
        if grep -q "VERILATOR_ROOT/bin" "$BASHRC_FILE"; then
            echo -e "${BLUE}VERILATOR_ROOT PATH already configured${NC}"
        else
            echo 'export PATH="$VERILATOR_ROOT/bin:$PATH"' >> "$BASHRC_FILE"
        fi
    else
        echo -e "${YELLOW}Adding VERILATOR_ROOT to .bashrc${NC}"
        # add the new VERILATOR_ROOT setting
        cat >> "$BASHRC_FILE" << BASHEOF

# Verilator Configuration - Added by verilator switcher
export VERILATOR_ROOT="$install_dir"
export PATH="\$VERILATOR_ROOT/bin:\$PATH"
BASHEOF
    fi
    
    # clean up the temporary file
    [ -f "$BASHRC_FILE.tmp" ] && rm -f "$BASHRC_FILE.tmp"
    
    echo -e "${GREEN}VERILATOR_ROOT updated in .bashrc to version $version${NC}"
    echo -e "${CYAN}New VERILATOR_ROOT: $install_dir${NC}"
    return 0
}

# Restore original .bashrc
restore_bashrc() {
    if [ -f "$BACKUP_DIR/bashrc.backup" ]; then
        echo -e "${YELLOW}Restoring original .bashrc${NC}"
        cp "$BACKUP_DIR/bashrc.backup" "$BASHRC_FILE"
        echo -e "${GREEN}.bashrc restored from backup${NC}"
    else
        echo -e "${YELLOW}No .bashrc backup found${NC}"
        echo -e "${YELLOW}Manually removing VERILATOR_ROOT lines...${NC}"
        # manually remove the VERILATOR_ROOT related lines
        grep -v "export VERILATOR_ROOT=" "$BASHRC_FILE" > "$BASHRC_FILE.tmp" 2>/dev/null || true
        grep -v "# Verilator Configuration" "$BASHRC_FILE.tmp" > "$BASHRC_FILE" 2>/dev/null || true
        rm -f "$BASHRC_FILE.tmp"
        echo -e "${GREEN}VERILATOR_ROOT lines removed${NC}"
    fi
}

# Fix precompiled version directory structure
fix_precompiled_structure() {
    local install_dir=$1
    
    # check if it is a precompiled version (no include directory but has share/verilator/include)
    if [ ! -d "$install_dir/include" ] && [ -d "$install_dir/share/verilator/include" ]; then
        echo -e "${YELLOW}Detected precompiled version, fixing directory structure...${NC}"
        
        # create the include directory symlink
        cd "$install_dir"
        if ln -s "share/verilator/include" "include" 2>/dev/null; then
            echo -e "${GREEN}✓ Created include directory symlink${NC}"
        else
            echo -e "${YELLOW}Include symlink already exists or creation failed${NC}"
        fi
        
        # check if other symlinks are needed
        if [ ! -d "$install_dir/examples" ] && [ -d "$install_dir/share/verilator/examples" ]; then
            if ln -s "share/verilator/examples" "examples" 2>/dev/null; then
                echo -e "${GREEN}✓ Created examples directory symlink${NC}"
            fi
        fi
        
        # check if the bin directory symlink is needed
        if [ ! -d "$install_dir/bin" ] && [ -d "$install_dir/share/verilator/bin" ]; then
            if ln -s "share/verilator/bin" "bin" 2>/dev/null; then
                echo -e "${GREEN}✓ Created bin directory symlink${NC}"
            fi
        fi
        
        cd - >/dev/null
        echo -e "${GREEN}Precompiled version structure fixed${NC}"
    fi
    
    # check
    if [ ! -f "$install_dir/include/verilated.mk" ]; then
        echo -e "${RED}Warning: verilated.mk still not found after structure fix${NC}"
        echo -e "${YELLOW}This may cause SpinalHDL compilation issues${NC}"
    else
        echo -e "${GREEN}✓ verilated.mk found and accessible${NC}"
    fi
}

show_current_version() {
    echo -e "${GREEN}=== Current Environment ===${NC}"
    if [ -n "$VERILATOR_ROOT" ]; then
        local current_version=""
        if [[ "$VERILATOR_ROOT" =~ verilator_(.+)$ ]]; then
            current_version="${BASH_REMATCH[1]}"
        fi
        
        if [ -n "$current_version" ]; then
            echo -e "${GREEN}Current version:${NC} ${BLUE}$current_version${NC}"
            echo -e "${CYAN}VERILATOR_ROOT:${NC} $VERILATOR_ROOT"
            
            # check if the version is actually available
            if [ -f "$VERILATOR_ROOT/bin/verilator" ]; then
                local ver_output=$("$VERILATOR_ROOT/bin/verilator" --version 2>/dev/null | head -1)
                echo -e "${CYAN}Version info:${NC} $ver_output"
            else
                echo -e "${YELLOW}Warning:${NC} Verilator binary not found at current VERILATOR_ROOT"
            fi
        else
            echo -e "${YELLOW}VERILATOR_ROOT is set but doesn't match expected pattern${NC}"
        fi
    else
        echo -e "${YELLOW}No VERILATOR_ROOT set in current environment${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}=== .bashrc Configuration ===${NC}"
    if [ -f "$BASHRC_FILE" ]; then
        local bashrc_verilator=$(grep "^export VERILATOR_ROOT=" "$BASHRC_FILE" 2>/dev/null | head -1)
        if [ -n "$bashrc_verilator" ]; then
            local bashrc_path=$(echo "$bashrc_verilator" | sed 's/^export VERILATOR_ROOT="//' | sed 's/"$//')
            if [[ "$bashrc_path" =~ verilator_(.+)$ ]]; then
                local bashrc_version="${BASH_REMATCH[1]}"
                echo -e "${GREEN}.bashrc version:${NC} ${BLUE}$bashrc_version${NC}"
                echo -e "${CYAN}.bashrc VERILATOR_ROOT:${NC} $bashrc_path"
            else
                echo -e "${YELLOW}.bashrc VERILATOR_ROOT doesn't match expected pattern${NC}"
            fi
        else
            echo -e "${YELLOW}No VERILATOR_ROOT found in .bashrc${NC}"
        fi
    else
        echo -e "${YELLOW}No .bashrc file found${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}=== Available in PATH ===${NC}"
    local system_verilator=$(which verilator 2>/dev/null)
    if [ -n "$system_verilator" ]; then
        echo -e "${CYAN}Verilator path:${NC} $system_verilator"
        local sys_ver_output=$("$system_verilator" --version 2>/dev/null | head -1)
        echo -e "${CYAN}Active version:${NC} $sys_ver_output"
    else
        echo -e "${YELLOW}No verilator found in PATH${NC}"
    fi
}

list_available_versions() {
    echo -e "${GREEN}Available Verilator versions:${NC}"
    local found=false
    for dir in "$BASE_DIR"/verilator_*; do
        if [ -d "$dir" ] && [ -f "$dir/bin/verilator" ]; then
            local version=$(basename "$dir" | sed 's/verilator_//')
            local current_marker=""
            
            # mark the current active version
            if [ -n "$VERILATOR_ROOT" ] && [[ "$VERILATOR_ROOT" == "$dir" ]]; then
                current_marker=" ${GREEN}(current)${NC}"
            fi
            
            if [ -f "$dir/VERSION" ]; then
                local info=$(head -1 "$dir/VERSION")
                echo -e "  ${BLUE}$version${NC} - $info${current_marker}"
            else
                echo -e "  ${BLUE}$version${NC}${current_marker}"
            fi
            found=true
        fi
    done
    
    if [ "$found" = false ]; then
        echo -e "  ${RED}No Verilator versions found${NC}"
        echo -e "  ${YELLOW}Run build_multiple_versions.sh to install versions${NC}"
    fi
}

switch_to_version() {
    local version=$1
    local install_dir="$BASE_DIR/verilator_$version"
    
    if [ ! -d "$install_dir" ]; then
        echo -e "${RED}Error: Version $version not found${NC}"
        echo ""
        list_available_versions
        return 1
    fi
    
    if [ ! -f "$install_dir/bin/verilator" ]; then
        echo -e "${RED}Error: Verilator binary not found for version $version${NC}"
        echo -e "${YELLOW}Directory exists but installation appears incomplete${NC}"
        return 1
    fi
    
    # check and fix the precompiled version directory structure
    fix_precompiled_structure "$install_dir"
    
    echo -e "${BLUE}Updating .bashrc for permanent switch...${NC}"
    if update_bashrc_verilator "$version"; then
        echo -e "${GREEN}Permanent switch completed${NC}"
        echo -e "${YELLOW}Changes will take effect in new shell sessions${NC}"
        echo -e "${YELLOW}To apply to current session, run: source ~/.bashrc${NC}"
        
        # show the current version information
        echo ""
        echo -e "${GREEN}Switched to Verilator $version${NC}"
        echo -e "${CYAN}VERILATOR_ROOT: $install_dir${NC}"
        
        # check if the installation is complete
        if [ -f "$install_dir/bin/verilator" ]; then
            local ver_output=$("$install_dir/bin/verilator" --version 2>/dev/null | head -1)
            echo -e "${CYAN}Version info: $ver_output${NC}"
        fi
    else
        echo -e "${RED}Failed to update .bashrc${NC}"
        return 1
    fi
    
    return 0
}



show_help() {
    echo "Verilator Version Switcher - Permanent .bashrc Integration"
    echo ""
    echo "Usage: $0 <command> [version]"
    echo ""
    echo "Commands:"
    echo -e "  ${BLUE}switch <version>${NC}        - Switch to specified verilator version permanently"
    echo -e "  ${BLUE}current${NC}                 - Show current version configuration"
    echo -e "  ${BLUE}list${NC}                    - List all available versions"
    echo -e "  ${BLUE}restore-bashrc${NC}          - Restore original .bashrc configuration"
    echo -e "  ${BLUE}help${NC}                    - Show this help message"
    echo ""
    echo "Examples:"
    echo -e "  ${CYAN}# Switch to specific version${NC}"
    echo -e "  ${CYAN}$0 switch v4.228${NC}"
    echo -e "  ${CYAN}source ~/.bashrc  # Apply to current session${NC}"
    echo ""
    echo -e "  ${CYAN}# Check current configuration${NC}"
    echo -e "  ${CYAN}$0 current${NC}"
    echo ""
    echo -e "  ${CYAN}# List available versions${NC}"
    echo -e "  ${CYAN}$0 list${NC}"
    echo ""
    echo -e "  ${CYAN}# Restore original .bashrc${NC}"
    echo -e "  ${CYAN}$0 restore-bashrc${NC}"
    echo ""
    echo -e "${YELLOW}Important Notes:${NC}"
    echo -e "• ${YELLOW}All switches are permanent and update .bashrc${NC}"
    echo -e "• ${YELLOW}Changes affect all new shell sessions and SpinalHDL${NC}"
    echo -e "• ${YELLOW}Use 'source ~/.bashrc' to apply changes to current session${NC}"
    echo ""
    echo -e "${YELLOW}Direct usage (for convenience):${NC}"
    echo -e "  ${CYAN}$0 <version>${NC}            - Same as 'switch <version>'"
}

# Main command handling
case "${1:-help}" in
    "switch")
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Please specify a version to switch to${NC}"
            echo ""
            list_available_versions
            exit 1
        fi
        echo -e "${YELLOW}Performing permanent switch by updating .bashrc${NC}"
        echo -e "${YELLOW}This will affect all new shell sessions and SpinalHDL${NC}"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            switch_to_version "$2"
        else
            echo -e "${YELLOW}Switch cancelled${NC}"
        fi
        ;;
    "current")
        show_current_version
        ;;
    "list")
        list_available_versions
        ;;
    "restore-bashrc")
        echo -e "${YELLOW}This will restore the original .bashrc configuration${NC}"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            restore_bashrc
        else
            echo -e "${YELLOW}.bashrc restore cancelled${NC}"
        fi
        ;;
    "help")
        show_help
        ;;
    *)
        # directly use the version number for convenience
        if [ -n "$1" ]; then
            echo -e "${YELLOW}Switching to Verilator $1${NC}"
            echo -e "${YELLOW}This will update .bashrc permanently${NC}"
            read -p "Continue? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                switch_to_version "$1"
            else
                echo -e "${YELLOW}Switch cancelled${NC}"
            fi
        else
            show_help
        fi
        ;;
esac
SEOF
    
    chmod +x "$switcher_script"
    log "Created permanent verilator version switcher at $switcher_script"
    log "Usage:"
    log "  Switch version: ./switch_verilator.sh switch <version>"
    log "  Direct usage: ./switch_verilator.sh <version>"
    log "  All switches update .bashrc permanently for SpinalHDL compatibility"
}

# Main command handling
case "${1:-help}" in
    "setup")
        setup_repo
        ;;
    "build")
        if [ -z "$2" ]; then
            error "Please specify a version to build"
            exit 1
        fi
        setup_repo
        build_version "$2"
        ;;
    "build-multiple")
        setup_repo
        shift
        for version in "$@"; do
            build_version "$version"
        done
        ;;
    "list")
        if [ -d "$REPO_DIR" ]; then
            list_versions
        else
            warn "Repository not set up. Run '$0 setup' first."
        fi
        ;;
    "installed")
        list_installed
        ;;
    "test")
        if [ -z "$2" ]; then
            error "Please specify a version to test"
            exit 1
        fi
        test_version "$2"
        ;;
    "switcher")
        create_switcher
        ;;
    "help"|*)
        echo "Verilator Multi-Version Management Script"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  setup                    - Clone/update Verilator repository"
        echo "  build <version>          - Build specific version"
        echo "  build-multiple <v1 v2>   - Build multiple versions"
        echo "  list                     - List available versions"
        echo "  installed                - List installed versions"
        echo "  test <version>           - Test specific version"
        echo "  switcher                 - Create version switcher script"
        echo ""
        echo "Examples:"
        echo "  $0 setup"
        echo "  $0 list"
        echo "  $0 build v5.024"
        echo "  $0 build-multiple v5.020 v5.024 v5.026"
        echo "  $0 test v5.024"
        ;;
esac

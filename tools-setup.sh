#!/usr/bin/env bash
# =============================================================================
# Pentest Tools Setup
# =============================================================================
#
# Installs personal pentest toolkit. Each tool is a github repo cloned into
# ~/Desktop/tools/<tool-name>/, with shell aliases auto-generated for fast access.
#
# This script lives in its own repo (e.g. github.com/<you>/tools-installer)
# and clones siblings tools next to itself.
#
# USAGE:
#   ./tools-setup.sh           # interactive
#   ./tools-setup.sh --yes     # non-interactive
#   ./tools-setup.sh --update  # git-pull all existing repos
#   ./tools-setup.sh --list    # show defined tools (no install)
#
# ADDING A NEW TOOL:
#   Add an entry to the TOOLS array below. Format:
#     "<dir>|<repo-url>|<alias>|<command>"
#
#   - dir:       lowercase folder name under TOOLS_DIR
#   - repo-url:  https github clone URL
#   - alias:     shortcut name (works in bash/zsh/fish)
#   - command:   what the alias runs. Use {DIR} as placeholder for the tool's path.
#
# =============================================================================

set -uo pipefail

# --- Configuration ---
readonly TOOLS_DIR="$HOME/Desktop/tools"
readonly ALIAS_FILE_BASH="$HOME/.config/tools-aliases.sh"
readonly ALIAS_FILE_FISH="$HOME/.config/fish/conf.d/tools-aliases.fish"
readonly LOG_FILE="/tmp/tools-setup-$(date +%Y%m%d-%H%M%S).log"

# --- Tool definitions ---
# Format: "dir|repo-url|alias|command"
# {DIR} in command is replaced with the full path to that tool's folder.

readonly TOOLS=(
    "http-smb-server|https://github.com/1337codes/OSCP-HTTP-SMB-File-Transfer-Server|tools|sudo python3 {DIR}/tools.py"
    "netcat-scanner|https://github.com/1337codes/OSCP-Netcat-scanner|ncscanner|sudo python3 {DIR}/ncscanner.py"
    "cve-suggester|https://github.com/1337codes/OSCP-CVE-exploit-suggester|cve|sudo python3 {DIR}/cve.py"
    "nxc-prey|https://github.com/1337codes/OSCP-NXC-PREY|nxcspray|bash {DIR}/nxc_spray.sh"
    "nhas-ssh|https://github.com/1337codes/OSCP-nhas-ssh-server|nhasup|bash {DIR}/nhas-start.sh"
    "ligolo|https://github.com/1337codes/OSCP-Ligolo|ligoloup|bash {DIR}/tunnels.sh"
    "ligolo|https://github.com/1337codes/OSCP-Ligolo|ligolofix|bash {DIR}/ligolofix.sh"
    "binary-check|https://github.com/1337codes/OSCP-Binary-Check|binary|sudo python3 {DIR}/app.py"
    "snmp-enum|https://github.com/1337codes/OSCP-SNMP-enumeration|snmpenum|sudo python3 {DIR}/snmp.py"
)

# --- Colors ---
readonly C_RESET=$'\033[0m'
readonly C_RED=$'\033[31m'
readonly C_GREEN=$'\033[32m'
readonly C_YELLOW=$'\033[33m'
readonly C_BLUE=$'\033[34m'
readonly C_BOLD=$'\033[1m'

# --- Flags ---
ASSUME_YES=0
DO_UPDATE=0
DO_LIST=0

# --- Helpers ---
info()    { printf "${C_BLUE}[INFO]${C_RESET}  %s\n" "$*" | tee -a "$LOG_FILE"; }
ok()      { printf "${C_GREEN}[OK]${C_RESET}    %s\n" "$*" | tee -a "$LOG_FILE"; }
warn()    { printf "${C_YELLOW}[WARN]${C_RESET}  %s\n" "$*" | tee -a "$LOG_FILE"; }
err()     { printf "${C_RED}[ERR]${C_RESET}   %s\n" "$*" | tee -a "$LOG_FILE" >&2; }
section() { printf "\n${C_BOLD}${C_BLUE}=== %s ===${C_RESET}\n" "$*" | tee -a "$LOG_FILE"; }

confirm() {
    local prompt="${1:-Proceed?}"
    [[ $ASSUME_YES -eq 1 ]] && return 0
    read -rp "$prompt [Y/n] " ans
    [[ -z "$ans" || "$ans" =~ ^[YyJj]$ ]]
}

usage() {
    cat <<EOF
Pentest Tools Setup

Usage: $0 [OPTIONS]

Options:
  -y, --yes      Non-interactive
  --update       Git pull all existing tool repos
  --list         Show all defined tools (no install)
  -h, --help     Show this help

Tools install to: $TOOLS_DIR
Aliases write to:
  bash/zsh: $ALIAS_FILE_BASH
  fish:     $ALIAS_FILE_FISH

To add tools: edit the TOOLS array near the top of this script.
EOF
}

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)  ASSUME_YES=1 ;;
        --update)  DO_UPDATE=1 ;;
        --list)    DO_LIST=1 ;;
        -h|--help) usage; exit 0 ;;
        *) err "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

# =============================================================================
# Functions
# =============================================================================

list_tools() {
    section "Configured tools"
    printf "  %-20s %-12s %s\n" "FOLDER" "ALIAS" "COMMAND"
    printf "  %-20s %-12s %s\n" "------" "-----" "-------"
    for entry in "${TOOLS[@]}"; do
        IFS='|' read -r dir url alias cmd <<< "$entry"
        printf "  %-20s %-12s %s\n" "$dir" "$alias" "$cmd"
    done
    echo
    info "Tools dir: $TOOLS_DIR"
}

install_dependencies() {
    section "Installing dependencies"
    local pkgs=(
        git python python-pip
        bash-completion
        openssh
        nmap
        smbclient impacket-suite
        proxychains-ng
    )

    info "Packages: ${pkgs[*]}"
    if ! confirm "Install/update these packages?"; then
        warn "Skipped dependency install"
        return 0
    fi

    sudo pacman -S --needed --noconfirm "${pkgs[@]}" 2>&1 | tail -5 \
        || warn "Some packages failed (may already be installed)"

    info "Installing common Python libraries..."
    pip install --user --upgrade --break-system-packages \
        requests \
        beautifulsoup4 \
        rich \
        colorama \
        pyfiglet 2>&1 | tail -3 || warn "Some pip libs failed"

    ok "Dependencies installed"
}

clone_or_update() {
    local dir="$1" url="$2"
    local target="$TOOLS_DIR/$dir"

    if [[ -d "$target/.git" ]]; then
        if [[ $DO_UPDATE -eq 1 ]]; then
            info "Updating: $dir"
            (cd "$target" && git pull --quiet) || warn "  pull failed for $dir"
        else
            info "Already cloned: $dir (use --update to refresh)"
        fi
    elif [[ -d "$target" ]]; then
        warn "$target exists but is not a git repo, skipping clone"
    else
        info "Cloning: $url"
        info "  → $dir/"
        git clone --quiet "$url" "$target" || {
            err "  clone failed for $url"
            return 1
        }
    fi

    # If repo has requirements.txt, install (best effort)
    if [[ -f "$target/requirements.txt" ]]; then
        info "  installing requirements.txt for $dir..."
        pip install --user --break-system-packages -r "$target/requirements.txt" 2>&1 | tail -2 \
            || warn "  pip install failed for $dir"
    fi

    # Make scripts executable
    find "$target" -maxdepth 2 -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} \; 2>/dev/null
}

install_tools() {
    section "Installing tools"

    # Create the tools dir if missing
    if [[ ! -d "$TOOLS_DIR" ]]; then
        info "Creating $TOOLS_DIR"
        mkdir -p "$TOOLS_DIR"
    else
        info "Tools dir already exists: $TOOLS_DIR"
    fi

    # Dedupe URLs (e.g. ligolo appears twice for two aliases)
    local -A seen
    for entry in "${TOOLS[@]}"; do
        IFS='|' read -r dir url _ _ <<< "$entry"
        local key="$dir|$url"
        if [[ -z "${seen[$key]:-}" ]]; then
            seen[$key]=1
            clone_or_update "$dir" "$url"
        fi
    done
    ok "All tools cloned/updated"
}

generate_aliases() {
    section "Generating aliases"

    # bash/zsh format
    {
        echo "# Pentest tool aliases — auto-generated by tools-setup.sh"
        echo "# Edit tools-setup.sh and re-run; do not edit this file directly."
        echo "# Generated: $(date)"
        echo
        for entry in "${TOOLS[@]}"; do
            IFS='|' read -r dir url alias cmd <<< "$entry"
            local full_dir="$TOOLS_DIR/$dir"
            local resolved_cmd="${cmd//\{DIR\}/$full_dir}"
            printf "alias %s='%s'\n" "$alias" "$resolved_cmd"
        done
    } > "$ALIAS_FILE_BASH"
    ok "Bash/Zsh aliases: $ALIAS_FILE_BASH"

    # fish format
    mkdir -p "$(dirname "$ALIAS_FILE_FISH")"
    {
        echo "# Pentest tool aliases — auto-generated by tools-setup.sh"
        echo "# Edit tools-setup.sh and re-run; do not edit this file directly."
        echo "# Generated: $(date)"
        echo
        for entry in "${TOOLS[@]}"; do
            IFS='|' read -r dir url alias cmd <<< "$entry"
            local full_dir="$TOOLS_DIR/$dir"
            local resolved_cmd="${cmd//\{DIR\}/$full_dir}"
            printf "alias %s '%s'\n" "$alias" "$resolved_cmd"
        done
    } > "$ALIAS_FILE_FISH"
    ok "Fish aliases: $ALIAS_FILE_FISH"
}

wire_up_shells() {
    section "Wiring aliases into shells"

    if [[ -f "$HOME/.bashrc" ]] && ! grep -q "tools-aliases.sh" "$HOME/.bashrc"; then
        echo "" >> "$HOME/.bashrc"
        echo "# Pentest tool aliases" >> "$HOME/.bashrc"
        echo "[ -f $ALIAS_FILE_BASH ] && source $ALIAS_FILE_BASH" >> "$HOME/.bashrc"
        ok "Added source line to ~/.bashrc"
    else
        info "bash already wired (or no ~/.bashrc)"
    fi

    if [[ -f "$HOME/.zshrc" ]] && ! grep -q "tools-aliases.sh" "$HOME/.zshrc"; then
        echo "" >> "$HOME/.zshrc"
        echo "# Pentest tool aliases" >> "$HOME/.zshrc"
        echo "[ -f $ALIAS_FILE_BASH ] && source $ALIAS_FILE_BASH" >> "$HOME/.zshrc"
        ok "Added source line to ~/.zshrc"
    else
        info "zsh already wired (or no ~/.zshrc)"
    fi

    info "fish auto-loads from conf.d/, no wiring needed"
}

show_summary() {
    section "Summary"
    echo
    echo "  Tools dir:        $TOOLS_DIR"
    echo
    echo "  ${C_BOLD}Aliases:${C_RESET}"
    for entry in "${TOOLS[@]}"; do
        IFS='|' read -r _ _ alias _ <<< "$entry"
        printf "    ${C_GREEN}%s${C_RESET}\n" "$alias"
    done
    echo
    echo "  ${C_YELLOW}Activate now:${C_RESET}"
    echo "    fish:     exec fish"
    echo "    bash/zsh: source ~/.bashrc"
    echo
    echo "  ${C_YELLOW}Add a new tool:${C_RESET}"
    echo "    1. Edit this script, append to TOOLS array"
    echo "    2. ./tools-setup.sh --yes"
    echo
    echo "  Log: $LOG_FILE"
    echo
}

# =============================================================================
# Main
# =============================================================================

main() {
    if [[ $DO_LIST -eq 1 ]]; then
        list_tools
        exit 0
    fi

    echo "=========================================="
    echo " Pentest Tools Setup"
    echo " Target: $TOOLS_DIR"
    echo "=========================================="

    if [[ $DO_UPDATE -eq 1 ]]; then
        info "Update mode — pulling latest from all repos"
        install_tools
        generate_aliases
        ok "Update complete"
        exit 0
    fi

    install_dependencies
    install_tools
    generate_aliases
    wire_up_shells
    show_summary
}

main "$@"

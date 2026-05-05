#!/usr/bin/env bash
# =============================================================================
# Pentest Tools Installer
# =============================================================================
#
# Manages a personal pentest toolkit. Each tool is a github repo cloned into
# a configurable tools directory, with shell aliases auto-generated for
# bash, zsh, and fish.
#
# Tool definitions live in tools.json (next to this script), making them
# easy to edit, version, and share separately from the installer logic.
#
# USAGE:
#   tools-setup.sh                # interactive TUI menu (default)
#   tools-setup.sh install        # install/refresh everything from tools.json
#   tools-setup.sh update         # git-pull all existing repos
#   tools-setup.sh list           # show all defined tools
#   tools-setup.sh status         # show install state of each tool
#   tools-setup.sh add            # interactively add a new tool
#   tools-setup.sh remove         # interactively remove a tool
#   tools-setup.sh edit           # open tools.json in $EDITOR
#
# =============================================================================

set -uo pipefail

# =============================================================================
# Paths & defaults
# =============================================================================

# Self-locate (works even when symlinked)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
readonly SCRIPT_DIR

# Tool definitions live next to the script
readonly TOOLS_JSON="${TOOLS_JSON:-$SCRIPT_DIR/tools.json}"

# User-configurable: where tools get cloned. Override with TOOLS_DIR env var.
TOOLS_DIR="${TOOLS_DIR:-$HOME/Desktop/tools}"

# Generated alias files (per shell)
readonly ALIAS_FILE_BASH="$HOME/.config/tools-aliases.sh"
readonly ALIAS_FILE_FISH="$HOME/.config/fish/conf.d/tools-aliases.fish"

# Logs go to $XDG_CACHE_HOME if set, else $HOME/.cache
readonly LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/tools-installer"
LOG_FILE="$LOG_DIR/tools-setup-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$LOG_DIR"

# =============================================================================
# Output helpers
# =============================================================================

readonly C_RESET=$'\033[0m'
readonly C_RED=$'\033[31m'
readonly C_GREEN=$'\033[32m'
readonly C_YELLOW=$'\033[33m'
readonly C_BLUE=$'\033[34m'
readonly C_BOLD=$'\033[1m'
readonly C_DIM=$'\033[2m'

info()    { printf "${C_BLUE}[INFO]${C_RESET}  %s\n" "$*" | tee -a "$LOG_FILE" >&2; }
ok()      { printf "${C_GREEN}[OK]${C_RESET}    %s\n" "$*" | tee -a "$LOG_FILE" >&2; }
warn()    { printf "${C_YELLOW}[WARN]${C_RESET}  %s\n" "$*" | tee -a "$LOG_FILE" >&2; }
err()     { printf "${C_RED}[ERR]${C_RESET}   %s\n" "$*" | tee -a "$LOG_FILE" >&2; }
section() { printf "\n${C_BOLD}${C_BLUE}=== %s ===${C_RESET}\n" "$*" | tee -a "$LOG_FILE" >&2; }

confirm() {
    local prompt="${1:-Proceed?}"
    [[ "${ASSUME_YES:-0}" -eq 1 ]] && return 0
    read -rp "$prompt [Y/n] " ans
    [[ -z "$ans" || "$ans" =~ ^[YyJj]$ ]]
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        err "Required command not found: $cmd"
        case "$cmd" in
            jq)  info "Install with: sudo pacman -S jq" ;;
            git) info "Install with: sudo pacman -S git" ;;
        esac
        exit 1
    fi
}

# =============================================================================
# JSON helpers (jq-backed)
# =============================================================================

ensure_tools_json() {
    if [[ ! -f "$TOOLS_JSON" ]]; then
        info "tools.json not found, creating empty one at $TOOLS_JSON"
        cat > "$TOOLS_JSON" <<'EOF'
{
  "tools": []
}
EOF
    fi
}

validate_tools_json() {
    if ! jq -e '.tools | type == "array"' "$TOOLS_JSON" >/dev/null 2>&1; then
        err "tools.json is invalid (missing or non-array .tools)"
        return 1
    fi
    return 0
}

count_tools() {
    jq '.tools | length' "$TOOLS_JSON"
}

list_tools_tsv() {
    jq -r '.tools[] | [.dir, .url, .alias, .command] | @tsv' "$TOOLS_JSON"
}

# =============================================================================
# Subcommand: list
# =============================================================================

cmd_list() {
    ensure_tools_json
    validate_tools_json || exit 1

    section "Configured tools ($(count_tools))"
    if [[ "$(count_tools)" -eq 0 ]]; then
        warn "No tools defined yet. Run: $0 add"
        return 0
    fi

    printf "  ${C_BOLD}%-20s %-12s %s${C_RESET}\n" "FOLDER" "ALIAS" "COMMAND"
    printf "  %-20s %-12s %s\n" "------" "-----" "-------"
    while IFS=$'\t' read -r dir url alias cmd; do
        printf "  %-20s ${C_GREEN}%-12s${C_RESET} ${C_DIM}%s${C_RESET}\n" \
            "$dir" "$alias" "$cmd"
    done < <(list_tools_tsv)
    echo
    info "Tools dir:    $TOOLS_DIR"
    info "Definitions:  $TOOLS_JSON"
}

# =============================================================================
# Subcommand: status
# =============================================================================

cmd_status() {
    ensure_tools_json
    validate_tools_json || exit 1

    section "Install status"
    printf "  ${C_BOLD}%-20s %-12s %s${C_RESET}\n" "FOLDER" "ALIAS" "STATUS"
    printf "  %-20s %-12s %s\n" "------" "-----" "------"

    local installed=0 missing=0
    while IFS=$'\t' read -r dir url alias cmd; do
        local target="$TOOLS_DIR/$dir"
        local status
        if [[ -d "$target/.git" ]]; then
            status="${C_GREEN}OK installed${C_RESET}"
            ((installed++))
        elif [[ -d "$target" ]]; then
            status="${C_YELLOW}exists, not git${C_RESET}"
        else
            status="${C_RED}missing${C_RESET}"
            ((missing++))
        fi
        printf "  %-20s %-12s %b\n" "$dir" "$alias" "$status"
    done < <(list_tools_tsv)
    echo
    info "$installed installed, $missing missing"
}

# =============================================================================
# Subcommand: add
# =============================================================================

cmd_add() {
    ensure_tools_json
    validate_tools_json || exit 1
    require_cmd jq

    section "Add a new tool"

    echo "We need 4 things:"
    echo "  ${C_BOLD}dir${C_RESET}      - folder name under \$TOOLS_DIR (lowercase, no spaces)"
    echo "  ${C_BOLD}url${C_RESET}      - git clone URL"
    echo "  ${C_BOLD}alias${C_RESET}    - shell shortcut (must be a valid identifier)"
    echo "  ${C_BOLD}command${C_RESET}  - what the alias runs. Use {DIR} for the tool's path."
    echo
    echo "Example:"
    echo "  dir:     linpeas"
    echo "  url:     https://github.com/peass-ng/PEASS-ng"
    echo "  alias:   peas"
    echo "  command: bash {DIR}/linPEAS/linpeas.sh"
    echo

    local dir url alias cmd
    read -rp "Folder name: " dir
    [[ -z "$dir" ]] && { err "Folder name required"; return 1; }
    if [[ ! "$dir" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        err "Folder name must be lowercase letters/digits/dash/underscore only"
        return 1
    fi

    if jq -e --arg d "$dir" '.tools[] | select(.dir == $d)' "$TOOLS_JSON" >/dev/null; then
        warn "Folder '$dir' already exists in tools.json (multiple aliases per repo is OK)"
        confirm "Continue?" || return 1
    fi

    read -rp "Git URL: " url
    [[ ! "$url" =~ ^https?://|^git@ ]] && { err "URL must start with http(s):// or git@"; return 1; }

    read -rp "Alias name: " alias
    [[ -z "$alias" ]] && { err "Alias required"; return 1; }
    if [[ ! "$alias" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
        err "Alias must be a valid shell identifier"
        return 1
    fi

    if jq -e --arg a "$alias" '.tools[] | select(.alias == $a)' "$TOOLS_JSON" >/dev/null; then
        err "Alias '$alias' already exists in tools.json (must be unique)"
        return 1
    fi

    read -rp "Command (use {DIR} for path): " cmd
    [[ -z "$cmd" ]] && { err "Command required"; return 1; }

    echo
    info "About to add:"
    echo "  dir:     $dir"
    echo "  url:     $url"
    echo "  alias:   $alias"
    echo "  command: $cmd"
    echo
    confirm "Add this tool?" || { warn "Cancelled"; return 0; }

    local tmp
    tmp=$(mktemp)
    jq --arg dir "$dir" --arg url "$url" --arg alias "$alias" --arg cmd "$cmd" \
        '.tools += [{"dir": $dir, "url": $url, "alias": $alias, "command": $cmd}]' \
        "$TOOLS_JSON" > "$tmp" && mv "$tmp" "$TOOLS_JSON"

    ok "Added '$alias' to tools.json"

    if confirm "Install this tool now?"; then
        clone_or_update "$dir" "$url"
        generate_aliases
        ok "Done. Run 'exec fish' or 'source ~/.bashrc' to use the alias."
    else
        info "Run '$0 install' later to clone."
    fi
}

# =============================================================================
# Subcommand: remove
# =============================================================================

cmd_remove() {
    ensure_tools_json
    validate_tools_json || exit 1
    require_cmd jq

    section "Remove a tool"

    if [[ "$(count_tools)" -eq 0 ]]; then
        warn "No tools defined."
        return 0
    fi

    local -a aliases dirs
    while IFS=$'\t' read -r dir url alias cmd; do
        dirs+=("$dir")
        aliases+=("$alias")
    done < <(list_tools_tsv)

    echo "Available tools:"
    for i in "${!aliases[@]}"; do
        printf "  ${C_GREEN}%2d${C_RESET}) %-12s ${C_DIM}(%s)${C_RESET}\n" \
            "$((i+1))" "${aliases[$i]}" "${dirs[$i]}"
    done
    echo

    local choice
    read -rp "Number to remove (or 'q' to quit): " choice
    [[ "$choice" == "q" ]] && return 0
    [[ ! "$choice" =~ ^[0-9]+$ ]] && { err "Invalid number"; return 1; }
    if (( choice < 1 || choice > ${#aliases[@]} )); then
        err "Out of range"
        return 1
    fi

    local idx=$((choice - 1))
    local target_alias="${aliases[$idx]}"
    local target_dir="${dirs[$idx]}"

    info "Will remove from tools.json:"
    info "  alias: $target_alias"
    info "  dir:   $target_dir"
    confirm "Confirm?" || { warn "Cancelled"; return 0; }

    local tmp
    tmp=$(mktemp)
    jq --arg a "$target_alias" --arg d "$target_dir" \
       '.tools |= map(select(.alias != $a or .dir != $d))' \
       "$TOOLS_JSON" > "$tmp" && mv "$tmp" "$TOOLS_JSON"

    ok "Removed '$target_alias' from tools.json"

    local target="$TOOLS_DIR/$target_dir"
    if [[ -d "$target" ]]; then
        if ! jq -e --arg d "$target_dir" '.tools[] | select(.dir == $d)' "$TOOLS_JSON" >/dev/null; then
            if confirm "Also delete cloned folder $target?"; then
                rm -rf "$target"
                ok "Deleted $target"
            fi
        else
            info "Folder kept (still used by other aliases)"
        fi
    fi

    generate_aliases
    ok "Aliases regenerated"
}

# =============================================================================
# Subcommand: edit
# =============================================================================

cmd_edit() {
    ensure_tools_json
    "${EDITOR:-nano}" "$TOOLS_JSON"
    validate_tools_json || { err "Validation failed after edit"; exit 1; }
    ok "tools.json valid"
    if confirm "Re-install/update aliases now?"; then
        cmd_install
    fi
}

# =============================================================================
# Subcommand: install / update
# =============================================================================

install_dependencies() {
    section "Installing dependencies"

    local pm
    if command -v pacman >/dev/null; then
        pm=pacman
    elif command -v apt >/dev/null; then
        pm=apt
    elif command -v dnf >/dev/null; then
        pm=dnf
    else
        warn "No supported package manager found, skipping"
        return 0
    fi

    if [[ "$pm" == "pacman" ]]; then
        local pkgs=(git python python-pip jq nmap smbclient impacket-suite proxychains-ng openssh)
        info "pacman: ${pkgs[*]}"
        if confirm "Install/update these packages?"; then
            sudo pacman -S --needed --noconfirm "${pkgs[@]}" 2>&1 | tail -5 \
                || warn "Some packages failed (may already be installed)"
        fi
    else
        warn "Non-Arch system detected; install dependencies manually"
    fi

    if command -v pip >/dev/null; then
        info "Installing common Python libs (user)..."
        pip install --user --upgrade --break-system-packages \
            requests beautifulsoup4 rich colorama pyfiglet 2>&1 | tail -3 \
            || warn "Some pip libs failed"
    fi

    ok "Dependencies done"
}

clone_or_update() {
    local dir="$1" url="$2"
    local target="$TOOLS_DIR/$dir"

    if [[ -d "$target/.git" ]]; then
        if [[ "${DO_UPDATE:-0}" -eq 1 ]]; then
            info "Updating: $dir"
            (cd "$target" && git pull --quiet) || warn "  pull failed for $dir"
        else
            info "Already cloned: $dir (use 'update' subcommand to refresh)"
        fi
    elif [[ -d "$target" ]]; then
        warn "$target exists but is not a git repo, skipping"
    else
        info "Cloning: $url"
        info "  -> $dir/"
        git clone --quiet "$url" "$target" || { err "  clone failed"; return 1; }
    fi

    if [[ -f "$target/requirements.txt" ]]; then
        info "  pip install -r $dir/requirements.txt"
        pip install --user --break-system-packages -r "$target/requirements.txt" 2>&1 | tail -2 \
            || warn "  pip install had issues"
    fi

    find "$target" -maxdepth 2 -type f \( -name "*.sh" -o -name "*.py" \) \
        -exec chmod +x {} \; 2>/dev/null
}

generate_aliases() {
    section "Generating aliases"

    {
        echo "# Pentest tool aliases - auto-generated by tools-setup.sh"
        echo "# Edit tools.json and run 'tools-setup.sh install' to regenerate."
        echo "# Generated: $(date -Iseconds)"
        echo
        echo "# TOOLS_DIR can be overridden by the user; default is where the installer last cloned to."
        echo "export TOOLS_DIR=\"\${TOOLS_DIR:-$TOOLS_DIR}\""
        echo
        while IFS=$'\t' read -r dir url alias cmd; do
            local resolved="${cmd//\{DIR\}/\${TOOLS_DIR}/$dir}"
            printf "alias %s='%s'\n" "$alias" "$resolved"
        done < <(list_tools_tsv)
    } > "$ALIAS_FILE_BASH"
    ok "Bash/Zsh aliases: $ALIAS_FILE_BASH"

    mkdir -p "$(dirname "$ALIAS_FILE_FISH")"
    {
        echo "# Pentest tool aliases - auto-generated by tools-setup.sh"
        echo "# Edit tools.json and run 'tools-setup.sh install' to regenerate."
        echo "# Generated: $(date -Iseconds)"
        echo
        echo "set -gx TOOLS_DIR (set -q TOOLS_DIR; and echo \$TOOLS_DIR; or echo \"$TOOLS_DIR\")"
        echo
        while IFS=$'\t' read -r dir url alias cmd; do
            local resolved="${cmd//\{DIR\}/\$TOOLS_DIR/$dir}"
            printf "alias %s '%s'\n" "$alias" "$resolved"
        done < <(list_tools_tsv)
    } > "$ALIAS_FILE_FISH"
    ok "Fish aliases: $ALIAS_FILE_FISH"
}

wire_up_shells() {
    section "Wiring shells"

    local source_line="[ -f $ALIAS_FILE_BASH ] && source $ALIAS_FILE_BASH"

    if [[ -f "$HOME/.bashrc" ]] && ! grep -q "tools-aliases.sh" "$HOME/.bashrc"; then
        printf "\n# Pentest tool aliases\n%s\n" "$source_line" >> "$HOME/.bashrc"
        ok "~/.bashrc updated"
    else
        info "bash already wired (or no ~/.bashrc)"
    fi

    if [[ -f "$HOME/.zshrc" ]] && ! grep -q "tools-aliases.sh" "$HOME/.zshrc"; then
        printf "\n# Pentest tool aliases\n%s\n" "$source_line" >> "$HOME/.zshrc"
        ok "~/.zshrc updated"
    else
        info "zsh already wired (or no ~/.zshrc)"
    fi

    info "fish auto-loads from conf.d/, no wiring needed"
}

cmd_install() {
    ensure_tools_json
    validate_tools_json || exit 1
    require_cmd git
    require_cmd jq

    section "Install / refresh tools"

    if [[ ! -d "$TOOLS_DIR" ]]; then
        info "Creating $TOOLS_DIR"
        mkdir -p "$TOOLS_DIR"
    else
        info "Tools dir: $TOOLS_DIR"
    fi

    install_dependencies

    if [[ "$(count_tools)" -eq 0 ]]; then
        warn "tools.json is empty. Add tools first with: $0 add"
        return 0
    fi

    section "Cloning tools"
    local -A seen
    while IFS=$'\t' read -r dir url alias cmd; do
        local key="$dir|$url"
        if [[ -z "${seen[$key]:-}" ]]; then
            seen[$key]=1
            clone_or_update "$dir" "$url"
        fi
    done < <(list_tools_tsv)
    ok "All tools processed"

    generate_aliases
    wire_up_shells
    show_summary
}

cmd_update() {
    DO_UPDATE=1
    cmd_install
}

show_summary() {
    section "Summary"
    echo
    echo "  Tools dir:    $TOOLS_DIR"
    echo "  Definitions:  $TOOLS_JSON"
    echo
    echo "  ${C_BOLD}Aliases:${C_RESET}"
    while IFS=$'\t' read -r dir url alias cmd; do
        printf "    ${C_GREEN}%s${C_RESET}\n" "$alias"
    done < <(list_tools_tsv)
    echo
    echo "  ${C_YELLOW}Activate now:${C_RESET}"
    echo "    fish:     exec fish"
    echo "    bash/zsh: source ~/.bashrc"
    echo
    echo "  Log: $LOG_FILE"
    echo
}

# =============================================================================
# Subcommand: menu
# =============================================================================

cmd_menu() {
    while true; do
        echo
        printf "${C_BOLD}+----------------------------------------+${C_RESET}\n"
        printf "${C_BOLD}|       Pentest Tools Installer          |${C_RESET}\n"
        printf "${C_BOLD}+----------------------------------------+${C_RESET}\n"
        echo
        echo "  ${C_GREEN}1${C_RESET}) Install / refresh all tools"
        echo "  ${C_GREEN}2${C_RESET}) Update all (git pull)"
        echo "  ${C_GREEN}3${C_RESET}) List configured tools"
        echo "  ${C_GREEN}4${C_RESET}) Show install status"
        echo "  ${C_GREEN}5${C_RESET}) Add a new tool"
        echo "  ${C_GREEN}6${C_RESET}) Remove a tool"
        echo "  ${C_GREEN}7${C_RESET}) Edit tools.json directly"
        echo "  ${C_GREEN}q${C_RESET}) Quit"
        echo
        read -rp "Choice: " choice
        case "$choice" in
            1) cmd_install ;;
            2) cmd_update ;;
            3) cmd_list ;;
            4) cmd_status ;;
            5) cmd_add ;;
            6) cmd_remove ;;
            7) cmd_edit ;;
            q|Q) ok "Bye"; break ;;
            *) warn "Unknown choice: $choice" ;;
        esac
    done
}

# =============================================================================
# Help
# =============================================================================

usage() {
    cat <<EOF
Pentest Tools Installer

USAGE:
  $0 [SUBCOMMAND] [OPTIONS]

SUBCOMMANDS:
  install        Install/refresh tools from tools.json
  update         Git pull all existing repos
  list           Show all defined tools
  status         Show install state per tool
  add            Interactively add a new tool
  remove         Interactively remove a tool
  edit           Open tools.json in \$EDITOR
  menu           Interactive TUI menu (default if no args)
  help           Show this help

GLOBAL OPTIONS:
  -y, --yes      Non-interactive (accept defaults)

ENVIRONMENT VARIABLES:
  TOOLS_DIR      Where tools get cloned (default: \$HOME/Desktop/tools)
  TOOLS_JSON     Path to tools definition (default: alongside this script)
  EDITOR         Editor for 'edit' subcommand (default: nano)

EXAMPLES:
  $0                          # opens interactive menu
  $0 install -y               # install everything, no prompts
  $0 add                      # guided: add a new tool
  TOOLS_DIR=/opt/tools $0 install   # install to custom location

FILES:
  tools.json                                      Tool definitions
  ~/.config/tools-aliases.sh                      Generated bash/zsh aliases
  ~/.config/fish/conf.d/tools-aliases.fish        Generated fish aliases
EOF
}

# =============================================================================
# Argument parsing & dispatch
# =============================================================================

ASSUME_YES=0
DO_UPDATE=0
SUBCOMMAND="menu"

ARGS=()
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help|help) usage; exit 0 ;;
        *) ARGS+=("$arg") ;;
    esac
done

if [[ ${#ARGS[@]} -gt 0 ]]; then
    SUBCOMMAND="${ARGS[0]}"
fi

case "$SUBCOMMAND" in
    list|status|add|remove|edit|install|update|menu)
        require_cmd jq
        ;;
esac

case "$SUBCOMMAND" in
    install) cmd_install ;;
    update)  cmd_update ;;
    list)    cmd_list ;;
    status)  cmd_status ;;
    add)     cmd_add ;;
    remove)  cmd_remove ;;
    edit)    cmd_edit ;;
    menu)    cmd_menu ;;
    *)       err "Unknown subcommand: $SUBCOMMAND"; usage; exit 1 ;;
esac

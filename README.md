# Pentest Tools Installer

A simple, portable installer for managing a personal collection of pentest tools cloned from GitHub. Generates shell aliases for **bash, zsh, and fish** so every tool is one short command away.

Tools live in their own folder, definitions live in `tools.json`, and aliases are auto-generated. Add a tool, the alias works immediately. Move to a new machine, run one command, everything is back.

## Quick start

```bash
# 1. Clone this repo into your tools folder
mkdir -p ~/Desktop/tools
cd ~/Desktop/tools
git clone https://github.com/<your-username>/tools-installer
cd tools-installer

# 2. Run it (interactive menu by default)
./tools-setup.sh

# 3. Or skip the menu and install everything at once
./tools-setup.sh install -y

# 4. Activate aliases in your current shell
exec fish              # or: source ~/.bashrc
```

## Subcommands

| Command | What it does |
|---|---|
| `tools-setup.sh` | Opens an interactive menu (default) |
| `tools-setup.sh install` | Installs/refreshes everything in `tools.json` |
| `tools-setup.sh update` | `git pull` on every cloned repo |
| `tools-setup.sh list` | Shows all tools defined in `tools.json` |
| `tools-setup.sh status` | Shows which tools are installed vs missing |
| `tools-setup.sh add` | Guided wizard to add a new tool |
| `tools-setup.sh remove` | Pick a tool from a list to remove |
| `tools-setup.sh edit` | Opens `tools.json` in `$EDITOR` |
| `tools-setup.sh help` | Show full help |

Add `-y` to any command for non-interactive mode.

## Adding a tool

The easiest way:

```bash
./tools-setup.sh add
```

The wizard asks four questions:

1. **Folder name** — lowercase, no spaces. Used as the directory name and for `{DIR}` substitution.
2. **Git URL** — the clone URL.
3. **Alias** — what you'll type in the shell. Must be unique across all tools.
4. **Command** — what the alias runs. Use `{DIR}` to refer to the tool's folder.

Example wizard session:

```
Folder name: linpeas
Git URL: https://github.com/peass-ng/PEASS-ng
Alias name: peas
Command (use {DIR} for path): bash {DIR}/linPEAS/linpeas.sh

About to add:
  dir:     linpeas
  url:     https://github.com/peass-ng/PEASS-ng
  alias:   peas
  command: bash {DIR}/linPEAS/linpeas.sh

Add this tool? [Y/n] y
[OK]    Added 'peas' to tools.json
Install this tool now? [Y/n] y
[INFO]  Cloning: https://github.com/peass-ng/PEASS-ng
[OK]    Done. Run 'exec fish' or 'source ~/.bashrc' to use the alias.
```

Now `peas` runs the linpeas script. From any directory.

## Removing a tool

```bash
./tools-setup.sh remove
```

Picks from a numbered list. Optionally also deletes the cloned folder. Won't delete the folder if other aliases still reference it (some tools use multiple aliases, like `ligoloup` and `ligolofix` for the same Ligolo repo).

## Environment variables

The installer is fully portable across users and machines. No hardcoded paths.

| Variable | Default | What it controls |
|---|---|---|
| `TOOLS_DIR` | `$HOME/Desktop/tools` | Where tools get cloned |
| `TOOLS_JSON` | `<script-dir>/tools.json` | Tool definitions file |
| `EDITOR` | `nano` | Editor for the `edit` subcommand |

Examples:

```bash
# Install to a different location
TOOLS_DIR=/opt/pentest-tools ./tools-setup.sh install

# Use a different definitions file (separate sets of tools per role)
TOOLS_JSON=~/.config/work-tools.json ./tools-setup.sh install
```

The generated aliases also respect `TOOLS_DIR` at runtime — change it in your shell rc and aliases follow.

## File layout

After install, your tools folder looks like:

```
~/Desktop/tools/
├── tools-installer/        ← this repo
│   ├── tools-setup.sh
│   ├── tools.json
│   └── README.md
│
├── http-smb-server/        ← cloned tool
├── netcat-scanner/
├── cve-suggester/
├── nxc-prey/
├── nhas-ssh/
├── ligolo/
├── binary-check/
└── snmp-enum/
```

Generated alias files:

```
~/.config/tools-aliases.sh                  # for bash/zsh
~/.config/fish/conf.d/tools-aliases.fish    # for fish
```

These get sourced automatically by your shell.

## Pre-bundled tools

Out of the box `tools.json` includes [@1337codes](https://github.com/1337codes)' OSCP toolkit:

| Alias | Tool | Purpose |
|---|---|---|
| `tools` | [OSCP-HTTP-SMB-File-Transfer-Server](https://github.com/1337codes/OSCP-HTTP-SMB-File-Transfer-Server) | HTTP/SMB transfer server |
| `ncscanner` | [OSCP-Netcat-scanner](https://github.com/1337codes/OSCP-Netcat-scanner) | Netcat-based port scanner |
| `cve` | [OSCP-CVE-exploit-suggester](https://github.com/1337codes/OSCP-CVE-exploit-suggester) | CVE exploit lookup |
| `nxcspray` | [OSCP-NXC-PREY](https://github.com/1337codes/OSCP-NXC-PREY) | NetExec password spraying |
| `nhasup` | [OSCP-nhas-ssh-server](https://github.com/1337codes/OSCP-nhas-ssh-server) | NHAS reverse SSH server |
| `ligoloup` | [OSCP-Ligolo](https://github.com/1337codes/OSCP-Ligolo) | Ligolo tunnel setup |
| `ligolofix` | [OSCP-Ligolo](https://github.com/1337codes/OSCP-Ligolo) | Ligolo connectivity fix |
| `binary` | [OSCP-Binary-Check](https://github.com/1337codes/OSCP-Binary-Check) | Binary security analysis |
| `snmpenum` | [OSCP-SNMP-enumeration](https://github.com/1337codes/OSCP-SNMP-enumeration) | SNMP enumeration |

Don't want some? `./tools-setup.sh remove`. Want different ones? Use `add`, or edit `tools.json` directly.

## Updating

To pull the latest version of every tool:

```bash
./tools-setup.sh update
```

The installer itself updates separately:

```bash
cd ~/Desktop/tools/tools-installer
git pull
```

## How `tools.json` looks

```json
{
  "tools": [
    {
      "dir": "linpeas",
      "url": "https://github.com/peass-ng/PEASS-ng",
      "alias": "peas",
      "command": "bash {DIR}/linPEAS/linpeas.sh"
    }
  ]
}
```

You can edit it directly with `./tools-setup.sh edit` (validates JSON before saving). Multiple aliases per repo are allowed (same `dir`, different `alias`).

## Requirements

- **Arch-based Linux** (CachyOS, Arch, Manjaro, EndeavourOS, BlackArch) — uses `pacman` for system deps
- **Bash 4+** to run the installer
- **`jq`** for JSON manipulation (auto-installed if missing)
- **Internet** for cloning

The script is best-effort on other distros — it'll skip the `pacman` step and warn you to install dependencies manually.

## Idempotent

Safe to re-run any number of times. Already-cloned tools are skipped (use `update` to refresh). Already-wired shells aren't wired again. Aliases are regenerated every install so edits to `tools.json` always reflect.

## Logs

Each run logs to:

```
~/.cache/tools-installer/tools-setup-<timestamp>.log
```

Useful when an install fails halfway and you want to see what happened.

## Troubleshooting

**Alias not found after install**

You need to reload your shell. Open a new terminal or:

```bash
exec fish              # fish
source ~/.bashrc       # bash
source ~/.zshrc        # zsh
```

**`jq: command not found`**

```bash
sudo pacman -S jq
```

**A tool fails to run because of a missing Python module**

Most tools have a `requirements.txt` that the installer auto-pip-installs. If a tool has dependencies it doesn't list, install manually:

```bash
pip install --user --break-system-packages <module>
```

**Tool repo URL changed**

Run `./tools-setup.sh edit`, fix the URL, save. Then `./tools-setup.sh install` to re-clone.

## License

MIT — do whatever.

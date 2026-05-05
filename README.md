# Pentest Tools Installer

Personal pentest toolkit installer. Clones tools to `~/Desktop/tools/` and generates shell aliases for fast access. Works on bash, zsh, and fish.

## Usage

```bash
./tools-setup.sh              # interactive
./tools-setup.sh --yes        # non-interactive
./tools-setup.sh --update     # pull latest from all tool repos
./tools-setup.sh --list       # show defined tools without installing
```

After install: `exec fish` (or new terminal) to activate aliases.

## Adding a tool

Edit `tools-setup.sh`, add an entry to the `TOOLS` array:

```bash
"<dir>|<repo-url>|<alias>|<command>"
```

Example:

```bash
"linpeas|https://github.com/peass-ng/PEASS-ng|peas|bash {DIR}/linPEAS/linpeas.sh"
```

Then re-run: `./tools-setup.sh --yes`

`{DIR}` in the command is replaced with the tool's full path (`~/Desktop/tools/linpeas` in this example).

## Structure

```
~/Desktop/tools/
├── tools-installer/        ← this repo
│   ├── tools-setup.sh
│   └── README.md
├── http-smb-server/        ← cloned tool
├── netcat-scanner/
├── cve-suggester/
└── ...
```

## Aliases

| Alias | Tool | Purpose |
|---|---|---|
| `tools` | OSCP-HTTP-SMB-File-Transfer-Server | HTTP/SMB file transfer server |
| `ncscanner` | OSCP-Netcat-scanner | Netcat-based port scanner |
| `cve` | OSCP-CVE-exploit-suggester | CVE exploit lookup |
| `nxcspray` | OSCP-NXC-PREY | NetExec password spraying |
| `nhasup` | OSCP-nhas-ssh-server | NHAS reverse SSH server |
| `ligoloup` | OSCP-Ligolo | Ligolo tunnel setup |
| `ligolofix` | OSCP-Ligolo | Ligolo connectivity fix |
| `binary` | OSCP-Binary-Check | Binary security analysis |
| `snmpenum` | OSCP-SNMP-enumeration | SNMP enumeration |

## Requirements

- Arch-based Linux (CachyOS, Arch, Manjaro, EndeavourOS)
- bash to run the installer
- Internet for cloning

The script auto-installs system dependencies via `pacman` and Python libs via `pip`.

## Notes

- Idempotent — safe to re-run
- Aliases regenerated on every run, so editing entries works
- Per-tool `requirements.txt` auto-installed via pip if present
- Sourced files: `~/.config/tools-aliases.sh` (bash/zsh), `~/.config/fish/conf.d/tools-aliases.fish` (fish)

## License

MIT

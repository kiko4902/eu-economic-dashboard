# Setup notes (local Windows machine)

How the development tools for this project were installed on this machine (Windows 10 Pro 22H2,
build 19045). Everything possible lives on **F:** because C: is short on space.

## Installed

| Tool | Version | Location | How |
|---|---|---|---|
| GNU make | 4.4.1 | `F:\Programs\make` (exe in `F:\Programs\make\bin`) | ezwinports zip from SourceForge, SHA256 verified, extracted manually |
| Python (via uv) | 3.12.14 | `F:\uv\python\cpython-3.12-windows-x86_64-none\` | `uv python install 3.12` |
| WSL | 3.0.1.0 (kernel 6.18.40.1-1) | `C:\Program Files\WSL` (cannot be relocated) | `wsl --install --no-distribution --web-download` (elevated) |
| Docker Desktop | 4.94.0 | `F:\Programs\Docker` | see command below (elevated) |
| Docker WSL data (disk image) | – | `F:\DockerData` | `--wsl-default-data-root` installer flag |

Docker Desktop install command (run elevated, TEMP redirected to F: so the installer does not
unpack onto C:):

```
set "TEMP=F:\Temp" && set "TMP=F:\Temp" && "F:\Downloads\installers\Docker Desktop Installer.exe" install ^
  --installation-dir=F:\Programs\Docker --wsl-default-data-root=F:\DockerData ^
  --accept-license --backend=wsl-2 --always-run-service --quiet
```

- `--always-run-service`: `com.docker.service` is set to Automatic, so Docker Desktop starts
  without a UAC prompt.
- No Linux distribution was installed in WSL; Docker Desktop brings its own.
- Installers are kept in `F:\Downloads\installers` and can be deleted.

## User environment variables

| Variable | Value |
|---|---|
| `UV_PYTHON_INSTALL_DIR` | `F:\uv\python` |
| `UV_CACHE_DIR` | `F:\uv\cache` |
| `PIP_CACHE_DIR` | `F:\pip\cache` |
| `Path` (appended) | `F:\Programs\make\bin` |

Open a new terminal (and restart VS Code / Claude Code) for these to take effect.

## What remains on C:

- `C:\Program Files\WSL` (~1.2 GB): WSL itself, fixed location.
- Windows optional features enabled by WSL (Virtual Machine Platform, WSL), part of Windows.
- Docker Desktop config and logs: `C:\ProgramData\DockerDesktop`
  (`install-settings.json` contains `"wslDefaultDataRoot": "F:\\DockerData"`),
  `%APPDATA%\Docker`, `%LOCALAPPDATA%\Docker`, `%USERPROFILE%\.docker`. These are small.
- `uv.exe` and the `python3.12.exe` shim in `C:\Users\Kristian\.local\bin` (a few MB).
- Old pip/uv caches in `%LOCALAPPDATA%` were deleted (~3.8 GB freed).

## After the restart

1. Start **Docker Desktop** (Start menu). Accept any first-run prompts and wait until the
   status shows "Engine running".
2. Verify the disk image location: Docker Desktop → Settings → Resources → Advanced →
   **Disk image location** must be `F:\DockerData`. `F:\DockerData` should now contain the
   `docker-desktop` WSL disk (`.vhdx`).
3. In a new terminal, check the tools:
   ```
   docker --version
   docker compose version
   make --version
   uv python find 3.12
   ```
4. Finish Phase 0 (in `F:\projekti\eu-economic-dashboard`, Git Bash):
   ```
   cp .env.example .env          # then set POSTGRES_PASSWORD
   rm -rf .venv
   make install                  # uses python3.12 (uv shim in ~/.local/bin)
   make up
   make db-shell                 # in psql: \dn  -> raw, warehouse, analytics
   ```
   Then mark Phase 0 done in `CLAUDE.md`.

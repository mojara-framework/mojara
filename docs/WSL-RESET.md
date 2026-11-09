# Safe fresh installation on Windows + WSL2

**Important:** Do not erase or unregister your WSL distro merely to reinstall Mojara. WSL may contain other projects, unpushed source code, databases and credentials that are not in this GitHub repository.

## First: preserve your work

1. Check all projects, especially `~/projects/Mojara`, and push any uncommitted changes or first-party extension sources to a backed-up repository. The published v1.2.5 SDK does not yet include every original transaction-pool extension source file.
2. Make logical database dumps of any local MySQL/PostgreSQL databases that matter.
3. If you intend a **full Ubuntu reset**, create and verify a complete WSL distribution export from Windows PowerShell:

```powershell
wsl --list --verbose
$distro = 'Ubuntu-24.04'  # Replace if your distro has another name.
$backup = Join-Path $env:USERPROFILE 'Downloads\Ubuntu-before-Mojara-reset.tar'
wsl --terminate $distro
wsl --export $distro $backup
Get-Item $backup | Select-Object FullName, Length
```

Check that the archive is non-empty and stored outside the distro. Have enough disk space and test the restore plan. **Do not run `wsl --unregister` before confirming backups**: unregistering irreversibly deletes that Linux distribution and all its internal files.

## Prefer a clean Mojara-only reinstall

You can reset Mojara **without deleting Ubuntu, other projects, or Pixi**.

Inside the Ubuntu WSL terminal:

```bash
pixi global list
pixi global uninstall mojara
pixi global install "mojara==1.2.5" \
  -c https://mojara.kasua.ng/conda/ \
  -c https://conda.modular.com/max/ \
  -c conda-forge
hash -r
mojara version
mojara doctor
```

Smoke test project creation in a temporary directory:

```bash
cd ~
mojara new mojara-clean-smoke
cd mojara-clean-smoke
mojara build
```

Do not run `pixi init` inside a Mojara project. The globally installed native CLI is designed to create an application anywhere.

If you remove Pixi itself, install it again following [the official Pixi instructions](https://pixi.sh/) before installing Mojara. Do not indiscriminately delete `~/.pixi` if other projects depend on its environments.

## When is it safe to wipe the entire WSL distro?

Only when you have verified (a) WSL export, (b) local source and extension backups, (c) database backups, and (d) a working restoration plan. The full distro reset is a separate, explicit destructive operation and is **not part of the standard Mojara installation procedure**.

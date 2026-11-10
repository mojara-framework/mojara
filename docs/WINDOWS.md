# Windows support

## Windows today: use WSL2

Mojara 1.2.9 supports Linux x86-64 and ARM64. On Windows 11, install WSL2 with Ubuntu and install Mojara **inside Ubuntu**. The Mojo compiler and the application run in Linux, not as native Windows executables.

From PowerShell you can invoke the installed Linux CLI:

```powershell
wsl.exe --distribution Ubuntu-24.04 -- mojara version
wsl.exe --distribution Ubuntu-24.04 -- mojara doctor
```

You can also use the optional repository [PowerShell launcher](../scripts/windows/mojara.ps1) to forward Mojara commands to Ubuntu:

```powershell
.\scripts\windows\mojara.ps1 version
.\scripts\windows\mojara.ps1 doctor
```

It expects the distribution name `Ubuntu-24.04` by default; set `$env:MOJARA_WSL_DISTRO` to the name from `wsl --list --verbose` if yours differs.

The PowerShell CI workflow checks syntax only: it does **not** claim to have tested WSL2 execution on GitHub's Windows runner. For application development, keep project files in the WSL2 Linux home filesystem for best performance.

## Native Windows roadmap

Official Mojo system requirements as of November 2026 say Windows is available through WSL2 rather than a native Windows toolchain. On August 18, 2026 Modular announced collaboration with Microsoft's Windows team to bring Mojo natively to Windows. The compiler is now open source.

- [Mojo system requirements](https://mojolang.org/docs/requirements/)
- [Modular's Windows announcement](https://www.modular.com/blog/modcon-announcements)
- [Mojo compiler open-source announcement](https://www.modular.com/blog/mojo-open-source)

A **true** native `mojara.exe` also needs a Windows-compatible Mojo compiler/runtime, native C and FFI ABIs, networking and I/O, dynamic DLL loading, TLS, filesystem and process handling, plus a Windows installer and full end-to-end application tests.

The WSL2 wrapper is **not** native Windows support. Native Windows is not yet released.

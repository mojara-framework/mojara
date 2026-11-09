# Windows support

## What works today

Mojara 1.2.5 is a native Linux x86-64 framework. You can develop on Windows using **WSL2 + Ubuntu**. The compiler and application run inside WSL2, not as Windows-native processes. From PowerShell, invoke the Linux CLI with `wsl.exe`:

```powershell
wsl.exe --distribution Ubuntu-24.04 -- mojara version
wsl.exe --distribution Ubuntu-24.04 -- mojara doctor
```

If your WSL distro is named differently, replace `Ubuntu-24.04` with the name shown by `wsl --list --verbose`. You must first have a working Mojara global install **inside** that distribution.

## Native Windows: not available yet

Official Mojo system requirements say that Windows is supported through WSL, not natively. On **August 18, 2026**, Modular announced collaboration with the Microsoft Windows team to bring native Windows support to Mojo.

Sources:
- [Mojo system requirements](https://mojolang.org/docs/requirements/)
- [Modular's August 2026 Windows announcement](https://www.modular.com/blog/modcon-announcements)
- [Open-source Mojo compiler announcement](https://www.modular.com/blog/mojo-open-source)

A real native `mojara.exe` requires a Windows-compatible Mojo compiler/runtime, matching C/FFI ABIs, Windows sockets and event handling, TLS, filesystem, native dynamic libraries, and installation/CI verification. Cross-compiling a Linux executable or wrapping WSL2 in PowerShell does **not** make it Windows-native.

**Do not ship an `.exe` advertised as native until all requirements and real Windows integration tests pass.**

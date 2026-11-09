# Cross-platform build and test status

Mojara is published for Linux x86-64. Its first-party source is being prepared for other platforms. The three targets require **different degrees of testing**.

## Automated GitHub Actions checks

| Workflow | Target | Trigger | Test scope |
| --- | --- | --- | --- |
| [Mojara Linux portability CI](../.github/workflows/mojara-cross-platform.yml) | Linux x86-64 + Linux ARM64 | Push, PR, manual | Native Mojo CLI build and starter project generation |
| [Native bridge regressions](../.github/workflows/native-bridge-regressions.yml) | Linux x86-64 + Linux ARM64 | Push, PR, manual | File serving, uploads, telemetry C API tests |
| [macOS Apple Silicon validation](../.github/workflows/mojara-macos-validation.yml) | macOS 15 Apple Silicon | **Manual** | Native CLI and starter project generation; experimental |

macOS validation is manual while GitHub-hosted macOS runners are frequently queued. You can run it from **Actions → macOS Apple Silicon validation (experimental) → Run workflow**. The Linux jobs are intentionally independent so a queued Mac runner does not falsely mark the Linux checks as failed.

## Actual platform support

| Target | CLI | Native regression tests | Full app | Production package |
| --- | --- | --- | --- | --- |
| Linux x86-64 | Verified | Verified | Verified for 1.2.5 on a local server | **Released (1.2.5)** |
| Linux ARM64 | Verified | Verified | Not verified | Not released |
| macOS Apple Silicon | Runner-dependent | Not verified | Not verified | Not released |
| Windows through WSL2 x86-64 | Existing Linux setup | Via Linux | Via Linux | Supported via Linux package |
| Native Windows | No native Mojo toolchain yet | Not verified | Not verified | Not released |

**CLI success is not a complete framework port.** Before adding a platform to the supported list, follow [the full release checklist](RELEASE-CHECKLIST.md).

## Native Mojo Windows

Modular announced in August 2026 that it is working with Microsoft's Windows team on native Windows support. Official system requirements still list Windows via WSL2. Follow [Windows notes](WINDOWS.md) for current details.

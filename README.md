# dev-tools

Human-focused shell helpers for a fork-based GitHub pull-request workflow.

This first public slice provides a small installation contract and an
interactive `pr-help` command. Git and pull-request operations will arrive in
separate, reviewable changes after this foundation has been tried by hand.

## Requirements

- Bash
- Standard Linux command-line tools (`awk`, `find`, `grep`, and `install`)

## Install

```bash
./install.sh
source ~/.bashrc
pr-help
```

The installer copies the helper to `~/.bashrc.d/dev-tools-git.sh`, adds a
marked `.bashrc.d` loader to `~/.bashrc` when needed, and prints the installed
command reference. Running the installer again is safe and does not duplicate
the loader.

## Uninstall

```bash
./uninstall.sh
source ~/.bashrc
```

The uninstaller removes only the dev-tools helper. If other shell extensions
remain in `~/.bashrc.d`, their directory and loader are preserved. If the
directory becomes empty, the installer-owned loader and directory are removed.

## Test

```bash
shellcheck bashrc.d/git.sh install.sh uninstall.sh test/install_help_test.sh
bash test/install_help_test.sh
```

The test uses temporary home directories and does not change the caller's
shell configuration.

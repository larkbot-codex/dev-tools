# dev-tools

Human-focused shell helpers for a fork-based GitHub pull-request workflow.

The public command set is growing through small, reviewable slices. The current
surface installs the helpers, creates a correctly configured fork checkout, and
keeps the fork's default branch synchronized with its canonical upstream.

## Requirements

- Bash
- Git
- [GitHub CLI](https://cli.github.com/) authenticated to the target host
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

## Clone a fork

```bash
fork-clone OWNER/REPOSITORY
fork-clone github.example.com/OWNER/REPOSITORY
fork-clone OWNER/REPOSITORY DIRECTORY
```

`fork-clone` asks GitHub CLI to create the authenticated user's fork, clones
that fork as `origin`, adds the canonical repository as `upstream`, fetches the
upstream refs, and reports the resulting topology. The optional host form uses
the same workflow with GitHub Enterprise.

## Synchronize a fork

From anywhere inside the cloned repository:

```bash
fork-sync
```

`fork-sync` refuses to run when tracked worktree or index changes are present.
It detects the upstream default branch, switches to it when necessary,
fast-forwards it from `upstream`, and pushes that exact branch to `origin`. It
never force-pushes.

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
shellcheck bashrc.d/git.sh install.sh uninstall.sh test/*.sh
bash test/install_help_test.sh
bash test/fork_sync_test.sh
```

The tests use temporary home directories and local bare Git repositories. They
do not change the caller's shell configuration, GitHub account, or remote
repositories.

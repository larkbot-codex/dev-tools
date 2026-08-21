# dev-tools

Human-focused shell helpers for a fork-based GitHub pull-request workflow.

The public command set is growing through small, reviewable slices. The current
surface installs the helpers, creates and synchronizes a fork checkout, commits
feature work, and opens a draft pull request against the canonical upstream.

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

## Commit feature work

Create or switch to a feature branch, make a focused change, and run:

```bash
pr-commit "Describe the change"
```

By default, `pr-commit` stages modifications and deletions to tracked files,
creates one commit with the supplied message, and pushes the feature branch to
`origin`. Use `pr-commit --all "Describe the change"` when untracked files are
intentionally part of the commit. The command refuses to commit on the upstream
default branch and never force-pushes.

## Open an upstream pull request

From a clean feature branch with at least one commit:

```bash
pr-create
```

`pr-create` pushes the current branch and opens a draft pull request from the
fork to the upstream default branch. Pass a branch name, such as
`pr-create release`, to choose a different upstream base. The command refuses
the default branch and refuses to continue when tracked changes are present.

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
shellcheck bashrc.d/*.sh install.sh uninstall.sh test/*.sh
bash test/install_help_test.sh
bash test/fork_sync_test.sh
bash test/pr_create_test.sh
bash test/jenkinsfile_test.sh
```

The tests use temporary home directories and local bare Git repositories. They
do not change the caller's shell configuration, GitHub account, or remote
repositories.

## Local Jenkins verification

The repository-owned Declarative `Jenkinsfile` runs on an agent labeled
`linux`. It performs a normal source checkout, runs ShellCheck across the shell
surface, and executes every `test/*.sh` script. New shell tests are picked up
without editing the pipeline.

The pipeline requires Bash, Git, and ShellCheck on the agent. It does not need
developer credentials, a host-home mount, a container-engine socket, or a
project-specific task runner.

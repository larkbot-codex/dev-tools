# Repository review policy

Standard: review-standard-v1
Approval profile: peer-agents
Human owner: @thelarklan

This repository adopts
[`review-standard-v1`](https://github.com/thelarklan/thelarklan/blob/review-standard-v1/standards/review-standard-v1.md)
from `thelarklan/thelarklan`. The standard is authoritative for common review
intent; this file records only the `dev-tools` implementation and exceptions.

## Approval and protected paths

Routine eligible agent changes follow the three-agent quorum and trusted-check
contract in [automatic-merge.md](automatic-merge.md). Until that gate is
deployed and verified, a maintainer merges deliberately.

The human owner must approve changes to ownership, review policy, CI and local
verification enforcement, scheduled review execution, or the automatic-merge
contract. The local `CODEOWNERS` file identifies those paths. Agent approvals
remain required where the organization ruleset applies; they do not substitute
for the human approval on a protected path.

## Current enforcement

The ruleset audit on 2026-08-28 found an active two-approval gate with stale
review dismissal, latest-push approval, resolved conversations, strict base
updates, squash-only merge, and the `bot-review-quorum` check. The repository is
user-owned, code-owner review is not yet required, and Jenkins is not a required
status check.

Consequently, the protected automatic path is ineligible and the new human-only
ownership rules are not fully enforced by GitHub yet. Before this adoption is
declared complete, the maintainer must enable code-owner review and add Jenkins
as a required status check after confirming the context is published reliably.
Organization ownership and the dedicated-team rule remain prerequisites for any
future automatic merge.

## Verification

Run the complete tree suite and verify the final pull-request diff from its
merge base to its exact head:

```bash
bash scripts/verify.sh
bash scripts/verify-pr-diff.sh upstream/main HEAD
git diff --check
```

Record the exact base, head, environment, expected results, and observed results
in the pull-request description. Repeat this evidence after every new commit or
history rewrite.

Manual verification follows [human-verification.md](human-verification.md) and
adds command-specific success, failure, recovery, portability, and destructive-
operation checks when those behaviors change.

## Merge and cleanup

Only squash merge is supported. GitHub may merge automatically only under the
deployed, verified, fail-closed contract; otherwise the maintainer merges
deliberately. Agents and repository helpers never merge directly or bypass the
gate.

After GitHub reports the pull request merged, run `pr-cleanup` from the verified
feature branch.

## Exceptions

The repository-specific `pr-cleanup` workflow is an extension of the shared
standard. It verifies the exact merged pull request, synchronizes the default
branch, and removes only the matching local and fork feature branches.

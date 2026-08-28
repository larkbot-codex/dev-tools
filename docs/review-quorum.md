# Bot review quorum

`pr-review-quorum` is a polling evaluator for the private
`thelarklan-bot-review-quorum` GitHub App. It never checks out pull-request code
and cannot push, approve, merge, or change repository settings. Its installation
permissions are limited to pull-request and metadata reads plus check-run reads
and writes.

For each open pull request in a repository owned by `thelarklan`, the evaluator
publishes the `bot-review-quorum` check on the exact pull-request head. For a
bot-authored pull request, both other bot IDs must have a latest decisive
`APPROVED` review for that same head. For an owner-authored pull request, any two
of the three bot IDs must approve the exact head. Approvals by the author,
`thelarklan`, or any account outside the cohort never count. Authors outside the
owner-plus-bot set, drafts, other base branches, stale approvals, dismissals,
change requests, a review-read error, and a head change during evaluation do not
receive a successful result.

## Trusted deployment configuration

Download a private key from the App's GitHub settings and store it outside every
repository. On the one trusted WSL account that runs the evaluator:

```bash
install -d -m 700 "$HOME/.config/dev-tools"
install -m 600 /mnt/c/Users/CHANGE_ME/Downloads/thelarklan-bot-review-quorum.pem \
  "$HOME/.config/dev-tools/thelarklan-bot-review-quorum.pem"
```

Create `~/.config/dev-tools/pr-review-quorum.env` with mode `600`:

```bash
QUORUM_APP_ID=4752010
QUORUM_INSTALLATION_ID=157289427
QUORUM_OWNER_ID=166922787
QUORUM_BOT_IDS=270192887,104110997,320627233
QUORUM_PRIVATE_KEY_FILE="$HOME/.config/dev-tools/thelarklan-bot-review-quorum.pem"
```

Then enforce its mode:

```bash
chmod 600 "$HOME/.config/dev-tools/pr-review-quorum.env"
```

The immutable account-ID mapping is:

| Account | GitHub ID |
| --- | ---: |
| `thelarklan` | `166922787` |
| `larkbot-codex` | `270192887` |
| `larkbot-claude` | `104110997` |
| `larkbot-gemini` | `320627233` |

Do not put the private key, installation token, environment file, or a copy of
the private key in Git. The evaluator refuses a key readable by group or other
users. It obtains a short-lived installation token for every poll, streams the
authorization header to curl over standard input so the token is absent from
process arguments, and does not write that token to disk or logs.

Run one foreground audit before scheduling:

```bash
QUORUM_CONFIG_FILE="$HOME/.config/dev-tools/pr-review-quorum.env" \
  pr-review-quorum
```

Each output line is JSON containing the repository, pull request, exact head,
author and reviewer IDs, conclusion, and check-run ID. It contains no
credential. Copy `cron/pr-review-quorum` into `crontab -e` only after the audit
succeeds. Run exactly one evaluator instance; the template uses `flock` and
polls once per minute.

The append-only audit log is not rotated automatically. Configure `logrotate`
or equivalent retention for `~/.local/state/pr-review-quorum/cron.log` based on
the repository's pull-request volume and required audit window.

## Personal-repository ruleset

The App installation does not create rulesets. For each default branch, create
an active ruleset with no bypass actors that:

- requires pull requests and two approvals;
- dismisses stale approvals and requires approval of the latest reviewable
  push;
- requires all conversations to be resolved;
- requires the branch to be current before merging;
- requires `bot-review-quorum` specifically from
  `thelarklan-bot-review-quorum` and every repository CI check; and
- permits only squash merge.

GitHub auto-merge may be enabled only after the evaluator has published a check
in that repository and the ruleset is verified on a safe pull request. A
personal repository cannot natively restrict the two approval slots to a team.
The App check prevents an owner or outside approval from satisfying the bot
quorum, but polling is not an instantaneous revocation mechanism. Therefore,
while auto-merge is enabled, `thelarklan` must not approve a bot-authored pull
request. If such an approval is submitted, disable auto-merge on that pull
request until the evaluator has published a fresh non-successful result or the
two exact-head bot approvals have been independently reverified.

An API failure before the evaluator can enumerate a repository or pull request
causes a nonzero poll but cannot revoke a previously published check until API
access recovers. The native two-approval rule and the owner-approval constraint
are the safety boundary during that interval.

The evaluator supplies one required check; GitHub remains the only component
that performs the merge.

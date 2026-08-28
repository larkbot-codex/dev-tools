#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

# shellcheck source=bin/pr-review-quorum
source "$project_dir/bin/pr-review-quorum"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

bot_codex=270192887
bot_claude=104110997
bot_gemini=320627233
owner=166922787
bots="[$bot_codex,$bot_claude,$bot_gemini]"
head_sha='exact-head'
pull_file="$test_dir/pull.json"
reviews_file="$test_dir/reviews.json"

write_pull() {
    local author="$1" draft="${2:-false}" base="${3:-main}" state="${4:-open}"
    jq -cn --argjson author "$author" --argjson draft "$draft" --arg base "$base" \
        --arg state "$state" --arg head "$head_sha" \
        '{state:$state,draft:$draft,user:{id:$author},head:{sha:$head},base:{ref:$base}}' >"$pull_file"
}

write_reviews() {
    jq -cn "$1" >"$reviews_file"
}

conclusion() {
    evaluate_quorum "$pull_file" "$reviews_file" main "$bots" "$owner" | jq -r '.conclusion'
}

review() {
    local id="$1" login="$2" state="$3" commit="$4" sequence="$5"
    jq -cn --argjson id "$sequence" --argjson user_id "$id" --arg login "$login" \
        --arg state "$state" --arg commit "$commit" --arg submitted "2026-08-28T10:00:0${sequence}Z" \
        '{id:$id,user:{id:$user_id,login:$login},state:$state,commit_id:$commit,submitted_at:$submitted}'
}

assert_success_for_author() {
    local author="$1" first_id="$2" first_login="$3" second_id="$4" second_login="$5"
    local first second
    write_pull "$author"
    first=$(review "$first_id" "$first_login" APPROVED "$head_sha" 1)
    second=$(review "$second_id" "$second_login" APPROVED "$head_sha" 2)
    write_reviews "[$first,$second]"
    [[ "$(conclusion)" == success ]] || fail "rotation failed for author $author"
}

assert_success_for_author "$bot_codex" "$bot_claude" larkbot-claude "$bot_gemini" larkbot-gemini
assert_success_for_author "$bot_claude" "$bot_codex" larkbot-codex "$bot_gemini" larkbot-gemini
assert_success_for_author "$bot_gemini" "$bot_codex" larkbot-codex "$bot_claude" larkbot-claude

write_pull "$bot_codex"
claude_review=$(review "$bot_claude" larkbot-claude APPROVED "$head_sha" 1)
owner_review=$(review "$owner" thelarklan APPROVED "$head_sha" 2)
write_reviews "[$claude_review,$owner_review]"
[[ "$(conclusion)" == failure ]] || fail 'owner approval substituted for a bot approval'

author_review=$(review "$bot_codex" larkbot-codex APPROVED "$head_sha" 1)
write_reviews "[$author_review,$claude_review,$owner_review]"
[[ "$(conclusion)" == failure ]] || fail 'author or owner approval counted toward quorum'

stale_review=$(review "$bot_gemini" larkbot-gemini APPROVED old-head 2)
write_reviews "[$claude_review,$stale_review]"
[[ "$(conclusion)" == failure ]] || fail 'approval on an old head counted'

dismissed_review=$(review "$bot_gemini" larkbot-gemini DISMISSED "$head_sha" 2)
write_reviews "[$claude_review,$dismissed_review]"
[[ "$(conclusion)" == failure ]] || fail 'dismissed approval counted'

gemini_approval=$(review "$bot_gemini" larkbot-gemini APPROVED "$head_sha" 1)
gemini_change=$(review "$bot_gemini" larkbot-gemini CHANGES_REQUESTED "$head_sha" 3)
write_reviews "[$claude_review,$gemini_approval,$gemini_change]"
[[ "$(conclusion)" == failure ]] || fail 'latest change request did not override approval'

write_pull 999999999
write_reviews "[$claude_review,$gemini_approval]"
[[ "$(conclusion)" == failure ]] || fail 'outside author passed the cohort gate'

write_pull "$owner"
write_reviews "[$claude_review,$gemini_approval]"
[[ "$(conclusion)" == success ]] || fail 'owner-authored pull request did not accept two bot approvals'

write_reviews "[$claude_review,$owner_review]"
[[ "$(conclusion)" == failure ]] || fail 'owner approval counted on an owner-authored pull request'

write_pull "$bot_codex" true
write_reviews "[$claude_review,$gemini_approval]"
[[ "$(conclusion)" == failure ]] || fail 'draft pull request passed'

write_pull "$bot_codex" false release
[[ "$(conclusion)" == failure ]] || fail 'pull request to another base passed'

fake_bin="$test_dir/fake-bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/curl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
method=''
previous=''
for argument in "\$@"; do
    if [[ "\$previous" == -X ]]; then
        method="\$argument"
    fi
    previous="\$argument"
done
url="\${!#}"
case "\$method \$url" in
    *'/app/installations/157289427/access_tokens')
        printf '%s\n' '{"token":"installation-token"}'
        ;;
    *'/installation/repositories?per_page=100&page=1')
        printf '%s\n' '{"repositories":[{"full_name":"thelarklan/example","owner":{"id":166922787},"default_branch":"main"}]}'
        ;;
    *'/repos/thelarklan/example/pulls?state=open&per_page=100&page=1')
        printf '%s\n' '[{"number":7}]'
        ;;
    *'/repos/thelarklan/example/pulls/7/reviews?per_page=100&page=1')
        printf '%s\n' '[{"id":1,"user":{"id":104110997,"login":"larkbot-claude"},"state":"APPROVED","commit_id":"exact-head","submitted_at":"2026-08-28T10:00:01Z"},{"id":2,"user":{"id":320627233,"login":"larkbot-gemini"},"state":"APPROVED","commit_id":"exact-head","submitted_at":"2026-08-28T10:00:02Z"}]'
        ;;
    *'/repos/thelarklan/example/pulls/7')
        printf '%s\n' '{"state":"open","draft":false,"html_url":"https://github.com/thelarklan/example/pull/7","user":{"id":270192887},"head":{"sha":"exact-head"},"base":{"ref":"main"}}'
        ;;
    *'/repos/thelarklan/example/commits/exact-head/check-runs?check_name=bot-review-quorum&filter=latest')
        printf '%s\n' '{"check_runs":[]}'
        ;;
    'POST '*'/repos/thelarklan/example/check-runs')
        printf '%s\n' '{"id":9001}'
        ;;
    *)
        printf 'unexpected fake curl request: %s %s\n' "\$method" "\$url" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$fake_bin/curl"

private_key="$test_dir/app.pem"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$private_key" 2>/dev/null
chmod 600 "$private_key"
config_file="$test_dir/quorum.env"
cat >"$config_file" <<EOF
QUORUM_APP_ID=4752010
QUORUM_INSTALLATION_ID=157289427
QUORUM_OWNER_ID=166922787
QUORUM_BOT_IDS=270192887,104110997,320627233
QUORUM_PRIVATE_KEY_FILE=$private_key
QUORUM_CURL_BIN=$fake_bin/curl
EOF
chmod 600 "$config_file"

integration_output=$(QUORUM_CONFIG_FILE="$config_file" "$project_dir/bin/pr-review-quorum")
[[ "$(jq -r '.conclusion' <<<"$integration_output")" == success ]] || \
    fail 'end-to-end polling fixture did not publish success'
[[ "$(jq -r '.check_run_id' <<<"$integration_output")" == 9001 ]] || \
    fail 'end-to-end polling fixture did not record the published check run'

printf 'pull request quorum tests passed\n'

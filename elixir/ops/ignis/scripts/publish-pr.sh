#!/usr/bin/env bash
set -euo pipefail

log() { printf "[symphony-publish] %s\n" "$*"; }

ISSUE_ID="${SYMPHONY_ISSUE_ID:-}"
ISSUE_IDENTIFIER="${SYMPHONY_ISSUE_IDENTIFIER:-}"
BASE_BRANCH="${SYMPHONY_BASE_BRANCH:-develop}"
REPO="${SYMPHONY_GITHUB_REPO:-ignislabsio/mycards-api}"

if [[ -z "$ISSUE_IDENTIFIER" ]]; then
  log "SYMPHONY_ISSUE_IDENTIFIER is missing; skipping publish"
  exit 0
fi

ISSUE_TITLE="$ISSUE_IDENTIFIER"
ISSUE_URL=""
LINEAR_BRANCH=""
ISSUE_STATE=""
if [[ -n "${LINEAR_API_KEY:-}" ]]; then
  DETAILS_JSON="$(python3 - "$ISSUE_IDENTIFIER" <<'PY' || true
import json, os, sys, urllib.request
identifier = sys.argv[1]
query = '''query($id:String!){ issue(id:$id){ id identifier title url branchName state { name type } } }'''
try:
    req = urllib.request.Request(
        'https://api.linear.app/graphql',
        data=json.dumps({'query': query, 'variables': {'id': identifier}}).encode(),
        headers={'Authorization': os.environ['LINEAR_API_KEY'], 'Content-Type': 'application/json'},
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = json.load(resp)
    issue = (data.get('data') or {}).get('issue') or {}
    print(json.dumps({
        'title': issue.get('title') or identifier,
        'url': issue.get('url') or '',
        'branchName': issue.get('branchName') or '',
        'state': ((issue.get('state') or {}).get('name') or ''),
    }))
except Exception as exc:
    print(json.dumps({'error': str(exc)}))
PY
)"
  ISSUE_TITLE="$(python3 - "$DETAILS_JSON" "$ISSUE_IDENTIFIER" <<'PY'
import json, sys
data=json.loads(sys.argv[1] or '{}')
print(data.get('title') or sys.argv[2])
PY
)"
  ISSUE_URL="$(python3 - "$DETAILS_JSON" <<'PY'
import json, sys
data=json.loads(sys.argv[1] or '{}')
print(data.get('url') or '')
PY
)"
  LINEAR_BRANCH="$(python3 - "$DETAILS_JSON" <<'PY'
import json, sys
data=json.loads(sys.argv[1] or '{}')
print(data.get('branchName') or '')
PY
)"
  ISSUE_STATE="$(python3 - "$DETAILS_JSON" <<'PY'
import json, sys
data=json.loads(sys.argv[1] or '{}')
print(data.get('state') or '')
PY
)"
fi

# Only publish when the agent has explicitly handed the ticket to Human Review.
# This avoids publishing half-finished work after an active/max-turns run.
if [[ "$ISSUE_STATE" != "Human Review" ]]; then
  log "Issue $ISSUE_IDENTIFIER state is '${ISSUE_STATE:-unknown}', not Human Review; skipping publish"
  exit 0
fi

# Ignore purely local agent/cache artifacts.
git update-index -q --refresh || true
if git diff --quiet -- . ':(exclude).codex' ':(exclude).agents' ':(exclude).venv' ':(exclude).pytest_cache' ':(exclude)__pycache__' \
  && [[ -z "$(git ls-files --others --exclude-standard -- . ':(exclude).codex' ':(exclude).agents' ':(exclude).venv' ':(exclude).pytest_cache' ':(exclude)__pycache__')" ]]; then
  log "No publishable changes for $ISSUE_IDENTIFIER"
  exit 0
fi

BRANCH="$LINEAR_BRANCH"
if [[ -z "$BRANCH" ]]; then
  BRANCH="feature/${ISSUE_IDENTIFIER,,}"
fi
BRANCH="$(printf '%s' "$BRANCH" | tr ' ' '-' | tr -cd 'A-Za-z0-9._/-')"

log "Publishing $ISSUE_IDENTIFIER from $(pwd) to $BRANCH"

git config user.name "Byron Rode"
git config user.email "byron@ignislabs.io"

git fetch origin "$BASE_BRANCH" --prune
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git switch "$BRANCH"
else
  git switch -c "$BRANCH"
fi

git add -A
git reset -q -- .codex .agents .venv .pytest_cache __pycache__ 2>/dev/null || true
find . -type d -name __pycache__ -prune -print0 2>/dev/null | xargs -0r git reset -q -- 2>/dev/null || true

if git diff --cached --quiet; then
  log "No staged publishable changes for $ISSUE_IDENTIFIER"
  exit 0
fi

git commit -m "feat(api): ${ISSUE_TITLE} (${ISSUE_IDENTIFIER})"
git push -u origin "$BRANCH"

PR_TITLE="${ISSUE_IDENTIFIER}: ${ISSUE_TITLE}"
BODY_FILE="$(mktemp)"
{
  printf 'Fixes %s\n\n' "$ISSUE_IDENTIFIER"
  [[ -n "$ISSUE_URL" ]] && printf 'Linear: %s\n\n' "$ISSUE_URL"
  printf 'Published automatically by Symphony after the issue moved to Human Review.\n\n'
  printf 'Validation details are recorded in the Linear workpad/comments.\n'
} > "$BODY_FILE"

if gh pr view "$BRANCH" --repo "$REPO" --json url --jq .url >/tmp/symphony-pr-url 2>/dev/null; then
  PR_URL="$(cat /tmp/symphony-pr-url)"
  log "PR already exists: $PR_URL"
else
  PR_URL="$(gh pr create --repo "$REPO" --base "$BASE_BRANCH" --head "$BRANCH" --title "$PR_TITLE" --body-file "$BODY_FILE" --draft 2>&1 | tail -n1)"
  log "Created PR: $PR_URL"
fi

if [[ -n "${LINEAR_API_KEY:-}" && -n "$ISSUE_ID" && "$PR_URL" == http* ]]; then
  PR_URL="$PR_URL" ISSUE_ID="$ISSUE_ID" python3 - <<'PY' || true
import json, os, urllib.request
body = f"Symphony published the draft PR: {os.environ['PR_URL']}"
query = 'mutation($input: CommentCreateInput!) { commentCreate(input: $input) { success } }'
req = urllib.request.Request(
    'https://api.linear.app/graphql',
    data=json.dumps({'query': query, 'variables': {'input': {'issueId': os.environ['ISSUE_ID'], 'body': body}}}).encode(),
    headers={'Authorization': os.environ['LINEAR_API_KEY'], 'Content-Type': 'application/json'},
)
urllib.request.urlopen(req, timeout=20).read()
PY
fi

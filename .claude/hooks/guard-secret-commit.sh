#!/bin/sh
# PreToolUse(Bash): block `git add`/`git commit` of likely-secret files.
# ponytail: filename-based (high signal, low false-positive); fail-open on any parse error so git
# never gets bricked. Content-scanning (BEGIN PRIVATE KEY in an oddly-named file) is deliberately
# out of scope — add it only if a leak slips past filenames.
payload=$(cat)
command -v jq >/dev/null 2>&1 || exit 0          # no jq → can't parse → allow

cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
cwd=$(printf '%s' "$payload" | jq -r '.cwd // "."')

case "$cmd" in
  *"git add"*|*"git commit"*) : ;;
  *) exit 0 ;;
esac

# Match real secret-file extensions/names only — NOT source like AuthKeyManager.swift.
secret_re='\.p8$|\.env$|/secrets\.plist$|\.pem$|\.p12$|\.mobileprovision$|(^|/)id_rsa$|(^|/)id_ed25519$'

# Already-staged files + any paths named explicitly on the command line.
staged=$(cd "$cwd" 2>/dev/null && git diff --cached --name-only 2>/dev/null)
hits=$(printf '%s\n' "$staged" $cmd | grep -Ei "$secret_re" | grep -Ev '\.env\.example$' | sort -u)

if [ -n "$hits" ]; then
  reason="Refusing to stage/commit possible secret(s):
$hits
Secrets belong in Keychain / ~/.hermes/.env / ~/Downloads — never in the repo."
  jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
fi
exit 0

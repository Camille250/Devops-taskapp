#!/usr/bin/env bash
# Fills in your usernames and writes jenkins/.env from Codespaces secrets,
# so no secret is ever typed into a file in Git. Safe to run again any time
# (run it after creating new files that contain the placeholders).
#
# Codespaces sets GITHUB_USER automatically. Add these as Codespaces secrets
# (github.com > Settings > Codespaces > Secrets, give them access to this repo):
#   DOCKERHUB_USER, DOCKERHUB_TOKEN, GH_PAT, JENKINS_ADMIN_PASSWORD
set -euo pipefail
cd "$(dirname "$0")/.."

: "${GITHUB_USER:?GITHUB_USER not set}"
: "${DOCKERHUB_USER:?Add DOCKERHUB_USER as a Codespaces secret, then rebuild/restart the codespace}"

echo "Replacing placeholders with GitHub user '$GITHUB_USER' and Docker Hub user '$DOCKERHUB_USER'"
grep -rl 'your-github-username\|your-dockerhub-username' --exclude-dir=.git --exclude=setup-codespace.sh . \
  | xargs -r sed -i -e "s/your-github-username/$GITHUB_USER/g" -e "s/your-dockerhub-username/$DOCKERHUB_USER/g" \
  || true   # no file with placeholders yet: nothing to replace

REPO_URL=$(git config --get remote.origin.url)
mkdir -p jenkins
cat > jenkins/.env <<ENV
JENKINS_ADMIN_PASSWORD=${JENKINS_ADMIN_PASSWORD:-admin}
DOCKERHUB_USER=${DOCKERHUB_USER}
DOCKERHUB_TOKEN=${DOCKERHUB_TOKEN:?Add DOCKERHUB_TOKEN as a Codespaces secret}
GITHUB_USER=${GITHUB_USER}
GITHUB_TOKEN=${GH_PAT:?Add GH_PAT as a Codespaces secret}
GIT_REPO_URL=${REPO_URL}
ENV
echo "Wrote jenkins/.env (git-ignored). Repo: $REPO_URL"

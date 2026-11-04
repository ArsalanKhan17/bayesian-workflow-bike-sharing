#!/usr/bin/env bash
set -euo pipefail
# Run only from the repository root after full analysis and validation.
repo='ArsalanKhan17/bayesian-workflow-bike-sharing'
Rscript scripts/validate.R --strict
gh auth status
if ! gh repo view "$repo" >/dev/null 2>&1; then
  gh repo create "$repo" --public --description 'An executable Bayesian workflow with R, brms, Stan, and the UCI Bike Sharing dataset'
fi
git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$repo.git"
if [ "$(git remote get-url origin)" != "https://github.com/$repo.git" ]; then
  echo 'origin does not match the intended repository; inspect it before publishing.' >&2
  exit 1
fi
git push --set-upstream origin main
# Pages enablement is an explicit repository administration action.
gh api --method POST "repos/$repo/pages" -f build_type=workflow || {
  echo 'If Pages already exists, select GitHub Actions under repository Settings > Pages.' >&2
}
printf 'Repository: https://github.com/%s\n' "$repo"


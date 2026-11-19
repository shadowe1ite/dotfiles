#!/usr/bin/env bash
# Print latest omp skills docs; refetch only when upstream changed.
R=can1357/oh-my-pi; C=${XDG_CACHE_HOME:-$HOME/.cache}/omp-skill-builder; mkdir -p "$C"
echo "# installed omp: $(omp --version 2>/dev/null | head -1)"
for f in docs/skills.md; do
  n=$(echo $f | tr / _)
  sha=$(gh api "repos/$R/commits?path=$f&per_page=1" --jq '.[0].sha[:8]' 2>/dev/null)
  if [ -n "$sha" ] && [ "$(cat "$C/$n.sha" 2>/dev/null)" != "$sha" ]; then
    gh api "repos/$R/contents/$f" -H "Accept: application/vnd.github.raw" >| "$C/$n" && echo "$sha" >| "$C/$n.sha" && echo "# refreshed $f @ $sha"
  elif [ -z "$sha" ]; then echo "# offline: using cached $f"; else echo "# up to date $f @ $sha"; fi
  cat "$C/$n"
done
echo; echo "# More docs: https://github.com/$R/tree/main/docs (e.g. docs/hooks.md, docs/extensions.md)"

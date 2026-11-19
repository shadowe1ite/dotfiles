#!/usr/bin/env bash
#
# extract_endpoints.sh — pull endpoints/paths/URLs out of local JavaScript files.
#
# Usage:
#   extract_endpoints.sh                  # every *.js in the current working directory (recursive)
#   extract_endpoints.sh file.js ...      # one or more specific JS files
#   extract_endpoints.sh ./dir            # every *.js under a directory (recursive)
#
# Output: sorted, de-duplicated endpoints on stdout.
# Operates only on local files — no network access.

set -euo pipefail

# Use Perl for PCRE matching — portable across GNU/Linux and BSD/macOS
# (macOS grep has no -P). Perl ships on every macOS and most Linux boxes.
#
# Core matcher: feed JS source on stdin, emit candidate endpoints.
#   - absolute & relative paths starting with / or //
#   - http(s) URLs
#   - targets of .get/.post/.ajax/.load/fetch( calls
extract() {
  tr ';})>' '\n' \
    | perl -nle 'while (/(https?:\/\/[^"'"'"'\x60 >]{4,})|(?:["'"'"'\x60](\/{1,2}[a-zA-Z0-9_?&=\/\-#.]{3,}))|(?:(?:\.(?:get|post|ajax|load)|fetch)\s*\(\s*["'"'"'\x60]((?:https?:\/\/)?\/?[^"'"'"'\x60> ]{3,}))/g) { print $1 // $2 // $3 }'
}

clean() {
  perl -nle 'print $1 if /((?:https?:\/\/)?\/?[a-zA-Z0-9_?&=\/\-#.]{3,})/' | sort -u
}

main() {
  # No args → scan *.js under the current working directory.
  if [[ $# -eq 0 ]]; then
    find . -type f -name '*.js' -print0 | xargs -0 cat 2>/dev/null | extract | clean
    return
  fi

  for arg in "$@"; do
    if [[ -d "$arg" ]]; then
      find "$arg" -type f -name '*.js' -print0 | xargs -0 cat 2>/dev/null | extract
    elif [[ -f "$arg" ]]; then
      cat "$arg" | extract
    else
      echo "skip: $arg (not a file or dir)" >&2
    fi
  done | clean
}

main "$@"

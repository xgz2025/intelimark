#!/usr/bin/env bash
#
#  Copyright © 2026 Gaoliang Luo. All rights reserved.
#
#  This software and associated documentation are proprietary
#  and confidential. Unauthorized copying, modification,
#  distribution, or use of this software is strictly prohibited.
#
#  Created by Gaoliang Luo.
#

# Fails when the Swift compiler warned about Nextmark's own code, and reports each
# warning as a GitHub annotation. Third-party packages (GRDB) are ignored.
#   scripts/check-warnings.sh build.log
set -euo pipefail

log="$1"
root="${GITHUB_WORKSPACE:-$PWD}"
pattern='^(/[^:]*/(Packages/NextmarkKit/(Sources|Tests)|App|Extensions)/[^:]+\.swift):([0-9]+):([0-9]+): warning: (.*)$'

warnings=$(grep -E "$pattern" "$log" | sort -u || true)
if [[ -z "$warnings" ]]; then
  echo "No compiler warnings in Nextmark code."
  exit 0
fi

while IFS= read -r line; do
  [[ "$line" =~ $pattern ]] || continue
  file="${BASH_REMATCH[1]#"$root/"}"
  echo "::warning file=${file},line=${BASH_REMATCH[4]},col=${BASH_REMATCH[5]}::${BASH_REMATCH[6]}"
done <<< "$warnings"

echo "$(wc -l <<< "$warnings" | tr -d ' ') compiler warning(s) in Nextmark code." >&2
exit 1

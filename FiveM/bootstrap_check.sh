#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

echo "================================================================"
echo "       NYXFRAMEWORK REPOSITORY & SYNTAX SANITY CHECK"
echo "================================================================"

python3 "$DIR/scripts/bootstrap_validator.py" || python "$DIR/scripts/bootstrap_validator.py"

echo "[SUCCESS] All Nyxframework modules, manifests, and syntax validated!"
exit 0

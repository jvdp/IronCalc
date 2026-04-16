#!/usr/bin/env bash
# Build @ironcalc/wasm + @ironcalc/workbook at the current commit and drop
# the workbook tarball into IronCalc-NC/frontend/vendor/.

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
workbook_dir="$repo_root/webapp/IronCalc"
wasm_dir="$repo_root/bindings/wasm"
consumer="$repo_root/../IronCalc-NC/frontend"

hash=$(git -C "$repo_root" rev-parse --short HEAD)
base_version=$(node -p "require('$workbook_dir/package.json').version.split('-')[0]")
tagged_version="$base_version-$hash"
tarball="ironcalc-workbook-$tagged_version.tgz"

# Files we mutate transiently so the branch doesn't need committed edits.
# Each is copied to a temp file now and restored on exit (success or failure).
backup_dir=$(mktemp -d)
mutated=(
  "$workbook_dir/package.json"
  "$workbook_dir/package-lock.json"
)
for f in "${mutated[@]}"; do
  [ -f "$f" ] && cp "$f" "$backup_dir/$(basename "$f")"
done

restore() {
  for f in "${mutated[@]}"; do
    b="$backup_dir/$(basename "$f")"
    [ -f "$b" ] && cp "$b" "$f"
  done
  rm -rf "$backup_dir"
}
trap restore EXIT

echo "==> Building @ironcalc/wasm (--target web)"
make -C "$wasm_dir" all

echo "==> Applying transient packaging edits"
# Move @ironcalc/wasm from dependencies to devDependencies so the produced
# tarball doesn't ask consumers to resolve the local file: path.
(cd "$workbook_dir" \
  && npm pkg delete 'dependencies.@ironcalc/wasm' >/dev/null \
  && npm pkg set 'devDependencies.@ironcalc/wasm=file:../../bindings/wasm/pkg' >/dev/null \
  && npm pkg set "version=$tagged_version" >/dev/null)

echo "==> Installing workbook dependencies"
(cd "$workbook_dir" && npm install)

echo "==> Building @ironcalc/workbook"
(cd "$workbook_dir" && npm run build)

echo "==> Packing $tarball"
(cd "$workbook_dir" && rm -f ironcalc-workbook-*.tgz && npm pack >/dev/null)

vendor="$consumer/vendor"
mkdir -p "$vendor"
rm -f "$vendor"/ironcalc-workbook-*.tgz
mv "$workbook_dir/$tarball" "$vendor/"
tarball_path="$vendor/$tarball"

(cd "$consumer" && npm pkg set "dependencies.@ironcalc/workbook=file:vendor/$tarball" >/dev/null)
echo "==> Updated $consumer/package.json"

echo "    $tarball_path"
echo "    Next: cd $consumer && rm -rf node_modules/@ironcalc && npm install"

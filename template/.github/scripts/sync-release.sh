#!/usr/bin/env bash
# Keeps GitHub releases in sync with the %changelog of the spec file in dist/.
#
# - Creates a release for the current spec version if it does not exist yet.
# - If the changelog entry of the current version changed, moves its tag to
#   TARGET_SHA, deletes the old packages and updates the release notes.
# - If the changelog entry of an older version changed, only updates the notes.
# - Determines which EL versions are missing packages on the current release,
#   so that interrupted publishing is resumed on the next run.
#
# Required env: GH_REPO, GH_TOKEN, TARGET_SHA, GITHUB_OUTPUT, ALMA_VERSIONS
# Optional env: FORCE_PUBLISH=true to rebuild packages for all EL versions.
set -euo pipefail
shopt -s extglob

spec=$(ls dist/*.spec)
# Drop %{dist} so the tag does not depend on the build host
query() { rpmspec -q --srpm --define 'dist %{nil}' --qf "$1" "$spec"; }

version=$(query '%{VERSION}')
release=$(query '%{RELEASE}')
tag="${version}-${release}"
echo "tag=${tag}" >> "$GITHUB_OUTPUT"
echo "Specfile version: ${tag}"

# Split %changelog into <n>.header / <n>.notes files, newest entry first (n=0)
entries=$(mktemp -d)
trap 'rm -rf "$entries"' EXIT
query '[%{CHANGELOGNAME}\n@@TEXT@@\n%{CHANGELOGTEXT}\n@@END@@\n]' | awk -v dir="$entries" '
  BEGIN { n = 0; state = "header" }
  state == "header" { f = dir "/" n ".header"; print > f; close(f); state = "wait"; next }
  $0 == "@@TEXT@@" { f = dir "/" n ".notes"; printf "" > f; state = "text"; next }
  $0 == "@@END@@" { close(f); n++; state = "header"; next }
  state == "text" { print > f }
'
num_entries=$(find "$entries" -name '*.header' | wc -l)
if (( num_entries == 0 )); then
  echo "::error file=${spec}::The spec file has no %changelog entries."
  exit 1
fi

current_header=$(cat "$entries/0.header")
echo "Latest changelog entry: ${current_header}"
if [[ "${current_header}" != *" ${tag}" && "${current_header}" != *" ${version}" ]]; then
  echo "::error file=${spec}::Latest %changelog entry ('${current_header}') does not match specfile version ${tag}. Add a changelog entry for the new version."
  exit 1
fi

declare -A releases=()
while IFS= read -r t; do
  releases["$t"]=1
done < <(gh release list --limit 1000 --exclude-drafts --json tagName --jq '.[].tagName')

# $(...) strips trailing newlines on both sides, so only real changes are detected
notes_match() { [[ "$(gh release view "$1" --json body --jq .body)" == "$(cat "$2")" ]]; }

# --- Current version ---------------------------------------------------------
if [[ -z "${releases[$tag]:-}" ]]; then
  echo "Creating release ${tag}."
  gh release create "${tag}" --target "${TARGET_SHA}" --title "${tag}" --notes-file "$entries/0.notes"
elif ! notes_match "${tag}" "$entries/0.notes"; then
  tag_sha=$(gh api "repos/${GH_REPO}/git/ref/tags/${tag}" --jq .object.sha)
  if [[ "${tag_sha}" != "${TARGET_SHA}" ]]; then
    echo "Changelog for ${tag} changed, moving tag from ${tag_sha} to ${TARGET_SHA} and rebuilding."
    # Delete stale packages first, so an interrupted rebuild shows up as missing assets on the next run
    gh release view "${tag}" --json assets --jq '.assets[].name' | while IFS= read -r asset; do
      gh release delete-asset "${tag}" "${asset}" --yes
    done
    gh api -X PATCH "repos/${GH_REPO}/git/refs/tags/${tag}" -f sha="${TARGET_SHA}" -F force=true > /dev/null
  fi
  echo "Updating release notes for ${tag}."
  gh release edit "${tag}" --notes-file "$entries/0.notes"
else
  echo "Release ${tag} is up to date."
fi

# --- Older versions: only sync release notes ---------------------------------
for (( i = 1; i < num_entries; i++ )); do
  header=$(cat "$entries/$i.header")
  old_tag=${header##* }
  if [[ "${old_tag}" == "${tag}" || -z "${releases[$old_tag]:-}" ]]; then
    continue
  fi
  if ! notes_match "${old_tag}" "$entries/$i.notes"; then
    echo "Changelog for ${old_tag} changed, updating release notes."
    gh release edit "${old_tag}" --notes-file "$entries/$i.notes"
  fi
done

# --- Determine which EL versions still need packages -------------------------
mapfile -t assets < <(gh release view "${tag}" --json assets --jq '.assets[].name')

# Matches <prefix><suffix>, also allowing a minor version in the dist tag (e.g. .el10_1)
has_asset() {
  local a
  for a in "${assets[@]}"; do
    [[ "$a" == "$1"?(_+([0-9]))"$2" ]] && return 0
  done
  return 1
}

missing=()
for el in ${ALMA_VERSIONS}; do
  if [[ "${FORCE_PUBLISH:-false}" == "true" ]]; then
    missing+=("$el")
    continue
  fi
  defs=(--define "dist .el${el}" --define "rhel ${el}" --define "el${el} 1")
  complete=true
  srpm_prefix=$(rpmspec -q --srpm "${defs[@]}" --qf '%{NAME}-%{VERSION}-%{RELEASE}' "$spec")
  has_asset "${srpm_prefix}" ".src.rpm" || complete=false
  while read -r prefix arch; do
    has_asset "${prefix}" ".${arch}.rpm" || complete=false
  done < <(rpmspec -q "${defs[@]}" --qf '%{NAME}-%{VERSION}-%{RELEASE} %{ARCH}\n' "$spec")
  if [[ "${complete}" == "false" ]]; then
    echo "Release ${tag} is missing packages for EL${el}."
    missing+=("$el")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "publish=true" >> "$GITHUB_OUTPUT"
  echo "alma_versions=[$(IFS=,; echo "${missing[*]}")]" >> "$GITHUB_OUTPUT"
else
  echo "All packages for ${tag} are present."
  echo "publish=false" >> "$GITHUB_OUTPUT"
fi

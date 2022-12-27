#!/usr/bin/env bash
set -euo pipefail

bazel=$(readlink -f /proc/${PPID}/exe)

bazel_format=("$bazel" build \
                    --noshow_progress \
                    --ui_event_filters=-info,-stdout \
                    --color=no \
                    --compile_one_dependency \
                    --aspects=@@WORKSPACE@//:defs.bzl%clang_format_aspect \
                    --@@WORKSPACE@//:binary=@BINARY@ \
                    --@@WORKSPACE@//:config=@CONFIG@ \
                    --output_groups=report)

cd $BUILD_WORKSPACE_DIRECTORY

args=$(printf " union %s" "${@}" | sed "s/^ union \(.*\)/\1/")

sources=$("$bazel" query --color=yes --noshow_progress \
    "let t = kind(\"cc_.* rule\", ${args:-//...}) in labels(srcs, \$t) union labels(hdrs, \$t)")

# manually build wrapper to set up runfiles tree
# https://stackoverflow.com/questions/48178323/during-bazel-build-when-is-target-runfiles-directory-properly-set-up
"$bazel" build \
         --noshow_progress \
         --ui_event_filters=-info,-stdout \
         @@WORKSPACE@//:wrapper &>/dev/null

result=$("${bazel_format[@]}" \
             --keep_going \
             --check_up_to_date \
             $sources 2>&1 || true)

files=$(echo "$result" \
    | grep "ERROR: action 'ClangFormat" \
    | sed "s/^ERROR: action 'ClangFormat \(.*\)\.clang_format' is not up-to-date$/\1/" || true)

if [[ -z $files ]] && [[ $(echo "$result" | grep "ERROR:" | wc -l) -gt 0 ]]; then
    echo "$result"
    exit 1
fi

count=$(echo "$files" | sed '/^\s*$/d' | wc -l)
trap ">&2 echo \"Formatted $count file(s).\"" EXIT

[[ $count -ne 0 ]] || exit 0

# use bazel to generate the formatted files in a separate
# directory in case the user is overriding .clang-format
"${bazel_format[@]}" --@@WORKSPACE@//:dry_run=False $files

for arg in $files; do
    # fix file mode bits
    # https://github.com/bazelbuild/bazel/issues/2888
    chmod $(stat -c "%a" "$arg") "@BINDIR@${arg}.clang_format"

    # replace source with formatted version
    mv "@BINDIR@${arg}.clang_format" "$arg"
done

# run format check to cache success
"${bazel_format[@]}" $files

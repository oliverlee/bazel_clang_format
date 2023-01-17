#!/usr/bin/env bash
set -euo pipefail

bazel=$(readlink -f /proc/${PPID}/exe)

function stale()
{
echo "$1" \
      | grep "ERROR: action 'ClangFormat" \
      | sed "s/^ERROR: action 'ClangFormat \(.*\)\.clang_format' is not up-to-date$/\1/" || true
}

bazel_query=("$bazel" query \
                      --color=yes \
                      --noshow_progress \
                      --ui_event_filters=-info)

bazel_format=("$bazel" build \
                    --noshow_progress \
                    --ui_event_filters=-info,-stdout \
                    --color=no \
                    --aspects=@@WORKSPACE@//:defs.bzl%clang_format_aspect \
                    --@@WORKSPACE@//:binary=@BINARY@ \
                    --@@WORKSPACE@//:config=@CONFIG@ \
                    --output_groups=report)

bazel_format_file=("${bazel_format[@]}" --compile_one_dependency)

cd $BUILD_WORKSPACE_DIRECTORY

# manually build wrapper to set up runfiles tree
# https://stackoverflow.com/questions/48178323/during-bazel-build-when-is-target-runfiles-directory-properly-set-up
"$bazel" build \
         --noshow_progress \
         --ui_event_filters=-info,-stdout \
         @@WORKSPACE@//:wrapper &>/dev/null

args=$(printf " union %s" "${@}" | sed "s/^ union \(.*\)/\1/")

source_files=$("${bazel_query[@]}" \
    "let t = kind(\"cc_.* rule\", ${args:-//...}) in labels(srcs, \$t) union labels(hdrs, \$t)")

result=$("${bazel_format_file[@]}" \
             --keep_going \
             --check_up_to_date \
             $source_files 2>&1 || true)

files=$(stale "$result")

if [[ -z $files ]] && [[ $(echo "$result" | grep "ERROR:" | wc -l) -gt 0 ]]; then
    echo "$result"
    exit 1
fi

# libraries without `srcs` are not handled correctly with `--compile_one_dependency`
header_libs=$("${bazel_query[@]}" \
    "attr(\"srcs\", \"\[\]\", kind(\"cc_library rule\", ${args:-//...}))")

result=$("${bazel_format[@]}" \
             --keep_going \
             --check_up_to_date \
             $header_libs 2>&1 || true)

header_files=$(stale "$result")

file_count=$(echo "$files" | sed '/^\s*$/d' | wc -l)
header_file_count=$(echo "$header_files" | sed '/^\s*$/d' | wc -l)

[[ $file_count -ne 0 ]] || [[ $header_file_count -ne 0 ]] || exit 0

# use bazel to generate the formatted files in a separate
# directory in case the user is overriding .clang-format
[[ $file_count -eq 0 ]] || "${bazel_format_file[@]}" --@@WORKSPACE@//:dry_run=False $files

# format all header only libs
[[ $header_file_count -eq 0 ]] || "${bazel_format[@]}" --@@WORKSPACE@//:dry_run=False $header_libs

for arg in $(echo "$files" "$header_files"); do
    # fix file mode bits
    # https://github.com/bazelbuild/bazel/issues/2888
    chmod $(stat -c "%a" "$arg") "@BINDIR@${arg}.clang_format"

    # replace source with formatted version
    mv "@BINDIR@${arg}.clang_format" "$arg"
done

# run format check to cache success
[[ $file_count -eq 0 ]] || "${bazel_format_file[@]}" $files
[[ $header_file_count -eq 0 ]] || "${bazel_format[@]}" $header_libs

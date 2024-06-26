#!/usr/bin/env bash
set -euo pipefail

function bazel_bin
{
    pid=$PPID
    bin=$(readlink -f "/proc/$pid/exe")

    while $bin --version | grep -q -v '^bazel'; do
        pid=$(ps -o ppid= $pid | xargs)
        bin=$(readlink -f "/proc/$pid/exe")
    done

    echo "$bin"
}

bazel=$(bazel_bin)

bazel_query=("$bazel" query \
                      --noshow_progress \
                      "--ui_event_filters=-info" \
                      "--color=yes")

bazel_format=("$bazel" build \
                       --noshow_progress \
                       "--ui_event_filters=-info,-stdout" \
                       "--color=yes" \
                       "--aspects=@@WORKSPACE@//:defs.bzl%clang_format_aspect" \
                       "--@@WORKSPACE@//:binary=@BINARY@" \
                       "--@@WORKSPACE@//:config=@CONFIG@" \
                       "--@@WORKSPACE@//:ignore=@IGNORE@" \
                       "--output_groups=report" \
                       --keep_going \
                       --verbose_failures)

function stale
{
    format_args=("$@")

    result=$("${bazel_format[@]}" \
                 --check_up_to_date \
                 "${format_args[@]}" 2>&1 || true)

    echo "$result" \
        | grep ".*ERROR:.*action 'ClangFormat" \
        | sed -e 's/\x1b\[[0-9;]*m//g' \
        | sed -e "s/^.* action 'ClangFormat \(.*\)\.clang_format' is not up-to-date$/\1/" || true
}

function update
{
    generated="@BINDIR@${1}.clang_format"
    if [[ ! -f "$generated" ]]; then
        echo "ERROR: unable to find $generated"
        exit 1
    fi

    # fix file mode bits
    # https://github.com/bazelbuild/bazel/issues/2888
    chmod "$(stat -c "%a" "$1")" "$generated"

    # replace source with formatted version
    mv "$generated" "$1"
}


cd "$BUILD_WORKSPACE_DIRECTORY"

"$bazel" build @BINARY@

args=$(printf " union %s" "${@}" | sed "s/^ union \(.*\)/\1/")

source_targets="let t = kind(\"cc_.* rule\", ${args:-//...} except deps(@IGNORE@, 1)) in labels(srcs, \$t) union labels(hdrs, \$t)"
readarray -t source_files < <("${bazel_query[@]}" "$source_targets")
readarray -t files < <(stale --compile_one_dependency "${source_files[@]}")

# libraries without `srcs` are not handled correctly with `--compile_one_dependency`
header_targets="attr(\"srcs\", \"\[\]\", kind(\"cc_library rule\", ${args:-//...}))"
readarray -t header_libraries < <("${bazel_query[@]}" "$header_targets")
readarray -t header_files < <(stale "${header_libraries[@]}")

# https://stackoverflow.com/questions/48394251/why-are-empty-arrays-treated-as-unset-in-bash
set +u

if [[ ${#files[@]} -eq 0 ]] && [[ ${#header_files[@]} -eq 0 ]]; then
    exit 0
fi

# use bazel to generate the formatted files in a separate
# directory in case the user is overriding .clang-format
if [[ ${#files[@]} -ne 0 ]]; then
    "${bazel_format[@]}" --compile_one_dependency --@@WORKSPACE@//:dry_run=False --remote_download_outputs=toplevel "${files[@]}"
fi

# format all header only libs
if [[ ${#header_files[@]} -ne 0 ]]; then
    "${bazel_format[@]}" --@@WORKSPACE@//:dry_run=False --remote_download_outputs=toplevel "${header_libraries[@]}"
fi

export -f update
printf '%s\n' "${files[@]}" "${header_files[@]}" | xargs -P 0 -n 1 -I {} /bin/bash -c 'update {}'

# run format check to cache success
if [[ ${#files[@]} -ne 0 ]]; then
    "${bazel_format[@]}" --compile_one_dependency "${files[@]}"
fi
if [[ ${#header_files[@]} -ne 0 ]]; then
    "${bazel_format[@]}" "${header_libraries[@]}"
fi

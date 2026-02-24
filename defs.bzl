"""
clang-format aspect
"""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _source_files_in(ctx, attr):
    if not hasattr(ctx.rule.attr, attr):
        return []

    files = []
    for file_target in getattr(ctx.rule.attr, attr):
        files += file_target.files.to_list()

    return [f for f in files if f.is_source]

def _do_format(ctx, f, format_options, execution_reqs):
    binary = ctx.attr._binary.files_to_run.executable
    out = ctx.actions.declare_file(f.short_path + ".clang_format")

    ctx.actions.run_shell(
        inputs = [
            ctx.file._config,
            f,
        ] + ([binary] if binary else []),
        outputs = [out],
        command = """
set -euo pipefail

# https://github.com/llvm/llvm-project/issues/46336
# although newer versions of clang-format (e.g. 18.1.4) *do* appear to work
# with symlinks
#
{binary} -style=file:{config} {format_options} $(readlink -f {infile})

touch {outfile}
""".format(
            config = ctx.file._config.path,
            binary = binary.path if binary else "clang-format",
            format_options = " ".join(format_options),
            infile = f.path,
            outfile = out.path,
        ),
        mnemonic = "ClangFormat",
        progress_message = "Formatting {}".format(f.short_path),
        use_default_shell_env = True,
        execution_requirements = execution_reqs,
    )

    return out

def _clang_format_aspect_impl(format_options, execution_requirements):
    def impl(target, ctx):
        ignored = {f.owner: "" for f in ctx.attr._ignore.files.to_list()}

        if target.label in ignored.keys():
            return [OutputGroupInfo(report = depset([]))]

        outputs = [
            _do_format(
                ctx,
                f,
                format_options,
                execution_requirements,
            )
            for f in (
                _source_files_in(ctx, "srcs") +
                _source_files_in(ctx, "hdrs")
            )
        ]

        return [OutputGroupInfo(report = depset(outputs))]

    return impl

def make_clang_format_aspect(
        binary = None,
        config = None,
        ignore = None,
        options = None,
        execution_requirements = None):
    return aspect(
        implementation = _clang_format_aspect_impl(
            options or [],
            execution_requirements or {},
        ),
        fragments = ["cpp"],
        attrs = {
            "_binary": attr.label(
                default = Label(binary or "//:binary"),
            ),
            "_config": attr.label(
                default = Label(config or "//:config"),
                allow_single_file = True,
            ),
            "_ignore": attr.label(
                default = Label(ignore or "//:ignore"),
            ),
        },
        required_providers = [CcInfo],
        toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    )

check_aspect = make_clang_format_aspect(
    options = ["--color=true", "--Werror", "--dry-run"],
    execution_requirements = {
        "no-remote": "1",
        "local": "1",
    },
)

fix_aspect = make_clang_format_aspect(
    options = ["-i"],
    # https://stackoverflow.com/questions/50025990/disable-sandbox-in-custom-rule
    #
    # https://bazel.build/reference/be/common-definitions#common.tags
    #
    # however, due to
    # https://github.com/bazelbuild/bazel/issues/15516
    # https://github.com/bazelbuild/bazel/issues/21587
    #
    # fixing formatting will require use of --use_action_cache=false
    # https://bazel.build/versions/6.5.0/docs/user-manual#use-action-cache
    execution_requirements = {
        "no-sandbox": "1",
        "no-cache": "1",
        "no-remote": "1",
        "local": "1",
    },
)

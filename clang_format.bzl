"""
clang-format aspect
"""

def _source_files_in(ctx, attr):
    if not hasattr(ctx.rule.attr, attr):
        return []

    files = []
    for file_target in getattr(ctx.rule.attr, attr):
        files += file_target.files.to_list()

    return [f for f in files if f.is_source]

def _path(f):
    return f.path

def _clang_format_aspect_impl(target, ctx):
    if not CcInfo in target:
        return []

    wrapper = ctx.attr._wrapper.files_to_run
    binary = ctx.attr._binary.files_to_run.executable
    config = ctx.attr._config.files.to_list()
    files = _source_files_in(ctx, "srcs") + _source_files_in(ctx, "hdrs")

    if len(config) != 1:
        fail(":config must contain a single file.")

    inputs = depset(direct = (files + config + ([binary] if binary else [])))

    outfile = ctx.actions.declare_file(
        "{name}.clang_format.touch".format(name = ctx.label.name),
    )

    args = ctx.actions.args()
    args.add(binary or "clang-format")
    args.add(outfile.path)
    args.add(config[0].path)
    args.add("--Werror")
    args.add("--dry-run")
    args.add("--fcolor-diagnostics")
    args.add_all(files, map_each = _path)

    ctx.actions.run(
        inputs = inputs,
        outputs = [outfile],
        executable = wrapper,
        arguments = [args],
        mnemonic = "ClangFormat",
        progress_message = "Run clang-format on {}".format(
            ", ".join([f.short_path for f in files]),
        ),
    )

    return [OutputGroupInfo(report = depset(direct = [outfile]))]

clang_format_aspect = aspect(
    implementation = _clang_format_aspect_impl,
    fragments = ["cpp"],
    attrs = {
        "_wrapper": attr.label(default = Label("//:wrapper")),
        "_binary": attr.label(default = Label("//:binary")),
        "_config": attr.label(default = Label("//:config")),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
)

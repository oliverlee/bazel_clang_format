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

def _check_format(ctx, f):
    wrapper = ctx.attr._wrapper.files_to_run
    binary = ctx.attr._binary.files_to_run.executable
    config = ctx.attr._config.files.to_list()

    if len(config) != 1:
        fail(":config must contain a single file.")

    touch = ctx.actions.declare_file(
        "{name}.clang_format".format(name = f.short_path),
    )

    ctx.actions.run(
        inputs = config + ([binary] if binary else []) + [f],
        outputs = [touch],
        executable = wrapper,
        arguments = [
            binary.path if binary else "clang-format",
            config[0].path,
            f.path,
            touch.path,
        ],
    )

    return touch

def _clang_format_aspect_impl(_target, ctx):
    outputs = [
        _check_format(ctx, f)
        for f in (
            _source_files_in(ctx, "srcs") +
            _source_files_in(ctx, "hdrs")
        )
    ]

    return [OutputGroupInfo(report = depset(direct = outputs))]

clang_format_aspect = aspect(
    implementation = _clang_format_aspect_impl,
    fragments = ["cpp"],
    attrs = {
        "_wrapper": attr.label(default = Label("//:wrapper")),
        "_binary": attr.label(default = Label("//:binary")),
        "_config": attr.label(default = Label("//:config")),
    },
    required_providers = [CcInfo],
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
)

"""
clang-format aspect
"""

# Avoid the need to bring in bazel-skylib as a dependency
# https://github.com/bazelbuild/bazel-skylib/blob/main/docs/common_settings_doc.md
BuildSettingInfo = provider(
    doc = "Contains the value of a build setting.",
    fields = {
        "value": "The value of the build setting in the current configuration. " +
                 "This value may come from the command line or an upstream transition, " +
                 "or else it will be the build setting's default.",
    },
)

def _impl(ctx):
    return BuildSettingInfo(value = ctx.build_setting_value)

bool_flag = rule(
    implementation = _impl,
    build_setting = config.bool(flag = True),
    doc = "A bool-typed build setting that can be set on the command line",
)

def _source_files_in(ctx, attr):
    if not hasattr(ctx.rule.attr, attr):
        return []

    files = []
    for file_target in getattr(ctx.rule.attr, attr):
        files += file_target.files.to_list()

    return [f for f in files if f.is_source]

def _check_format(ctx, package, f):
    wrapper = ctx.attr._wrapper.files_to_run
    binary = ctx.attr._binary.files_to_run.executable
    config = ctx.attr._config.files.to_list()
    dry_run = ctx.attr._dry_run[BuildSettingInfo].value

    if len(config) != 1:
        fail(":config {} must contain a single file.".format(config))

    out = ctx.actions.declare_file(
        "{name}.clang_format".format(
            # don't duplicate package in the out file
            name = f.short_path.removeprefix(package + "/"),
        ),
    )

    ctx.actions.run(
        inputs = config + ([binary] if binary else []) + [f],
        outputs = [out],
        executable = wrapper,
        arguments = [
            binary.path if binary else "clang-format",
            config[0].path,
            f.path,
            out.path,
        ] + (["--dry-run"] if dry_run else [""]),
        mnemonic = "ClangFormat",
    )

    return out

def _clang_format_aspect_impl(target, ctx):
    outputs = [
        _check_format(ctx, target.label.package, f)
        for f in (
            _source_files_in(ctx, "srcs") +
            _source_files_in(ctx, "hdrs")
        )
    ]

    return [OutputGroupInfo(report = depset(outputs))]

clang_format_aspect = aspect(
    implementation = _clang_format_aspect_impl,
    fragments = ["cpp"],
    attrs = {
        "_wrapper": attr.label(default = Label("//:wrapper")),
        "_binary": attr.label(default = Label("//:binary")),
        "_config": attr.label(default = Label("//:config")),
        "_dry_run": attr.label(default = Label("//:dry_run")),
    },
    required_providers = [CcInfo],
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
)

def _clang_format_update_impl(ctx):
    update_format = ctx.actions.declare_file(
        "{}.clang_format.sh".format(ctx.attr.name),
    )

    bindir = update_format.path[:update_format.path.find("bin/")] + "bin/"

    config = ctx.attr._config.files.to_list()
    if len(config) != 1:
        fail(":config ({}) must contain a single file".format(config))

    ctx.actions.expand_template(
        template = ctx.attr._template.files.to_list()[0],
        output = update_format,
        substitutions = {
            "@BINARY@": str(ctx.attr._binary.label),
            "@CONFIG@": str(ctx.attr._config.label),
            "@WORKSPACE@": ctx.label.workspace_name,
            "@BINDIR@": bindir,
        },
    )

    # TODO set dependency on wrapper runfiles tree
    # see
    # https://github.com/bazelbuild/bazel/issues/1516
    # https://stackoverflow.com/questions/48178323/during-bazel-build-when-is-target-runfiles-directory-properly-set-up

    return [DefaultInfo(
        executable = update_format,
    )]

clang_format_update = rule(
    implementation = _clang_format_update_impl,
    fragments = ["cpp"],
    attrs = {
        "_template": attr.label(default = Label("//:template")),
        "_binary": attr.label(default = Label("//:binary")),
        "_config": attr.label(default = Label("//:config")),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    executable = True,
)

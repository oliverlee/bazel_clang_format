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
    binary = ctx.attr._binary.files_to_run.executable
    dry_run = ctx.attr._dry_run[BuildSettingInfo].value

    out = ctx.actions.declare_file(
        "{name}.clang_format".format(
            # don't duplicate package in the out file
            name = f.short_path.removeprefix(package + "/"),
        ),
    )

    ctx.actions.run(
        inputs = [ctx.file._config] + ([binary] if binary else []) + [f],
        outputs = [out],
        executable = ctx.executable._wrapper,
        arguments = [
            binary.path if binary else "clang-format",
            ctx.file._config.path,
            f.path,
            out.path,
        ] + (["--dry-run"] if dry_run else [""]),
        mnemonic = "ClangFormat",
    )

    return out

def _clang_format_aspect_impl(target, ctx):
    ignored = {f.owner: "" for f in ctx.attr._ignore.files.to_list()}

    if target.label in ignored.keys():
        return [OutputGroupInfo(report = depset([]))]

    outputs = [
        _check_format(ctx, target.label.package, f)
        for f in (
            _source_files_in(ctx, "srcs") +
            _source_files_in(ctx, "hdrs")
        )
    ]

    return [OutputGroupInfo(report = depset(outputs))]

def make_clang_format_aspect(binary = None, config = None, ignore = None):
    return aspect(
        implementation = _clang_format_aspect_impl,
        fragments = ["cpp"],
        attrs = {
            "_wrapper": attr.label(
                executable = True,
                cfg = "exec",
                allow_files = True,
                default = Label("//:wrapper"),
            ),
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
            "_dry_run": attr.label(default = Label("//:dry_run")),
        },
        required_providers = [CcInfo],
        toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    )

clang_format_aspect = make_clang_format_aspect()

def _clang_format_update_impl(ctx):
    update_format = ctx.actions.declare_file(
        "bazel_clang_format.{}.sh".format(ctx.attr.name),
    )

    bindir = update_format.path[:update_format.path.find("bin/")] + "bin/"

    binary = ctx.attr.binary or ctx.attr._binary
    config = ctx.attr.config or ctx.attr._config
    ignore = ctx.attr.ignore or ctx.attr._ignore

    # get the workspace of bazel_clang_format, not where this update rule is
    # defined
    workspace = ctx.attr._template.label.workspace_name

    ctx.actions.expand_template(
        template = ctx.attr._template.files.to_list()[0],
        output = update_format,
        substitutions = {
            "@BINARY@": str(binary.label),
            "@CONFIG@": str(config.label),
            "@IGNORE@": str(ignore.label),
            "@WORKSPACE@": workspace,
            "@BINDIR@": bindir,
        },
    )

    format_bin = binary.files_to_run.executable
    runfiles = ctx.runfiles(
        ([format_bin] if format_bin else []) +
        config.files.to_list(),
    )

    return [DefaultInfo(
        executable = update_format,
        runfiles = runfiles,
    )]

clang_format_update = rule(
    implementation = _clang_format_update_impl,
    fragments = ["cpp"],
    attrs = {
        "_template": attr.label(default = Label("//:template")),
        "_binary": attr.label(default = Label("//:binary")),
        "_config": attr.label(
            allow_single_file = True,
            default = Label("//:config"),
        ),
        "_ignore": attr.label(
            default = Label("//:ignore"),
        ),
        "binary": attr.label(
            doc = "Set clang-format binary to use. Overrides //:binary",
        ),
        "config": attr.label(
            allow_single_file = True,
            doc = "Set clang-format config to use. Overrides //:config",
        ),
        "ignore": attr.label(
            doc = "Set clang-format ignore targets to use. Overrides //:ignore",
        ),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    executable = True,
)

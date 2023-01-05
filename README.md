# bazel_clang_format

Run clang-format on Bazel C++ targets directly. It's like
[bazel_clang_tidy](https://github.com/erenon/bazel_clang_tidy) but for
clang-format.

## usage

```py
# //:WORKSPACE.bazel
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_repository")

BAZEL_CLANG_FORMAT_COMMIT = ...

BAZEL_CLANG_FORMAT_SHA = ...

http_repository(
    name = "bazel_clang_format",
    sha256 = BAZEL_CLANG_FORMAT_SHA,
    strip_prefix = "bazel_clang_format-{commit}".format(
        commit = BAZEL_CLANG_FORMAT_COMMIT,
    ),
    url = "https://github.com/oliverlee/bazel_clang_format/archive/{commit}.tar.gz".format(
        commit = BAZEL_CLANG_FORMAT_COMMIT,
    ),
)
```

You can now compile using the default clang format configuration provided using
the following command:

```
bazel build //... \
  --aspects @bazel_clang_format//:defs.bzl%clang_format_aspect \
  --output_groups=report
```

By default, `.clang-format` from this repo is applied. If you wish to override
the config, define a filegroup:

```py
# //:BUILD.bazel
filegroup(
    name = "clang_format_config",
    srcs = [".clang-format"],
    visibility = ["//visibility:public"],
)
```

and override the default config file using the config setting:

```sh
bazel build //... \
  --aspects @bazel_clang_format//:defs.bzl%clang_format_aspect \
  --@bazel_clang_format//:config=//:clang_format_config \ # <-----------
  --output_groups=report
```

To specify a specific binary (e.g. `clang-format` is specified by a hermetic
toolchain like [this](https://github.com/grailbio/bazel-toolchain), with the
binary setting:

```sh
bazel build //... \
  --aspects @bazel_clang_format//:defs.bzl%clang_format_aspect \
  --@bazel_clang_format//:binary=@llvm15//:clang-format \ # <-----------
  --output_groups=report
```

Now if you don't want to type this out every time, it is recommended that you
add a config in your .bazelrc that matches this command line;

Config shorthand:

```
# //.bazelrc
build:clang-format --aspects @bazel_clang_format//:defs.bzl%clang_format_aspect
build:clang-format --output_groups=report
```
or with configuration:

```
# //.bazelrc
build:clang-format --aspects @bazel_clang_format//:defs.bzl%clang_format_aspect
build:clang-format --@bazel_clang_format//:binary=@llvm15//:clang-format
build:clang-format --@bazel_clang_format//:config=//:clang_format_config
build:clang-format --output_groups=report
```

then run:

```sh
bazel build //... --config clang-format
```

To format all source files:

```sh
bazel run @bazel_clang_format//:update \
  --@bazel_clang_format//:binary=@llvm15//:clang_format \
  --@bazel_clang_format//:config=//:clang_format_config
```

with a specific binary/config if desired.

Or to format specific targets:

```sh
bazel run @bazel_clang_format//:update -- //src/...
```

## defaults without .bazelrc

Both the aspect and update rule can be defined locally to bake in a default
binary or config.

```python
# //:BUILD.bazel
load("@bazel_clang_format//:defs.bzl", "clang_format_update")

alias(
    name = "default_clang_format_binary",
    actual = "@llvm_toolchain//:clang-format",
)

filegroup(
    name = "default_clang_format_config",
    srcs = [".clang-format"]
    visibility = ["//visibility:public"],
)

clang_format_update(
    name = "clang_format",
    binary = ":default_clang_format_binary",
    config = ":default_clang_format_config",
)
```

```python
# //:aspects.bzl
load("@bazel_clang_format//:defs.bzl", "make_clang_format_aspect")

clang_format = make_clang_format_aspect(
    binary = "//:default_clang_format_binary",
    config = "//:default_clang_format_config",
)
```

```sh
bazel run //:clang_format
bazel build //... --aspects //:aspects.bzl%clang_format --output_groups=report
```

## Requirements

- Bazel ???
- clang-format ???

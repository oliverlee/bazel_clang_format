# bazel_clang_format

Run `clang-format` on Bazel C++ targets directly. It's like
[bazel_clang_tidy](https://github.com/erenon/bazel_clang_tidy) but for
`clang-format`.

## usage

Update your project with

```Starlark
# //:WORKSPACE.bazel
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_repository")

BAZEL_CLANG_FORMAT_COMMIT = ...

http_repository(
    name = "bazel_clang_format",
    integrity = ...,
    strip_prefix = "bazel_clang_format-{commit}".format(
        commit = BAZEL_CLANG_FORMAT_COMMIT,
    ),
    url = "https://github.com/oliverlee/bazel_clang_format/archive/{commit}.tar.gz".format(
        commit = BAZEL_CLANG_FORMAT_COMMIT,
    ),
)
```

```Starlark
# //:.bazelrc

build:clang-format --aspects @bazel_clang_format//:defs.bzl%check_aspect
build:clang-format --output_groups=report

build:clang-format-fix --aspects @bazel_clang_format//:defs.bzl%fix_aspect
build:clang-format-fix --output_groups=report
build:clang-format-fix --use_action_cache=false
```

Check formatting with

```sh
bazel build //... --config=clang-format
```

Fix formatting with

```sh
bazel build //... --config=clang-format-fix
```

This will use `clang-format` in your `PATH` and `.clang-format` defined in this
repo.


### using a hermetic toolchain

<details><summary></summary>

To specify a specific binary (e.g. `clang-format` is specified by a hermetic
toolchain like [this](https://github.com/grailbio/bazel-toolchain)), update the
build setting in `.bazelrc`.

```Starlark
# //:.bazelrc

build:clang-format-base --output_groups=report
build:clang-format-base --@bazel_clang_format//:binary=@llvm18//:clang-format

build:clang-format --aspects @bazel_clang_format//:defs.bzl%check_aspect

build:clang-format-fix --aspects @bazel_clang_format//:defs.bzl%fix_aspect
build:clang-format-fix --use_action_cache=false
```

</details>

### specifying `.clang-format`

<details><summary></summary>

To override the default `.clang-format`, define a `filegroup` containing the
replacement config and update build setting in `.bazelrc`.

```Starlark
# //:BUILD.bazel

load("@bazel_clang_format//:defs.bzl")

filegroup(
    name = "clang-format-config",
    srcs = [".clang-format"],
    visibility = ["//visibility:public"],
)
```

```Starlark
# //:.bazelrc

build:clang-format-base --output_groups=report
build:clang-format-base --@bazel_clang_format//:config=//:clang-format-config # <-----
...
```

</details>

### ignoring certain targets

<details><summary></summary>

Formatting can be skipped for certain targets by specifying a filegroup

```Starlark
# //:BUILD.bazel

filegroup(
    name = "clang-format-ignore",
    srcs = [
       "//third_party/lib1",
       "//third_party/lib2",
    ],
)
```

```Starlark
# //:.bazelrc

build:clang-format-base --output_groups=report
build:clang-format-base --@bazel_clang_format//:ignore=//:clang-format-ignore# <-----
...
```

</details>

## Requirements

- Bazel ???
- clang-format ???

I'm not sure what the minimum versions are but please let me know if you are
using a version that doesn't work.

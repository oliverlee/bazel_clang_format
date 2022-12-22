#!/usr/bin/env bash
set -eu

binary=$1
outfile=$2
config=$3

test -e .clang-format || ln -s -f $config .clang-format
$binary "${@:4}"
touch $outfile

#!/usr/bin/env bash
set -eu

binary=$1
config=$2
infile=$3
outfile=$4

test -e .clang-format || ln -s -f $config .clang-format

$binary --fcolor-diagnostics --Werror --dry-run $infile
touch $outfile

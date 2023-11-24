#!/usr/bin/env bash
set -eu

binary=$1
config=$2
infile=$3
outfile=$4
dry_run=$5

test -e .clang-format || ln -s -f $config .clang-format

$binary --color=true --Werror $dry_run $infile > $outfile

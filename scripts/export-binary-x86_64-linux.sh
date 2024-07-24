#!/usr/bin/env bash

name=$1
out=$2
cp "./result/bin/$name" "$name"
patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 --set-rpath /lib/x86_64-linux-gnu "$out/$name-x86_64-linux"

#!/bin/bash

caminho_sistema=$1
rev=$2

dir=$(pwd)

cd "$caminho_sistema"

git fetch --all --force --quiet

git checkout --force --quiet $rev

cd $dir

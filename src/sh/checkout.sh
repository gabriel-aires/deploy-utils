#!/bin/bash

repo=$1
caminho_sistema=$2
rev=$3
script_dir=$4
temp_dir=$5
dir=$(pwd)

if [ ! -d "$caminho_sistema/.git" ]; then
	echo " "
	git clone --progress $repo $caminho_sistema							#clona o repositório, caso ainda não tenha sido feito.
fi

echo " "

cd "$caminho_sistema"

{ 
	git fetch --all --force --quiet && git checkout --force --quiet $rev 
} || { 
	source $script_dir/clean_temp.sh $temp_dir && exit 
}

cd $dir

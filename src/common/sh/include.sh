#!/bin/bash
# Este arquivo deve ser carregado no cabeçalho de cada script através do comando "source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1"

install_dir="$(dirname $(dirname $(readlink -f $0)))"

# Define/Carrega variáveis, funções e scripts comuns.

INCLUDE=${INCLUDE:='0'}

if [ "$INCLUDE" -eq '0' ]; then
    source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/conf/include.conf || exit 1
    source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/functions.sh || exit 1
    PATH="$PATH:$(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh"
    INCLUDE='1'
fi

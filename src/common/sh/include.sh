#!/bin/bash
# Este arquivo deve ser carregado no cabeçalho de cada script através do comando "source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1"

# Define/Carrega variáveis, funções e scripts comuns.

INCLUDE=${INCLUDE:=false}

if ! "$INCLUDE"; then

    message_format='simple'

    # Define caminhos padrão
    install_dir="$(dirname $(dirname $(readlink -f $0)))"
    log_dir="${install_dir}/log"
    src_dir="$(dirname $install_dir)"
    doc_dir="$(dirname $src_dir)/docs"
    version_file="$src_dir/common/conf/version.txt"
    release_file="$src_dir/common/conf/release.txt"
    error_log="$log_dir/error.log"

    # Cria log de erros
    mkdir -p $log_dir || exit 1
    error_log="$log_dir/error_$$_$(basename $0).log"
    touch $error_log || exit 1

    # Declara arrays associativos
    declare -A col
    declare -A regex
    declare -A not_regex
    declare -A auto
    declare -A branch
    declare -A revisao
    declare -A hosts
    declare -A deploy_path
    declare -A modo

    # carrega funções comuns e define PATH
    source $src_dir/common/sh/functions.sh || exit 1
    PATH="$PATH:$src_dir/common/sh"

    # carrega configurações default comuns
    test -f "$src_dir/common/conf/include.conf" && source "$src_dir/common/conf/include.conf" || exit 1

    INCLUDE=true

fi

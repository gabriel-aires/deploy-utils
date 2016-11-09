#!/bin/bash
# Este arquivo deve ser carregado no cabeçalho de cada script através do comando "source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1"

# Define/Carrega variáveis, funções e scripts comuns.

INCLUDE=${INCLUDE:=false}

if ! "$INCLUDE"; then

    verbosity='verbose'

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
    declare -A regex_host
    declare -A auto
    declare -A branch
    declare -A revisao
    declare -A hosts
    declare -A share
    declare -A modo

    # carrega funções comuns e define PATH
    source $src_dir/common/sh/functions.sh || exit 1
    PATH="$PATH:$src_dir/common/sh"

    # carrega overrides específicos
    test -f "$src_dir/common/conf/environments.conf" || exit 1
    #chk_template "$src_dir/common/conf/environments.conf"
    source "$src_dir/common/conf/environments.conf" || exit 1

    # carrega configurações default comuns
    test -f "$src_dir/common/conf/include.conf" || exit 1
    #chk_template "$src_dir/common/conf/include.conf"
    source "$src_dir/common/conf/include.conf" || exit 1

    # atribui regras de validação de hostnames para cada ambiente
    valid 'ambientes' 'regex_env_list' 'Erro. Lista de ambientes inválida.'
    regex_ambiente="$(echo "$ambientes" | tr ' ' '|')"
    for environment in ${!regex_host[@]}; do
        valid 'environment' 'regex_ambiente' 'Erro. '$environment': Ambiente inválido.'
        custom_value="${regex_host[$environment]}"
        default_value="${regex_host[0]}"
        current_value="${custom_value:-$default_value}"
        regex_host["$environment"]="$current_value"
        regex_hosts["$environment"]="($current_value[ ,]?)+"
    done
    unset environment custom_value default_value current_value

    INCLUDE=true

fi

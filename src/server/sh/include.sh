#!/bin/bash

# Carrega funções e variáveis comuns, define $PATH
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/functions.sh || exit 1

# Cria log de erros
mkdir -p $log_dir || exit 1
error_log="$log_dir/error_$$_$(basename $0).log"
touch $error_log || exit 1

# Carrega preferências do usuário (overrides)
chk_template "$install_dir/conf/user.conf" 'user' &>> $error_log && source "$install_dir/conf/user.conf" &>> $error_log || exit 1

# Carrega valores default para o servidor
chk_template "$install_dir/conf/global.conf" 'global' &>> $error_log && source "$install_dir/conf/global.conf" &>> $error_log  || exit 1

# Define diretório temporário.
pid=$$
tmp_dir="$work_dir/$pid"

# Valida caminhos de diretório
aux_1=$verbosity; verbosity='quiet'
aux_2=$interactive; interactive=false
valid "$bak_dir" "bak_dir" "\nErro. Diretório de backup informado incorretamente." &>> $error_log || exit 1
valid "$cgi_dir" "cgi_dir" "\nErro. Diretório de cgi informado incorretamente." &>> $error_log || exit 1
valid "$tmp_dir" "tmp_dir" "\nErro. Diretório temporário informado incorretamente." &>> $error_log || exit 1
valid "$history_dir" "history_dir" "\nErro. Diretório de histórico informado incorretamente." &>> $error_log || exit 1
valid "$repo_dir" "repo_dir" "\nErro. Diretório de repositórios git informado incorretamente." &>> $error_log || exit 1
valid "$lock_dir" "lock_dir" "\nErro. Diretório de lockfiles informado incorretamente." &>> $error_log || exit 1
verbosity=$aux_1
interactive=$aux_2

# Cria diretórios necessários, com exceção de $tmp_dir, que deve ser gerenciado individualmente por cada script
mkdir -p $cgi_dir $work_dir $history_dir ${app_history_dir_tree} $repo_dir $lock_dir $app_conf_dir $bak_dir &>> $error_log || exit 1

unset aux_1
unset aux_2
rm -f $error_log

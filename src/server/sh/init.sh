#!/bin/bash

# Carrega funções e variáveis comuns, define $PATH
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1

# Cria log de erros
mkdir -p $log_dir || exit 1
error_log=$log_dir/error.log
touch $error_log || exit 1

# Carrega valores default para o servidor
test -f "$install_dir/conf/global.conf" || exit 1
chk_template $install_dir/conf/global.conf &>> $error_log
source "$install_dir/conf/global.conf" &>> $error_log  || exit 1

# Carrega preferências do usuário
if [ -f "$install_dir/conf/user.conf" ]; then
    chk_template $install_dir/conf/user.conf &>> $error_log
    source "$install_dir/conf/user.conf" &>> $error_log || exit 1
fi

# Define diretório temporário.
pid=$$
tmp_dir="$work_dir/$pid"

# Valida caminhos de diretório
aux_1=$verbosity; verbosity='quiet'
aux_2=$interactive; interactive=false
valid "bak_dir" "\nErro. Diretório de backup informado incorretamente." &>> $error_log
valid "cgi_dir" "\nErro. Diretório de cgi informado incorretamente." &>> $error_log
valid "tmp_dir" "\nErro. Diretório temporário informado incorretamente." &>> $error_log
valid "history_dir" "\nErro. Diretório de histórico informado incorretamente." &>> $error_log
valid "repo_dir" "\nErro. Diretório de repositórios git informado incorretamente." &>> $error_log
valid "lock_dir" "\nErro. Diretório de lockfiles informado incorretamente." &>> $error_log
verbosity=$aux_1
interactive=$aux_2

# Cria diretórios necessários, com exceção de $tmp_dir, que deve ser gerenciado individualmente por cada script
mkdir -p $cgi_dir $work_dir $history_dir ${app_history_dir_tree} $repo_dir $lock_dir $app_conf_dir $bak_dir &>> $error_log || exit 1

unset aux_1
unset aux_2
rm -f $error_log

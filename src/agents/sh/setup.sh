#!/bin/bash

interactive='false'
verbosity='verbose'

function end() {

    if [ "$1" != '0' ]; then
        echo "ERRO. Instalação interrompida."
    fi

    exit $1

}

trap "end 1" SIGQUIT SIGINT SIGHUP SIGTERM

case "$1" in
    --reconfigure)
        echo "Reconfigurando agente..."
        $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/reconfigure.sh || end 1
        ;;
    '') echo "Configurando agente..."
        ;;
    *)  echo "Argumento inválido" && end 1
        ;;
esac

source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1

# Valida o arquivo global.conf e carrega configurações
global_conf="${install_dir}/conf/global.conf"
chk_template "$global_conf" 'global' && source "$global_conf" || end 1

error=false
valid "$work_dir" "tmp_dir" "\nErro. Diretório 'work' informado incorretamente." || error=true
valid "$log_dir" "log_dir" "\nErro. Diretório de lockfiles informado incorretamente." || error=true
valid "$lock_dir" "lock_dir" "\nErro. Diretório de lockfiles informado incorretamente." || error=true
valid "$remote_pkg_dir_tree" "remote_dir" "\nErro. Repositório de pacotes remoto informado incorretamente." || error=true
valid "$remote_log_dir_tree" "remote_dir" "\nErro. Repositório de logs remoto informado incorretamente." || error=true
valid "$remote_lock_dir" "remote_dir" "\nErro. Diretório de lockfiles remoto informado incorretamente." || error=true
valid "$remote_conf_dir" "remote_dir" "\nErro. Diretório de configurações remoto informado incorretamente." || error=true
valid "$remote_history_dir" "remote_dir" "\nErro. Diretório de histórico remoto informado incorretamente." || error=true
valid "$remote_app_history_dir_tree" "remote_dir" "\nErro. Diretório de histórico de aplicações remoto informado incorretamente." || error=true
$error && end 1

#backup agent
if [ -f $service_init_script ]; then
    cp -f $service_init_script $service_init_script.bak
    $service_init_script stop || end 1
fi

#setup agent
cp -f $install_dir/template/service.template $service_init_script || end 1
test -w $service_init_script || end 1
sed -i -r "s|@src_dir|$src_dir|" $service_init_script
sed -i -r "s|@log_dir|$log_dir|" $service_init_script
sed -i -r "s|@service_init_script|$service_init_script|" $service_init_script

#create directories
mkdir -p "$common_work_dir" || end 1
mkdir -p "$common_log_dir" || end 1
mkdir -p "$work_dir" || end 1
mkdir -p "$log_dir" || end 1
mkdir -p "$lock_dir" || end 1
mkdir -p "$remote_pkg_dir_tree" || end 1
mkdir -p "$remote_log_dir_tree" || end 1
mkdir -p "$remote_lock_dir" || end 1
mkdir -p "$remote_conf_dir" || end 1
mkdir -p "$remote_history_dir" || end 1
mkdir -p "$remote_app_history_dir_tree" || end 1

#setup owner/permissions
chmod 775 "$common_work_dir" || end 1
chmod 775 "$common_log_dir" || end 1
chmod 755 "$src_dir/common/sh/query_file.sh" || end 1
chmod 755 "$service_init_script" || end 1
chmod 775 "$work_dir" || end 1
chmod 775 "$log_dir" || end 1
chmod 775 "$lock_dir" || end 1
chmod 770 "$remote_pkg_dir_tree" || end 1
chmod 770 "$remote_log_dir_tree" || end 1
chmod 770 "$remote_lock_dir" || end 1
chmod 770 "$remote_conf_dir" || end 1
chmod 770 "$remote_history_dir" || end 1
chmod 770 "$remote_app_history_dir_tree" || end 1

#restart services
$service_init_script restart || end 1

echo "Instalação concluída."
end 0

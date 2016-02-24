#!/bin/bash
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/init.sh || exit 1

##### Execução somente como usuário root ######

if [ ! "$USER" == 'root' ]; then
    echo "Requer usuário root."
    exit 1
fi

lock 'deploy_service' 'O serviço já está em execução'

function start() {

    nohup $install_dir/sh/tasks &
    echo "Iniciando serviço de deploy..."

}

function force-stop() {

    pkill -9 "$install_dir/sh/tasks"

}

function stop() {

    pkill -f "$install_dir/sh/tasks" &

    local t=0
    while [ "$(pgrep -f "$install_dir/sh/tasks" | wc -l)" -ne 0 ]; do
        echo "Aguarde..."
        sleep 1
        ((t++))
        test "$1" ==  "$t" && force-stop
    done

    echo "Serviço encerrado."
}

case "$1" in
    'start') start ;;
    'restart') stop && start ;;
    'stop') stop ;;
    'force-stop') force-stop ;;
    *) echo "'$1':Argumento inválido." 1>&2 && exit 1
esac

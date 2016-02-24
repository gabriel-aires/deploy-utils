#!/bin/bash
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/init.sh || exit 1

lock_history=false
interactive=false
execution_mode="server"
verbosity="quiet"

function end {

    break 10 2> /dev/null
    trap "" SIGQUIT SIGTERM SIGINT SIGHUP
    erro=$1

    wait
    find $tmp_dir/ -maxdepth 1 -type f -iname 'deploy_*.log' | sort | xargs cat

    if [ -d $tmp_dir ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    clean_locks

    exit $erro

}

trap "end 1" SIGQUIT SIGTERM SIGINT SIGHUP

##################### Deploy em todos os ambientes #####################

if [ -z "$ambientes" ]; then
    echo 'Favor preencher corretamente o arquivo global.conf e tentar novamente.'
    exit 1
fi

lock 'deploy_auto' "Rotina de deploy automático em andamento..."
mklist "$ambientes" "$tmp_dir/lista_ambientes"
running=0

while read ambiente; do

    grep -REl "^auto_$ambiente='1'$" $app_conf_dir > $tmp_dir/lista_aplicacoes
    sed -i -r "s|^$app_conf_dir/(.+)\.conf$|\1|g" $tmp_dir/lista_aplicacoes

    if [ -n "$(cat $tmp_dir/lista_aplicacoes)" ]; then

        while read aplicacao; do

            seconds=$(date +%s)
            echo '' > $tmp_dir/deploy_$seconds.log
            log "INFO" "DEPLOY ($aplicacao $ambiente)\n" &>> $tmp_dir/deploy_$seconds.log
            nohup $install_dir/sh/deploy_pages.sh -f $aplicacao auto $ambiente &>> $tmp_dir/deploy_$seconds.log &
            sleep 1

            ((running++))
            if [ "$running" -eq "$max_running" ]; then
                wait
                find $tmp_dir/ -maxdepth 1 -type f -iname 'deploy_*.log' | sort | xargs cat
                rm -f $tmp_dir/*.log
            fi

        done < "$tmp_dir/lista_aplicacoes"

    else

        log "INFO" "O deploy automático não foi habilitado no ambiente '$ambiente'\n"

    fi

done < "$tmp_dir/lista_ambientes"

end 0

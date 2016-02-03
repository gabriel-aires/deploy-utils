#!/bin/bash
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/init.sh || exit 1

lock_history=false
interactive=false
execution_mode="server"
verbosity="quiet"

##### Execução somente como usuário root ######

if [ ! "$USER" == 'root' ]; then
    echo "Requer usuário root."
    exit 1
fi

#### Funções ####

function horario () {

    echo $(date "+%F %T"):

}

function cron_tasks () {

    ##################### Deploy em todos os ambientes #####################

    mklist "$ambientes" "$tmp_dir/lista_ambientes"

    while read ambiente; do
        grep -REl "^auto_$ambiente='1'$" $app_conf_dir > $tmp_dir/lista_aplicacoes
        sed -i -r "s|^$app_conf_dir/(.+)\.conf$|\1|g" $tmp_dir/lista_aplicacoes

        if [ ! -z "$(cat $tmp_dir/lista_aplicacoes)" ];then
                while read aplicacao; do
                horario
                echo ""
                /bin/bash $install_dir/sh/deploy_pages.sh -f $aplicacao auto $ambiente
                wait
                echo ""
            done < "$tmp_dir/lista_aplicacoes"
        else
            echo "$(horario) O deploy automático não foi habilitado no ambiente '$ambiente'"
            echo ""
        fi
    done < "$tmp_dir/lista_ambientes"

    ############################ Expurgo de logs ###########################

    ########## Valida variáveis que definem o tamanho de logs logs e quantidade de entradas no histórico.
    valid "cron_log_size" "regex_qtd" "\nErro. Tamanho inválido para o log de tarefas agendadas."
    valid "app_history_size" "regex_qtd" "\nErro. Tamanho inválido para o histórico de aplicações."
    valid "global_history_size" "regex_qtd" "\nErro. Tamanho inválido para o histórico global."
    valid "history_html_size" "regex_qtd" "\nErro. Tamanho inválido para o histórico em HTML."

    ########## Trava histórico assim que possível
    while [ -f "$lock_dir/$history_lock_file" ]; do
        sleep 1
    done

    lock_history=true
    touch $lock_dir/$history_lock_file

    ########## 1) cron
    touch $history_dir/$cron_log_file
    tail --lines=$cron_log_size $history_dir/$cron_log_file > $tmp_dir/cron_log_new
    cp -f $tmp_dir/cron_log_new $history_dir/$cron_log_file

    ########## 2) Histórico de deploys
    local qtd_history
    local qtd_purge

    if [ -f "$history_dir/$history_csv_file" ]; then
        qtd_history=$(cat "$history_dir/$history_csv_file" | wc -l)
        if [ $qtd_history -gt $global_history_size ]; then
            qtd_purge=$(($qtd_history - $global_history_size))
            sed -i "2,${qtd_purge}d" "$history_dir/$history_csv_file"
        fi
    fi

    ########## 3) logs de deploy de aplicações
    find ${app_history_dir_tree} -mindepth 1 -maxdepth 1 -type d > $tmp_dir/app_history_path
    while read path; do
        app_history_dir="${app_history_dir_tree}/$(basename $path)"
        find "${app_history_dir}/" -mindepth 1 -maxdepth 1 -type d | sort > $tmp_dir/logs_total
        tail $tmp_dir/logs_total --lines=${history_html_size} > $tmp_dir/logs_ultimos
        grep -vxF --file=$tmp_dir/logs_ultimos $tmp_dir/logs_total > $tmp_dir/logs_expurgo
        cat $tmp_dir/logs_expurgo | xargs --no-run-if-empty rm -Rf
    done < $tmp_dir/app_history_path

    ########## Destrava histórico
    rm -f $lock_dir/$history_lock_file
    lock_history=false

    end 0

}

function end {

    ##### Remove lockfile e diretório temporário ao fim da execução #####

    trap "" SIGQUIT SIGTERM SIGINT SIGHUP

    erro=$1
    wait

    if [ "$erro" == "0" ]; then
        echo -e "$(horario) Rotina concluída com sucesso.\n"
    else
        echo -e "$(horario) Rotina concluída com erro.\n"
    fi

    if [ -d $tmp_dir ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    if [ -f $lock_dir/server_cron_tasks ]; then
        rm -f "$lock_dir/server_cron_tasks"
    fi

    if $lock_history; then
        rm -f "$lock_dir/$deploy_log_edit"
    fi

    unix2dos $history_dir/$cron_log_file > /dev/null 2>&1

    exit $erro

}

#### Inicialização #####

if [ -z "$ambientes" ]; then
    echo 'Favor preencher corretamente o arquivo global.conf e tentar novamente.'
    exit 1
fi

if [ -f $lock_dir/server_cron_tasks ]; then
    echo -e "O script de deploy automático já está em execução." && exit 0
else
    touch $lock_dir/server_cron_tasks
    mkdir -p $tmp_dir
fi

trap "end 1" SIGQUIT SIGTERM SIGINT SIGHUP

######## Execução da rotina ########

cron_tasks >> $history_dir/$cron_log_file 2>&1

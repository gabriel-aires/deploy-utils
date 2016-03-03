#!/bin/bash
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

lock_history=false
interactive=false
execution_mode="server"
verbosity="quiet"
pid="$$"

##### Execução somente como usuário root ######

if [ ! "$USER" == 'root' ]; then
    echo "Requer usuário root."
    exit 1
fi

#### Funções ####

function tasks () {

    mkdir -p $tmp_dir

    ### Processar fila de deploys

    auto_running=$(pgrep -f $install_dir/sh/deploy_auto.sh | wc -l)
    test "$auto_running" -eq 0 && $install_dir/sh/deploy_auto.sh &

    ### Expurgo de logs

    while [ -f "$lock_dir/$history_lock_file" ]; do
        sleep 0.001
    done

    lock_history=true
    touch $lock_dir/$history_lock_file

    # 1) Serviço
    touch $history_dir/$service_log_file
    tail --lines=$service_log_size $history_dir/$service_log_file > $tmp_dir/service_log_new
    cp -f $tmp_dir/service_log_new $history_dir/$service_log_file

    # 2) Histórico de deploys
    local qtd_history
    local qtd_purge

    if [ -f "$history_dir/$history_csv_file" ]; then
        qtd_history=$(cat "$history_dir/$history_csv_file" | wc -l)
        if [ $qtd_history -gt $global_history_size ]; then
            qtd_purge=$(($qtd_history - $global_history_size))
            sed -i "2,${qtd_purge}d" "$history_dir/$history_csv_file"
        fi
    fi

    # 3) logs de deploy de aplicações
    find ${app_history_dir_tree} -mindepth 1 -maxdepth 1 -type d > $tmp_dir/app_history_path
    while read path; do
        app_history_dir="${app_history_dir_tree}/$(basename $path)"
        find "${app_history_dir}/" -mindepth 1 -maxdepth 1 -type d | sort > $tmp_dir/logs_total
        tail $tmp_dir/logs_total --lines=${app_log_max} > $tmp_dir/logs_ultimos
        grep -vxF --file=$tmp_dir/logs_ultimos $tmp_dir/logs_total > $tmp_dir/logs_expurgo
        cat $tmp_dir/logs_expurgo | xargs --no-run-if-empty rm -Rf
    done < $tmp_dir/app_history_path

    # Remove arquivos temporários
    rm -f $tmp_dir/*
    rmdir $tmp_dir

    # Destrava histórico de deploy
    rm -f $lock_dir/$history_lock_file
    lock_history=false

}

function end {

    trap "" SIGQUIT SIGTERM SIGINT SIGHUP
    erro=$1

    break 10 2> /dev/null
    wait

    if [ -d $tmp_dir ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    clean_locks

    return $erro

}

trap "end 1" SIGQUIT SIGTERM SIGINT SIGHUP

lock 'server_tasks' "A rotina já está em execução."

valid "service_log_size" "regex_qtd" "\nErro. Tamanho inválido para o log de tarefas agendadas."
valid "app_log_max" "regex_qtd" "\nErro. Valor inválido para a quantidade de logs de aplicações."
valid "global_history_size" "regex_qtd" "\nErro. Tamanho inválido para o histórico global."

case "$1" in
    --test)
        tasks
        ;;
    --daemon)
        while true; do
            sleep 1
            touch $history_dir/$service_log_file
            tasks &>> $history_dir/$service_log_file
        done
        ;;
    *)
        echo "Utilização: $0 [opções]"
        echo "Opções:"
        echo "  --test: executa a rotina uma vez, exibindo a saída em stdout."
        echo "  --daemon: permite a execução como daemon, redirecionando a saída para um arquivo de log."
        ;;
esac

end 0

#!/bin/bash
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1

lock_history=false
interactive=false
execution_mode="agent"
verbosity="quiet"
running=0
pid="$$"

##### Execução somente como usuário root ######

if [ "$(id -u)" -ne "0" ]; then
    echo "Requer usuário root."
    exit 1
fi

#### Funções ####

function async_agent() {

    test "$#" -eq "2" || return 1
    test -d "$tmp_dir" || return 1
    test -z "$1" || return 1
    test -f "$2" || return 1

    local agent_task="$1"
    local agent_conf="$2"
    local agent_name="$(grep -Ex "agent_name=$regex_agent_name" | cut -d '=' -f2)"
    local agent_wait="$(grep -Ex "${task}_interval=$regex_qtd" | cut -d '=' -f2)"

    test -n "$agent_name" || return 1
    test -n "$agent_wait" || return 1

    local agent_lock="$tmp_dir/${agent_name}_${agent_task}_$(basename "$agent_conf" | cut -d '.' -f1)"
    local agent_cmd="$install_dir/sh/run_agent.sh '$agent_name' '$agent_task' '$agent_conf'"
    local current_time="$(date +%s)"
    local miliseconds=$(date +%s%3N)

    if [ -f "$agent_lock" ]; then
        start_time="$(cat "$agent_lock")"
        test "$((current_time-start_time))" -gt "$agent_wait" && test -z $(pgrep -f "$agent_cmd") && rm -f $agent_lock
        test "$((current_time-start_time))" -gt "$agent_timoeut" && test -n $(pgrep -f "$agent_cmd") && $(pkill -f "$agent_cmd") && rm -f $agent_lock
    else
        echo "$current_time" > "$agent_lock"
        log "INFO" "RUN_AGENT (name:$agent_name task:$agent_task conf:$agent_conf)\n" &> $tmp_dir/agent_$miliseconds.log
        nohup $agent_cmd &>> $tmp_dir/agent_$miliseconds.log &
        ((running++))
        if [ "$running" -eq "$max_running" ]; then
            wait
            running=0
            find $tmp_dir/ -maxdepth 1 -type f -iname 'agent_*.log' | sort | xargs cat >> $log
            rm -f $tmp_dir/*.log
        fi
    fi

    sleep 0.005
    return 0

}


function end {

    break 10 2> /dev/null
    trap "" SIGQUIT SIGTERM SIGINT SIGHUP
    erro=$1

    if [ -f "$log" ]; then
        wait
        find $tmp_dir/ -maxdepth 1 -type f -iname 'agent_*.log' | sort | xargs cat >> $log
    fi

    if [ -d $tmp_dir ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    clean_locks

    exit $erro

}

trap "end 1" SIGQUIT SIGTERM SIGINT SIGHUP

lock 'agent_tasks' "A rotina já está em execução."

# cria diretório temporário
tmp_dir="$work_dir/$pid"
valid 'tmp_dir' "'$tmp_dir': Caminho inválido para armazenamento de diretórios temporários" && mkdir -p $tmp_dir

function tasks () {

    ### Validação / Expurgo de logs ###

    valid "remote_conf_dir" "regex_remote_dir" "Diretório de configuração de agentes inválido"
    mkdir -p "$remote_conf_dir"

    valid 'log_dir' "'$log_dir': Caminho inválido para o diretório de armazenamento de logs"
    log="$log_dir/service_$(date +%F).log"
    mkdir -p $log_dir && touch $log
    echo "" >> $log
    find $log_dir -type f -iname "service_*.log" | grep -v $(date "+%Y-%m") | xargs rm -f

    ### Execução de agentes ###

    # Deploys
    grep -RExl "run_deploy_agent='true'" $remote_conf_dir/* > $tmp_dir/deploy_enabled.list
    while read deploy_conf; do
        async_agent "deploy" "$deploy_conf"
    done < $tmp_dir/deploy_enabled.list

    # Logs
    grep -RExl "run_log_agent='true'" $remote_conf_dir/* > $tmp_dir/log_enabled.list
    while read log_conf; do
        async_agent "log" "$log_conf"
    done < $tmp_dir/log_enabled.list

}

case "$1" in
    --test)
        tasks
        ;;
    --daemon)
        while true; do
            sleep 1
            tasks
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

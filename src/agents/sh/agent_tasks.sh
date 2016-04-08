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
    test -n "$1" || return 1
    test -f "$2" || return 1

    local agent_task="$1"
    local agent_conf="$2"
    local agent_name="$(grep -Ex "agent_name=[\"']?$regex_agent_name[\"']?" "$agent_conf" | cut -d '=' -f2 | sed -r "s/'//g" | sed -r 's/"//g')"
    local agent_wait="$(grep -Ex "${agent_task}_interval=[\"']?$regex_qtd[\"']?" "$agent_conf" | cut -d '=' -f2 | sed -r "s/'//g" | sed -r 's/"//g')"

    test -n "$agent_name" || return 1
    test -n "$agent_wait" || return 1

    local agent_lock="$tmp_dir/${agent_name}_${agent_task}_$(basename "$agent_conf" | cut -d '.' -f1)"
    local agent_cmd="$install_dir/sh/run_agent.sh $agent_name $agent_task $agent_conf"
    local current_time="$(date +%s)"
    local miliseconds=$(date +%s%3N)

    if [ -f "$agent_lock" ]; then
        start_time="$(cat "$agent_lock")"
        test "$((current_time-start_time))" -ge "$agent_wait" && test -z "$(pgrep -f "$agent_cmd")" && rm -f $agent_lock
        test "$((current_time-start_time))" -ge "$agent_timeout" && test -n "$(pgrep -f "$agent_cmd")" && pkill -f "$agent_cmd" && rm -f $agent_lock
    fi

    if [ ! -f "$agent_lock" ]; then
        echo "$current_time" > "$agent_lock"
        echo "" > $tmp_dir/agent_$miliseconds.log
        log "INFO" "RUN_AGENT (name:$agent_name task:$agent_task conf:$agent_conf)\n" &>> $tmp_dir/agent_$miliseconds.log
        nohup $agent_cmd &>> $tmp_dir/agent_$miliseconds.log &
        ((running++))
        if [ "$running" -eq "$max_running" ]; then
            wait
            running=0
            find $tmp_dir/ -maxdepth 1 -type f -iname 'agent_*.log' | sort | xargs cat
            rm -f $tmp_dir/*.log
        fi
    fi

    sleep 0.1
    return 0

}

function end {

    break 10 2> /dev/null
    trap "" SIGQUIT SIGTERM SIGINT SIGHUP
    erro=$1

    if [ -f "$log" ]; then
        wait
        find $tmp_dir/ -maxdepth 1 -type f -iname 'agent_*.log' | sort | xargs cat
    fi

    if [ -d $tmp_dir ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    clean_locks

    exit $erro

}

trap "end 1" SIGQUIT SIGTERM SIGINT SIGHUP

# Verifica o arquivo global.conf e carrega configurações
global_conf="${install_dir}/conf/global.conf"
test -f "$global_conf" || exit 1
chk_template "$global_conf"
source "$global_conf" || exit 1

# Validações
tmp_dir="$work_dir/$pid"
valid 'tmp_dir' "'$tmp_dir': Caminho inválido para armazenamento de diretórios temporários"
valid "remote_conf_dir" "regex_remote_dir" "Diretório de configuração de agentes inválido"
valid "remote_lock_dir" "regex_remote_dir" "Diretório de lockfiles remoto inválido"
valid 'log_dir' "'$log_dir': Caminho inválido para o diretório de armazenamento de logs"
valid 'lock_dir' "'$lock_dir': Caminho inválido para o diretório de lockfiles"
valid "max_running" "regex_qtd" "Valor inválido para a quantidade máxima de tarefas simultâneas"
valid "agent_timeout" "regex_qtd" "Valor inválido para o timeout de tarefas global"
valid "service_log_size" "regex_qtd" "Valor inválido para o tamanho máximo do log do agente"

mkdir -p "$tmp_dir" "$remote_conf_dir" "$remote_lock_dir" "$log_dir" "$lock_dir" || end 1
lock 'agent_tasks' "A rotina já está em execução."
log="$log_dir/service.log" && touch "$log"
host="$(echo $HOSTNAME | cut -d '.' -f1)"

function tasks () {

    test -f "$remote_lock_dir/edit_agent_$host" && return 1
    test -d "$remote_conf_dir/$host/" || return 1
    touch "$log" || return 1

    # Expurgo de log
    local qtd_log=$(cat "$log" | wc -l)
    local qtd_purge=$((qtd_log - service_log_size))
    test $qtd_purge -gt 0 && sed -i 1,"$qtd_purge"d "$log"

    # Deploys
    grep -RExl "run_deploy_agent=[\"']?true[\"']?" "$remote_conf_dir/$host/" > $tmp_dir/deploy_enabled.list
    while read deploy_conf; do
        async_agent "deploy" "$deploy_conf"
    done < $tmp_dir/deploy_enabled.list

    # Logs
    grep -RExl "run_log_agent=[\"']?true[\"']?" "$remote_conf_dir/$host/" > $tmp_dir/log_enabled.list
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
            tasks &>> $log
            sleep 5
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

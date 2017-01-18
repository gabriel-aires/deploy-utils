#!/bin/bash

function wildfly_script_init () {

    ##### LOCALIZA SCRIPT DE INICIALIZAÇÃO DA INSTÂNCIA wildfly #####

    local wildfly_instance=$1
    local wildfly_home
    local wildfly_server_base_dir

    if [ -n "$wildfly_instance" ] && [ -d  "$wildfly_servers_dir/$wildfly_instance" ]; then

        unset script_init
        find /etc/init.d/ -type f -iname '*wildfly*' > "$tmp_dir/scripts_wildfly.list"

        #verifica todos os scripts de wildfly encontrados em /etc/init.d até localizar o correto.
        while read script_wildfly && [ -z "$script_init" ]; do

            #verifica se o script corresponde à instalação correta do wildfly e se aceita os argumentos 'start' e 'stop'
            test -n "$(grep -E '^([^[:graph:]])+?start[^A-Za-z0-9_-]?' "$script_wildfly" | head -1)" || continue
            test -n "$(grep -E '^([^[:graph:]])+?stop[^A-Za-z0-9_-]?' "$script_wildfly" | head -1)" || continue
            test -n "$(grep -F "$wildfly_servers_dir" "$script_wildfly" | grep -Ev "^[[:blank:]]*#" | head -1)" || continue

            wildfly_server_base_dir="$(sed -rn "s/^.*-Djboss\.server\.base\.dir=([[:graph:]]+)[[:blank:]]*$/\1/p" "$script_wildfly" | tr -d \"\' | head -1)"

            if [ -n "$wildfly_server_base_dir" ]; then

                test "$wildfly_server_base_dir" == "$wildfly_servers_dir/$wildfly_instance" && script_init="$script_wildfly"                

            elif [ "$wildfly_instance" == 'standalone' ]; then

                wildfly_home="$(sed -rn "s/^[[:blank:]]*JBOSS_HOME=([[:graph:]]+)[[:blank:]]*$/\1/p" "$script_wildfly" | tr -d \"\' | head -1)"
                test "$wildfly_home" == "$wildfly_servers_dir" && script_init="$script_wildfly"                

            fi

        done < "$tmp_dir/scripts_wildfly.list"

    else
        log "ERRO" "Parâmetros incorretos ou instância wildfly não encontrada."
    fi

}

function file_operations () {

    cp -f "$pkg" "$old" || error=true

    if $error; then
        log "ERRO" "Impossível sobrescrever o pacote $(basename $old)."
        write_history "Deploy não concluído. Impossível sobrescrever o pacote $(basename $old) na instância $wildfly_instance." "1"
        return 1
    fi

    chown -R wildfly:wildfly $wildfly_deployments_dir/ || error=true

    if $error; then
        log "ERRO" "Impossível atribuir uid/gid aos arquivos no diretório de deploy."
        write_history "Deploy não concluído. Impossível atribuir uid/gid ao diretório 'deployments' na instância $wildfly_instance." "1"
        return 1
    fi

    return 0
}

function deploy_pkg () {

    ####### deploy #####

    find $wildfly_servers_dir -type f -regextype posix-extended -iregex "$wildfly_servers_dir/[^/]+/deployments/$app\.[ew]ar" > "$tmp_dir/old.list"

    if [ $( cat "$tmp_dir/old.list" | wc -l ) -eq 0 ]; then
        log "ERRO" "Deploy abortado. Não foi encontrado pacote anterior. O deploy deverá ser feito manualmente."
        write_history "Deploy abortado. Pacote anterior não encontrado." "0"
        rm -f $pkg
        return 1
    fi

    while read old; do

        error=false
        log "INFO" "O pacote $old será substituído".

        wildfly_deployments_dir=$(echo $old | sed -r "s|^(${wildfly_servers_dir}/[^/]+/deployments)/[^/]+\.[ew]ar$|\1|i")
        wildfly_instance=$(echo $old | sed -r "s|^${wildfly_servers_dir}/([^/]+)/deployments/[^/]+\.[ew]ar$|\1|i")
        wildfly_temp="$wildfly_servers_dir/$wildfly_instance/tmp"
        wildfly_temp=$(find $wildfly_servers_dir -iwholename $wildfly_temp)

        log "INFO" "Instância do wildfly:     \t$wildfly_instance"
        log "INFO" "Diretório de deploy:    \t$wildfly_deployments_dir"

        if $restart_required; then

            #tenta localizar o script de inicialização da instância e seta a variável $script_init, caso tenha sucesso
            wildfly_script_init "$wildfly_instance"

            if [ -z "$script_init" ]; then
                log "ERRO" "Não foi encontrado o script de inicialização da instância wildfly. O deploy deverá ser feito manualmente."
                write_history "Deploy abortado. Script de inicialização não encontrado." "0"
                continue
            fi
            
            log "INFO" "Script de inicialização:\t$script_init"
            stop_instance="timeout -s KILL $((agent_timeout/2)) $script_init stop"
            start_instance="timeout -s KILL $((agent_timeout/2)) $script_init start"

            $stop_instance

            if [ $? -ne 0 ] || [ $(pgrep -f "\-Djboss\.server\.base\.dir=$wildfly_servers_dir/$wildfly_instance \-c standalone\.xml" | wc -l) -ne 0 ]; then
                log "ERRO" "Não foi possível parar a instância $wildfly_instance do wildfly. Deploy abortado."
                write_history "Deploy abortado. Impossível parar a instância $wildfly_instance." "0"
                continue
            fi

            file_operations || { sleep "$restart_delay" ; $start_instance ; continue ; }
            
            if [ -d "$wildfly_temp" ]; then
                rm -Rf $wildfly_temp/*
            fi

            sleep "$restart_delay"
            $start_instance

            if [ $? -ne 0 ] || [ $(pgrep -f "\-Djboss\.server\.base\.dir=$wildfly_servers_dir/$wildfly_instance \-c standalone\.xml" | wc -l) -eq 0 ]; then
                log "ERRO" "O deploy do arquivo $war foi concluído, porém não foi possível reiniciar a instância do wildfly."
                write_history "Deploy não concluído. Erro ao reiniciar a instância $wildfly_instance." "0"
                continue
            fi

            sleep 1

        else

            file_operations || continue
            sleep "$deployment_delay"

        fi

        t=0      
        log "INFO" "Wildfly - realizando deploy do pacote $(basename $pkg) na instância $wildfly_instance..."

        while [ -f "$old.isdeploying" ]; do
            
            sleep 1

            if [ $((++t)) -gt "$((agent_timeout/2))" ]; then
                log "ERRO" "Wildfly - timeout atingido no deploy do pacote $(basename $pkg) na instância $wildfly_instance:"
                write_history "Deploy abortado. Wildfly - timeout atingido no deploy do pacote $(basename $pkg) na instância $wildfly_instance." "0"
                continue 2            
            else
                log "INFO" "Wildfly - realizando deploy do pacote $(basename $pkg) na instância $wildfly_instance..."
            fi

        done

        if [ -f "$old.failed" ]; then
            log "ERRO" "Wildfly - erro no deploy do pacote $(basename $pkg) na instância $wildfly_instance:"
            cat "$old.failed"
            write_history "Deploy abortado. Wildfly - erro no deploy do pacote $(basename $pkg) na instância $wildfly_instance." "0"
            continue
        fi

        log "INFO" "Deploy do arquivo $war concluído com sucesso!"
        write_history "Deploy concluído com sucesso na instância $wildfly_instance." "1"

    done < "$tmp_dir/old.list"

    rm -f $pkg
    return 0

}

function copy_log () {

    ######## LOGS #########

    log "INFO" "Copiando logs da rotina e das instâncias wildfly em '$wildfly_servers_dir'..."

    rm -f "$tmp_dir/app_origem.list"
    find $wildfly_servers_dir -type f -regextype posix-extended -iregex "$wildfly_servers_dir/[^/]+/deployments/$app\.[ew]ar" > "$tmp_dir/app_origem.list" 2> /dev/null

    if [ $(cat "$tmp_dir/app_origem.list" | wc -l) -eq 0 ]; then
        log "ERRO" "A aplicação $app não foi encontrada."
        return 1
    fi

    while read app_path; do

        wildfly_instance=$(echo $app_path | sed -r "s|^${wildfly_servers_dir}/([^/]+)/deployments/[^/]+\.[ew]ar$|\1|")
        server_log=$(find "${wildfly_servers_dir}/${wildfly_instance}" -iwholename "${wildfly_servers_dir}/${wildfly_instance}/log/server.log" 2> /dev/null)

        if [ $(echo $server_log | wc -l) -ne 1 ]; then
            log "ERRO" "Não há logs da instância wildfly correspondente à aplicação $app."
            continue
        fi

        log "INFO" "Copiando logs da aplicação $app no diretório $(dirname $server_log)..."
        cd $(dirname $server_log); zip -rql1 ${shared_log_dir}/${wildfly_instance}.zip *; cd - > /dev/null
        cp -f $server_log "$shared_log_dir/server_${wildfly_instance}.log"
        unix2dos "$shared_log_dir/server_${wildfly_instance}.log" > /dev/null 2>&1

    done < "$tmp_dir/app_origem.list"

    return 0

}

# Validar variáveis específicas
[ -d "$wildfly_servers_dir" ] || { log "ERRO" "O parâmetro 'wildfly_servers_dir' deve ser um diretório válido." && exit 1 ; }
[ "$restart_required" == "true" ] || [ "$restart_required" == "false" ] || { log "ERRO" "O parâmetro 'restart_required' deve ser um valor booleano (true/false)." && exit 1 ; }
[ "$restart_delay" -ge "0" ] 2> /dev/null || { log "ERRO" "O parâmetro 'restart_delay' deve ser um inteiro maior ou igual a zero." && exit 1 ; }
[ "$deployment_delay" -ge "0" ] 2> /dev/null || { log "ERRO" "O parâmetro 'deployment_delay' deve ser um inteiro maior ou igual a zero." && exit 1 ; }

case $1 in
    log) copy_log;;
    deploy) deploy_pkg;;
    *) log "ERRO" "O script somente admite os parâmetros 'deploy' ou 'log'.";;
esac

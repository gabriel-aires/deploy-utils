#!/bin/bash

function jboss_script_init () {

    ##### LOCALIZA SCRIPT DE INICIALIZAÇÃO DA INSTÂNCIA jboss #####

    local jboss_instance=$1
    local jboss_home
    local jboss_server_base_dir

    if [ -n "$jboss_instance" ] && [ -d  "$jboss_servers_dir/$jboss_instance" ]; then

        unset script_init
        find /etc/init.d/ -type f -iname '*jboss*' > "$tmp_dir/scripts_jboss.list"

        #verifica todos os scripts de jboss encontrados em /etc/init.d até localizar o correto.
        while read script_jboss && [ -z "$script_init" ]; do

            #verifica se o script corresponde à instalação correta do jboss e se aceita os argumentos 'start' e 'stop'
            test -n "$(grep -E '^([^[:graph:]])+?start[^A-Za-z0-9_-]?' "$script_jboss" | head -1)" || continue
            test -n "$(grep -E '^([^[:graph:]])+?stop[^A-Za-z0-9_-]?' "$script_jboss" | head -1)" || continue
            test -n "$(grep -F "$jboss_servers_dir" "$script_jboss" | grep -Ev "^[[:blank:]]*#" | head -1)" || continue

            jboss_server_base_dir="$(sed -rn "s/^.*-Djboss\.server\.base\.dir=([[:graph:]]+)[[:blank:]]*$/\1/p" "$script_jboss" | tr -d \"\' | head -1)"

            if [ -n "$jboss_server_base_dir" ]; then

                test "$jboss_server_base_dir" == "$jboss_servers_dir/$jboss_instance" && script_init="$script_jboss"                

            elif [ "$jboss_instance" == 'standalone' ]; then

                jboss_home="$(sed -rn "s/^[[:blank:]]*JBOSS_HOME=([[:graph:]]+)[[:blank:]]*$/\1/p" "$script_jboss" | tr -d \"\' | head -1)"
                test "$jboss_home" == "$jboss_servers_dir" && script_init="$script_jboss"                

            fi

        done < "$tmp_dir/scripts_jboss.list"

    else
        log "ERRO" "Parâmetros incorretos ou instância jboss não encontrada."
    fi

}

function file_operations () {

    cp -f "$pkg" "$old" || error=true

    if $error; then
        log "ERRO" "Impossível sobrescrever o pacote $(basename $old)."
        write_history "Deploy não concluído. Impossível sobrescrever o pacote $(basename $old) na instância $jboss_instance." "1"
        return 1
    fi

    chown -R "$jboss_uid":"$jboss_gid" $jboss_deployments_dir/ || error=true

    if $error; then
        log "ERRO" "Impossível atribuir uid/gid aos arquivos no diretório de deploy."
        write_history "Deploy não concluído. Impossível atribuir uid/gid ao diretório 'deployments' na instância $jboss_instance." "1"
        return 1
    fi

    return 0
}

function deploy_pkg () {

    ####### deploy #####

    find $jboss_servers_dir -type f -regextype posix-extended -iregex "$jboss_servers_dir/[^/]+/deployments/$app\.[ew]ar" > "$tmp_dir/old.list"

    if [ $( cat "$tmp_dir/old.list" | wc -l ) -eq 0 ]; then
        log "ERRO" "Deploy abortado. Não foi encontrado pacote anterior. O deploy deverá ser feito manualmente."
        write_history "Deploy abortado. Pacote anterior não encontrado." "0"
        rm -f $pkg
        return 1
    fi

    while read old; do

        error=false
        log "INFO" "O pacote $old será substituído".

        jboss_deployments_dir=$(echo $old | sed -r "s|^(${jboss_servers_dir}/[^/]+/deployments)/[^/]+\.[ew]ar$|\1|i")
        jboss_instance=$(echo $old | sed -r "s|^${jboss_servers_dir}/([^/]+)/deployments/[^/]+\.[ew]ar$|\1|i")
        jboss_temp="$jboss_servers_dir/$jboss_instance/tmp"
        jboss_temp=$(find $jboss_servers_dir -iwholename $jboss_temp)

        log "INFO" "Instância do jboss:     \t$jboss_instance"
        log "INFO" "Diretório de deploy:    \t$jboss_deployments_dir"

        if $restart_required; then

            #tenta localizar o script de inicialização da instância e seta a variável $script_init, caso tenha sucesso
            jboss_script_init "$jboss_instance"

            if [ -z "$script_init" ]; then
                log "ERRO" "Não foi encontrado o script de inicialização da instância jboss. O deploy deverá ser feito manualmente."
                write_history "Deploy abortado. Script de inicialização não encontrado." "0"
                continue
            fi
            
            log "INFO" "Script de inicialização:\t$script_init"
            stop_instance="timeout -s KILL $((agent_timeout/2)) $script_init stop"
            start_instance="timeout -s KILL $((agent_timeout/2)) $script_init start"

            $stop_instance

            if [ $? -ne 0 ] || [ $(pgrep -f "\-Djboss\.server\.base\.dir=$jboss_servers_dir/$jboss_instance \-c standalone\.xml" | wc -l) -ne 0 ]; then
                log "ERRO" "Não foi possível parar a instância $jboss_instance do jboss. Deploy abortado."
                write_history "Deploy abortado. Impossível parar a instância $jboss_instance." "0"
                continue
            fi

            file_operations || { sleep "$restart_delay" ; $start_instance ; continue ; }
            
            if [ -d "$jboss_temp" ]; then
                rm -Rf $jboss_temp/*
            fi

            sleep "$restart_delay"
            $start_instance

            if [ $? -ne 0 ] || [ $(pgrep -f "\-Djboss\.server\.base\.dir=$jboss_servers_dir/$jboss_instance \-c standalone\.xml" | wc -l) -eq 0 ]; then
                log "ERRO" "O deploy do arquivo $war foi concluído, porém não foi possível reiniciar a instância do jboss."
                write_history "Deploy não concluído. Erro ao reiniciar a instância $jboss_instance." "0"
                continue
            fi

            sleep 1

        else

            file_operations || continue
            sleep "$deployment_delay"

        fi

        t=0      
        log "INFO" "Jboss - realizando deploy do pacote $(basename $old) na instância $jboss_instance..."

        while [ -f "$old.isdeploying" ]; do
            
            sleep 1

            if [ $((++t)) -gt "$((agent_timeout/2))" ]; then
                log "ERRO" "Jboss - timeout atingido no deploy do pacote $(basename $old) na instância $jboss_instance:"
                write_history "Deploy abortado. Jboss - timeout atingido no deploy do pacote $(basename $old) na instância $jboss_instance." "0"
                continue 2            
            else
                log "INFO" "Jboss - realizando deploy do pacote $(basename $old) na instância $jboss_instance..."
            fi

        done

        if [ -f "$old.failed" ]; then
            log "ERRO" "Jboss - erro no deploy do pacote $(basename $old) na instância $jboss_instance:"
            cat "$old.failed"
            write_history "Deploy abortado. Jboss - erro no deploy do pacote $(basename $old) na instância $jboss_instance." "0"
            continue
        fi

        log "INFO" "Deploy do arquivo $war concluído com sucesso!"
        write_history "Deploy concluído com sucesso na instância $jboss_instance." "1"

    done < "$tmp_dir/old.list"

    rm -f $pkg
    return 0

}

function copy_log () {

    ######## LOGS #########

    log "INFO" "Copiando logs da rotina e das instâncias jboss em '$jboss_servers_dir'..."

    rm -f "$tmp_dir/app_origem.list"
    find $jboss_servers_dir -type f -regextype posix-extended -iregex "$jboss_servers_dir/[^/]+/deployments/$app\.[ew]ar" > "$tmp_dir/app_origem.list" 2> /dev/null

    if [ $(cat "$tmp_dir/app_origem.list" | wc -l) -eq 0 ]; then
        log "ERRO" "A aplicação $app não foi encontrada."
        return 1
    fi

    while read app_path; do

        jboss_instance=$(echo $app_path | sed -r "s|^${jboss_servers_dir}/([^/]+)/deployments/[^/]+\.[ew]ar$|\1|")
        server_log=$(find "${jboss_servers_dir}/${jboss_instance}" -iwholename "${jboss_servers_dir}/${jboss_instance}/log/server.log" 2> /dev/null)

        if [ $(echo $server_log | wc -l) -ne 1 ]; then
            log "ERRO" "Não há logs da instância jboss correspondente à aplicação $app."
            continue
        fi

        log "INFO" "Copiando logs da aplicação $app no diretório $(dirname $server_log)..."
        cd $(dirname $server_log); zip -rql1 ${shared_log_dir}/${jboss_instance}.zip *; cd - > /dev/null
        cp -f $server_log "$shared_log_dir/server_${jboss_instance}.log"
        unix2dos "$shared_log_dir/server_${jboss_instance}.log" > /dev/null 2>&1

    done < "$tmp_dir/app_origem.list"

    return 0

}

# Validar variáveis específicas
id -un "$jboss_uid" &> /dev/null || { log "ERRO" "O parâmetro 'jboss_uid' deve ser um usuário válido." && exit 1 ; }
id -Gn "$jboss_uid" | grep -Exq "$jboss_gid|.* $jboss_gid|$jboss_gid .*|.* $jboss_gid .*" || { log "ERRO" "O parâmetro 'jboss_gid' deve ser um grupo válido." && exit 1 ; }
[ -d "$jboss_servers_dir" ] || { log "ERRO" "O parâmetro 'jboss_servers_dir' deve ser um diretório válido." && exit 1 ; }
[ "$restart_required" == "true" ] || [ "$restart_required" == "false" ] || { log "ERRO" "O parâmetro 'restart_required' deve ser um valor booleano (true/false)." && exit 1 ; }
[ "$restart_delay" -ge "0" ] 2> /dev/null || { log "ERRO" "O parâmetro 'restart_delay' deve ser um inteiro maior ou igual a zero." && exit 1 ; }
[ "$deployment_delay" -ge "0" ] 2> /dev/null || { log "ERRO" "O parâmetro 'deployment_delay' deve ser um inteiro maior ou igual a zero." && exit 1 ; }

case $1 in
    log) copy_log;;
    deploy) deploy_pkg;;
    *) log "ERRO" "O script somente admite os parâmetros 'deploy' ou 'log'.";;
esac

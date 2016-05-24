#!/bin/bash

# TODO: adicionar suporte a wildfly 8 standalone.

function deploy_pkg () {

    # Caso o host seja domain controller, verificar se a aplicação $app já foi implantada.
    if [ "$HOSTNAME" == "$controller_hostname" ] || [ "$(echo $HOSTNAME | cut -f1 -d '.')" == "$controller_hostname" ]; then

        app_deployed="$($wildfly_cmd --command="deployment-info --server-group=*" | grep "$app.$ext")"
        app_srvgroup="$($wildfly_cmd --command="deployment-info --name=$app.$ext" | grep "enabled" | cut -f1 -d ' ')"

        if [ -n "$app_deployed" ]; then

            log "INFO" "Iniciando processo de deploy da aplicação $app..."

            echo "$app_srvgroup" | while read group; do

                log "INFO" "Removendo a aplicação $app do grupo $group..."
                $wildfly_cmd --command="undeploy $app.$ext --server-groups=$group"
                if [ "$?" -ne "0" ]; then
                    log "ERRO" "Falha ao remover a aplicação $app.$ext do server-group $group"
                    write_history "Falha ao remover a aplicação $app.$ext do server-group $group" "0"
                    continue
                fi

                log "INFO" "Implantando a nova versão da aplicação $app no grupo $group"
                $wildfly_cmd --command="deploy $pkg --name=$app.$ext --server-groups=$group"
                if [ "$?" -ne "0" ]; then
                    log "ERRO" "Falha ao implantar a aplicação $app.$ext no server-group $group"
                    write_history "Falha ao implantar a aplicação $app.$ext no server-group $group" "0"
                    continue
                fi

                log "INFO" "Deploy do arquivo $pkg realizado com sucesso no server-group '$group'"
                write_history "Deploy concluído com sucesso no grupo '$group'" "1"

            done

        else
            log "ERRO" "A aplicação $app não foi localizada pelo domain controller ($controller_hostname:$controller_port)"
            write_history "A aplicação $app não foi localizada pelo domain controller" "0"
            exit 1
        fi

        # finalizado o deploy, remover pacote do diretório de origem
        rm -f $pkg

    else
        log "ERRO" "O deploy deve ser realizado através domain controller ($controller_host)"
        write_history "O deploy deve ser realizado através domain controller ($controller_host)" "0"
        exit 1
    fi
}

function copy_log () {

    log "INFO" "Buscando logs da aplicação $app..."

    # verificar se a aplicação $app está implantada no domínio.
    app_deployed="$($wildfly_cmd --command="deployment-info --server-group=*" | cut -f1 -d ' ' | grep -Ex "$app\..+")"
    app_srvgroup="$($wildfly_cmd --command="deployment-info --name=$app_deployed" | grep "enabled" | cut -f1 -d ' ')"

    if [ -n "$app_deployed" ]; then

        echo "$app_srvgroup" | while read group; do

            hc=$(find $wildfly_dir/ -type d -maxdepth 1 -iname 'hc*' 2> /dev/null)

            echo "$hc" | while read hc_dir; do

                # para cada host controller, identificar os logs no diretório de configuração da instância associada ao server group
                hc_name=$(basename $hc_dir)
                srvconf=$(cat $hc_dir/configuration/host-slave.xml | grep -E "group=(['\"])?$group(['\"])?" | sed -r "s|^.*name=['\"]?([^'\"]+)['\"]?.*$|\1|")
                app_log_dir=$(find $hc_dir/ -type d -iwholename "$hc_dir/servers/$srvconf/log" 2> /dev/null)

                if [ -d  "$app_log_dir" ] && [ -f "$app_log_dir/server.log" ]; then

                    log "INFO" "Copiando logs da aplicação $app no diretório $app_log_dir"
                    cd $app_log_dir; zip -rql1 ${shared_log_dir}/logs_${hc_name}_${srvconf}.zip *; cd - > /dev/null
                    cp -f $app_log_dir/server.log $shared_log_dir/server_${hc_name}_${srvconf}.log

                    log "INFO" "Expurgando logs antigos no diretório $app_log_dir..."
                    ls -1 $app_log_dir/server.log.* | sort | head -n -$log_limit | xargs -r rm -fv

                else
                    log "INFO" "Não foram encontrados arquivos de log para a aplicação $app"
                fi

            done

        done

    else
        log "ERRO" "A aplicação $app não foi localizada pelo domain controller ($controller_hostname:$controller_port)" && exit 1
    fi
}

# Validar variáveis específicas
test -f $wildfly_dir/bin/jboss-cli.sh || exit 1
test -n $controller_hostname || exit 1
test -n $controller_port || exit 1
test -n $user || exit 1
test -n $password || exit 1
test "$log_limit" -ge 0 || exit 1

# testar a conexão com o domain controller
wildfly_cmd="$wildfly_dir/bin/jboss-cli.sh --connect --controller=$controller_hostname:$controller_port --user=$user --password=$password"
$wildfly_cmd --command="deployment-info --server-group=*" > /dev/null || exit 1

# executar função de deploy ou cópia de logs
case $1 in
    log) copy_log;;
    deploy) deploy_pkg;;
    *) log "ERRO" "O script somente admite os parâmetros 'deploy' ou 'log'.";;
esac

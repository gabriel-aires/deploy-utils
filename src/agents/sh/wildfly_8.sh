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
                    log "ERRO" "Falha ao remover a aplicação $app.$ext do server-group $group" && error=true
                    write_history "Falha ao remover a aplicação $app.$ext do server-group $group" "0"
                    continue
                fi

                log "INFO" "Implantando a nova versão da aplicação $app no grupo $group"
                $wildfly_cmd --command="deploy $pkg --name=$app.$ext --server-groups=$group"
                if [ "$?" -ne "0" ]; then
                    log "ERRO" "Falha ao implantar a aplicação $app.$ext no server-group $group" && error=true
                    write_history "Falha ao implantar a aplicação $app.$ext no server-group $group" "0"
                    continue
                fi

                log "INFO" "Deploy do arquivo $pkg realizado com sucesso no server-group '$group'"
                write_history "Deploy concluído com sucesso no grupo '$group'" "1"

            done

        else
            log "ERRO" "A aplicação $app não foi localizada pelo domain controller ($controller_hostname:$controller_port)" && error=true
            write_history "A aplicação $app não foi localizada pelo domain controller" "0"
        fi

    else
        log "ERRO" "O deploy deve ser realizado através do domain controller ($controller_host)" && error=true
        write_history "O deploy deve ser realizado através domain controller ($controller_host)" "0"
    fi

    # finalizado o deploy, remover pacote do diretório de origem
    rm -f $pkg

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
                    cd $app_log_dir; compress ${shared_log_dir}/logs_${hc_name}_${srvconf}.zip *; cd - > /dev/null
                    cp -f $app_log_dir/server.log $shared_log_dir/server_${hc_name}_${srvconf}.log

                else
                    log "INFO" "Não foram encontrados arquivos de log para a aplicação $app"
                fi

            done

        done

    else
        log "ERRO" "A aplicação $app não foi localizada pelo domain controller ($controller_hostname:$controller_port)" && error=true
    fi
}

# Validar variáveis específicas
error=false

test ! -x $wildfly_dir/bin/jboss-cli.sh && log "ERRO" "Não foi identificado o executável jboss-cli.sh" && error=true
test -z $controller_hostname && log "ERRO" "O parâmetro 'controller_hostname' deve ser preenchido." && error=true
test -z $controller_port && log "ERRO" "O parâmetro 'controller_port' deve ser preenchido." && error=true
test -z $user && log "ERRO" "O parâmetro 'user' deve ser preenchido." && error=true
test -z $password && log "ERRO" "O parâmetro 'password' deve ser preenchido." && error=true

$error && log "ERRO" "Rotina abortada." && exit 1

# testar a conexão com o domain controller
wildfly_cmd="timeout -s KILL $((agent_timeout/2)) $wildfly_dir/bin/jboss-cli.sh --connect --controller=$controller_hostname:$controller_port --user=$user --password=$password"
$wildfly_cmd --command="deployment-info --server-group=*" > /dev/null || { log "ERRO" "Falha na conexão com o domain controller" && error=true ; }

$error && log "ERRO" "Rotina abortada." && exit 1

# executar função de deploy ou cópia de logs
case $1 in
    log) copy_log;;
    deploy) deploy_pkg;;
    *) log "ERRO" "O script somente admite os parâmetros 'deploy' ou 'log'.";;
esac

$error && log "ERRO" "Rotina concluída com erro(s)." && exit 1
log "INFO" "Rotina concluída com sucesso." && exit 0
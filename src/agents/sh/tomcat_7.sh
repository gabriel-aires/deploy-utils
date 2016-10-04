#!/bin/bash

function tomcat_script_init () {

    ##### LOCALIZA SCRIPT DE INICIALIZAÇÃO DA INSTÂNCIA TOMCAT #####

    local tomcat_path=$1
    unset script_init
    
    test ! -d "$tomcat_path" && log "ERRO" "Parâmetros incorretos ou instância TOMCAT não encontrada." && return 1
    find /etc/init.d/ -type f -iname '*tomcat*' > "$tmp_dir/scripts_tomcat.list"

    #verifica todos os scripts de tomcat encontrados em /etc/init.d até localizar o correto.
    while read script_tomcat && [ -z "$script_init" ]; do

        #verifica se o script corresponde à instalação correta do TOMCAT e se aceita os argumentos 'start' e 'stop'
        test -n "$(grep -E "^[[:blank:]]*[\"']?start[\"']?\)" "$script_tomcat" | head -1)" || continue
        test -n "$(grep -E "^[[:blank:]]*[\"']?stop[\"']?\)" "$script_tomcat" | head -1)" || continue
        test -n "$(grep -F "$tomcat_path" "$script_tomcat" | head -1)" || continue
        
        #retorna a primeira linha onde foi definida a variável $CATALINA_BASE (ou $CATALINA_HOME, caso haja somente uma instância TOMCAT no servidor)
        param_name='CATALINA_BASE'
        param_line="$(grep -Ex '[[:blank:]]*${param_name}=.*' "$script_tomcat" | head -1 )"

        if [ -z "$param_line" ]; then
            param_name='CATALINA_HOME'
            param_line="$(grep -Ex '[[:blank:]]*${param_name}=.*' "$script_tomcat" | head -1 )"
        fi
        
        param_value="$(echo "$param_line" | cut -f2 -d '=' | tr -d "'" | tr -d '"' | tr '{}' '%')"

        #verificar se houve substituição de parâmetros
        if echo "$param_value" | grep -Ex "\\$%$param_name[:=-]+[^%]+%.*" &> /dev/null; then
            param_value=$(echo "$param_value" | sed 's|^..||' | sed 's|%.*$||' | sed -r "s|$param_name[:=-]+||")
        fi

        #verifica se o script encontrado corresponde à instância desejada.
        if [ "$param_value" == "$tomcat_path" ]; then
            script_init=$script_tomcat
        fi

    done < "$tmp_dir/scripts_tomcat.list"

    test -z "$script_init" && return 1
    return 0

}

function deploy_pkg () {

    ####### deploy #####

    find $tomcat_parent_dir -type f -regextype posix-extended -iregex "$tomcat_parent_dir/[^/]+/webapps/$app\.[ew]ar" > "$tmp_dir/old.list"

    if [ $( cat "$tmp_dir/old.list" | wc -l ) -eq 0 ]; then

        log "ERRO" "Deploy abortado. Não foi encontrado pacote anterior. O deploy deverá ser feito manualmente."
        write_history "Deploy abortado. Pacote anterior não encontrado." "0"

    else

        while read old; do

            log "INFO" "O pacote $old será substituído".

            deploy_dir=$(echo $old | sed -r "s|^(${tomcat_parent_dir}/[^/]+/webapps)/[^/]+\.[ew]ar$|\1|i")
            tomcat_dir=$(echo $old | sed -r "s|^(${tomcat_parent_dir}/[^/]+)/webapps/[^/]+\.[ew]ar$|\1|i")
            tomcat_instance=$(basename $tomcat_dir)

            #tenta localizar o script de inicialização da instância e seta a variável $script_init, caso tenha sucesso
            tomcat_script_init "$tomcat_dir"

            if [ -z "$script_init" ]; then
                log "ERRO" "Não foi encontrado o script de inicialização da instância TOMCAT. O deploy deverá ser feito manualmente."
                write_history "Deploy abortado. Script de inicialização não encontrado." "0"
            else
                log "INFO" "Instância do TOMCAT:    \t$tomcat_instance"
                log "INFO" "Diretório de deploy:    \t$deploy_dir"
                log "INFO" "Script de inicialização:\t$script_init"

                stop_instance="timeout -s KILL $((agent_timeout/2)) $script_init stop"
                start_instance="timeout -s KILL $((agent_timeout/2)) $script_init start"

                $stop_instance

                if [ $? -ne 0 ] || [ $(pgrep -f "\-Dcatalina.base=$tomcat_dir" | wc -l) -ne 0 ]; then
                    log "ERRO" "Não foi possível parar a instância $tomcat_instance do TOMCAT. Deploy abortado."
                    write_history "Deploy abortado. Impossível parar a instância $tomcat_instance." "0"
                else
                    rm -f $old
                    cp $pkg $deploy_dir/$(echo $app | tr '[:upper:]' '[:lower:]').$ext
                    chown -R tomcat:tomcat $deploy_dir/

                    $start_instance

                    if [ $? -ne 0 ] || [ $(pgrep -f "\-Dcatalina.base=$tomcat_dir" | wc -l) -eq 0 ]; then
                        log "ERRO" "O deploy do arquivo $pkg foi concluído, porém não foi possível reiniciar a instância do TOMCAT."
                        write_history "Deploy não concluído. Erro ao reiniciar a instância $tomcat_instance." "0"
                    else
                        log "INFO" "Deploy do arquivo $pkg concluído com sucesso!"
                        write_history "Deploy concluído com sucesso na instância $tomcat_instance." "1"
                    fi

                fi

            fi

        done < "$tmp_dir/old.list"

        rm -f $pkg

    fi

}

function copy_log () {

    ######## LOGS #########

    log "INFO" "Copiando logs da rotina e das instâncias TOMCAT em ${tomcat_parent_dir}..."

    rm -f "$tmp_dir/app_origem.list"
    find $tomcat_parent_dir -type f -regextype posix-extended -iregex "$tomcat_parent_dir/[^/]+/webapps/$app\.[ew]ar" > "$tmp_dir/app_origem.list" 2> /dev/null

    if [ $(cat "$tmp_dir/app_origem.list" | wc -l) -ne 0 ]; then

        while read caminho_app; do

            tomcat_instance=$(echo $caminho_app | sed -r "s|^${tomcat_parent_dir}/([^/]+)/webapps/[^/]+\.[ew]ar$|\1|")
            catalina_out=$(find "${tomcat_parent_dir}/${tomcat_instance}" -iwholename "${tomcat_parent_dir}/${tomcat_instance}/logs/catalina.out" 2> /dev/null)

            if [ $(echo $catalna_out | wc -l) -eq 1 ]; then
                log "INFO" "Copiando logs da aplicação $app no diretório $(dirname $catalina_out)..."
                cd $(dirname $catalina_out); zip -rql1 ${shared_log_dir}/${tomcat_instance}.zip *; cd - > /dev/null
                cp -f $catalina_out "$shared_log_dir/catalina_${tomcat_instance}.log"
                unix2dos "$shared_log_dir/catalina_${tomcat_instance}.log" > /dev/null 2>&1
            else
                log "ERRO" "Não há logs da instância TOMCAT correspondente à aplicação $app."
            fi

        done < "$tmp_dir/app_origem.list"

    else
        log "ERRO" "A aplicação $app não foi encontrada."
    fi

}

# Validar variáveis específicas
test ! -d "${tomcat_parent_dir}" && log "ERRO" "O parâmetro 'tomcat_parent_dir' deve ser um diretório válido." && exit 1

case $1 in
    log) copy_log;;
    deploy) deploy_pkg;;
    *) log "ERRO" "O script somente admite os parâmetros 'deploy' ou 'log'.";;
esac

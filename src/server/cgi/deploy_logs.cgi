#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

function end() {
    test "$1" == "0" || echo "      <p><b>Operação inválida.</b></p>"
    web_footer

    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    clean_locks
    wait &> /dev/null

    exit $1
}

trap "end 1" SIGQUIT SIGINT SIGHUP
mkdir $tmp_dir

### Cabeçalho
web_header

# Inicializar variáveis e constantes
mklist "$ambientes" "$tmp_dir/lista_ambientes"

valid "upload_dir" "<p><b>Erro. Caminho inválido para o diretório de upload.</b></p>"
test ! -d "$upload_dir" && "<p><b>Erro. Diretório de upload inexistente.</b></p>" && end 1
test ! -x "$upload_dir" && "<p><b>Erro. Permissões insuficientes no diretório de upload.</b></p>" && end 1

if [ -z "$QUERY_STRING" ]; then

    # Formulário deploy
    echo "      <p>"
    echo "          <form action=\"$start_page\" method=\"post\">"
    # Sistema...
    echo "              <p>"
    echo "      		    <select class=\"select_default\" name=\"app\">"
    echo "		        	<option value=\"\" selected>Sistema...</option>"
    find $app_history_dir_tree/ -mindepth 2 -maxdepth 2 -type d | xargs -I{} -d '\n' basename {} | sort | uniq | sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|" 2> /dev/null
    echo "		            </select>"
    echo "              </p>"
    # Ambiente...
    echo "              <p>"
    echo "      		<select class=\"select_default\" name=\"env\">"
    echo "		        	<option value=\"\" selected>Ambiente...</option>"
    cat $tmp_dir/lista_ambientes | sort | sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|"
    echo "		        </select>"
    echo "              </p>"
    # Submit
    echo "              <p>"
    echo "              <input type=\"submit\" name=\"submit\" value=\"Visualizar\">"
    echo "              </p>"
    echo "          </form>"
    echo "      </p>"

else

    # Processar QUERY_STRING
    arg_string="&$(web_filter "$QUERY_STRING")&"
    app=$(echo "$arg_string" | sed -rn "s/^.*&app=([^\&]+)&.*$/\1/p")
    env=$(echo "$arg_string" | sed -rn "s/^.*&env=([^\&]+)&.*$/\1/p")
    deploy_id=$(echo "$arg_string" | sed -rn "s/^.*&deploy_id=([^\&]+)&.*$/\1/p")

    if [ -n "$app" ] && [ -n "$env" ]; then

        if [ -z "$deploy_id" ]; then

            find $app_history_dir_tree/ -mindepth 3 -maxdepth 3 -type d -regextype posix-extended -iregex "^$app_history_dir_tree/$env/$app/.*$" | sort > $tmp_dir/log_path
            test "$(cat $tmp_dir/log_path | wc -l)" -eq 0 && echo "<p><b>Nenhum caminho de de acesso a logs encontrado para a aplicação '$app' no ambiente '$env'.</b></p>" && end 0
            echo "          <p>Sistema: $app</p>"
            echo "          <p>Ambiente: $env</p>"
            echo "          <ul>"
            cat $tmp_dir/log_path | sed -r "s|^$app_history_dir_tree/$env/$app/(.*)$|<li><a href=\"$web_context_path/deploy_logs.cgi?app=$app&env=$ambiente&deploy_id=\1\">\1</a></li>|"
            echo "          </ul>"

        else

            echo "          <p>Sistema: $app</p>"
            echo "          <p>Ambiente: $env</p>"
            echo "          <p>Deploy ID: $deploy_id</p>"

            app_log_clearance="$tmp_dir/app_log_clearance"
            env_log_clearance="$tmp_dir/env_log_clearance"
            process_group=''
            show_links=false

            rm -f $app_log_clearance $env_log_clearance

            { clearance "user" "$REMOTE_USER" "app" "$app" "read" && touch "$app_log_clearance"; } &
            process_group="$process_group $!"

            { clearance "user" "$REMOTE_USER" "ambiente" "$env" "read" && touch "$env_log_clearance"; } &
            process_group="$process_group $!"

            wait $process_group
            test -f $app_log_clearance && test -f $env_log_clearance && show_links=true

            if $show_links; then
                echo "          <ul>"
                find "$app_history_dir_tree/$env/$app/$deploy_id/" -maxdepth 1 -type f | sed -r "s|^$app_history_dir_tree/(.*)$|<li><a href=\"$apache_history_alias/\1\">\1</a></li>|" || end 1
                echo "          </ul>"
            fi

        fi

    else
        echo "      <p><b>Erro. Os parâmetro 'Sistema' e 'Ambiente' devem ser preenchidos.</b></p>"
    fi
fi

end 0

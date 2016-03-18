#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

function submit_deploy() {

    if [ "$proceed" != "$proceed_view" ]; then
        return 1

    else
        local app_deploy_clearance="$tmp_dir/app_deploy_clearance"
        local env_deploy_clearance="$tmp_dir/env_deploy_clearance"
        local process_group=''
        local show_form=false

        rm -f $app_deploy_clearance $env_deploy_clearance

        { clearance "user" "$REMOTE_USER" "app" "$app_name" "write" && touch "$app_deploy_clearance"; } &
        process_group="$process_group $!"

        { clearance "user" "$REMOTE_USER" "ambiente" "$env_name" "write" && touch "$env_deploy_clearance"; } &
        process_group="$process_group $!"

        wait $process_group
        test -f $app_deploy_clearance && test -f $env_deploy_clearance && show_form=true

        if $show_form; then
            echo "      <p>"
            echo "          <form action=\"$start_page\" method=\"post\" enctype=\"multipart/form-data\">"
            echo "              <input type=\"hidden\" name=\"$app_param\" value=\"$app_name\"></td></tr>"
            echo "              <input type=\"hidden\" name=\"$env_param\" value=\"$env_name\"></td></tr>"
            echo "              <input type=\"submit\" name=\"proceed\" value=\"$proceed_deploy\">"
            echo "              Arquivo: <input type=\"file\" name=\"file\">"
            echo "              <input type=\"submit\" name=\"upload\" value=\"Enviar\">"
            echo "          </form>"
            echo "      </p>"
        fi

    fi

    return 0

}

function end() {

    web_footer

    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    test -n "$sleep_pid" && kill "$sleep_pid" &> /dev/null
    clean_locks
    wait &> /dev/null

    exit $1
}

trap "end 1" SIGQUIT SIGINT SIGHUP
mkdir $tmp_dir

### Cabeçalho
web_header

# Inicializar variáveis e constantes
test "$REQUEST_METHOD" == "POST" && test -n "$CONTENT_LENGTH" && read -n "$CONTENT_LENGTH" POST_CONTENT
mklist "$ambientes" "$tmp_dir/lista_ambientes"
app_param="$(echo "$col_app" | sed -r 's/\[//;s/\]//')"
env_param="$(echo "$col_env" | sed -r 's/\[//;s/\]//')"
proceed_view="Continuar"
proceed_deploy="Deploy"

if [ -z "$POST_CONTENT" ]; then

    # Formulário deploy
    echo "      <p>"
    echo "          <form action=\"$start_page\" method=\"post\" enctype=\"multipart/form-data\">"
    # Sistema...
    echo "              <p>"
    echo "      		    <select class=\"select_default\" name=\"$app_param\">"
    echo "		        	<option value=\"\" selected>Sistema...</option>"
    find $upload_dir/ -mindepth $((qtd_dir+1)) -maxdepth $((qtd_dir+1)) -type d | sort | uniq | xargs -I{} -d '\n' basename {} | sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|" 2> /dev/null
    echo "		            </select>"
    echo "              </p>"
    # Ambiente...
    echo "              <p>"
    echo "      		<select class=\"select_default\" name=\"$env_param\">"
    echo "		        	<option value=\"\" selected>Ambiente...</option>"
    cat $tmp_dir/lista_ambientes | sort | sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|"
    echo "		        </select>"
    echo "              </p>"
    # Submit
    echo "              <p>"
    echo "              <input type=\"submit\" name=\"proceed\" value=\"$proceed_view\">"
    echo "              </p>"
    echo "          </form>"
    echo "      </p>"

else

    # Processar POST_CONTENT
    #arg_string="&$(web_filter "$POST_CONTENT")&"
    #app_name=$(echo "$arg_string" | sed -rn "s/^.*&$app_param=([^\&]+)&.*$/\1/p")
    #env_name=$(echo "$arg_string" | sed -rn "s/^.*&$env_param=([^\&]+)&.*$/\1/p")
    #proceed=$(echo "$arg_string" | sed -rn "s/^.*&proceed=([^\&]+)&.*$/\1/p")

    #DEBUG
    echo "<p>"
    echo "  ENVIRONMENT: <br>"
    env
    echo "</p>"
    echo "<p>"
    echo "  POST: <br>"
    echo "$POST_CONTENT"
    echo "</p>"
    #DEBUG

    if [ -n "$app_name" ] && [ -n "$env_name" ] && [ -n "$proceed" ]; then

        if [ "$proceed" == "$proceed_view" ]; then

            ### Visualizar parâmetros de deploy
            echo "      <p>"
            echo "          <table>"
            echo "              <tr><td>Sistema: </td><td>$app_name</td></tr>"
            echo "              <tr><td>Ambiente: </td><td>$env_name</td></tr>"
            echo "          </table>"
            echo "      </p>"

            submit_deploy

        else

            test -n "$REMOTE_USER" && user_name="$REMOTE_USER" || user_name="$(id --user --name)"
            # Realizar deploy

            fi
        fi
    else
        echo "      <p><b>Erro. Os parâmetro 'Sistema' e 'Ambiente' devem ser preenchidos.</b></p>"
    fi
fi

end 0

#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

function submit_log() {

    if [ -z "$proceed" ]; then
        return 1
    else

        local app_log_clearance="$tmp_dir/app_log_clearance"
        local env_log_clearance="$tmp_dir/env_log_clearance"
        local process_group=''
        local show_form=false

        rm -f $app_log_clearance $env_log_clearance

        { clearance "user" "$REMOTE_USER" "app" "$app_name" "read" && touch "$app_log_clearance"; } &
        process_group="$process_group $!"

        { clearance "user" "$REMOTE_USER" "ambiente" "$env_name" "read" && touch "$env_log_clearance"; } &
        process_group="$process_group $!"

        wait $process_group
        test -f $app_log_clearance && test -f $env_log_clearance && show_form=true

        if $show_form; then
            echo "      <p>"
            echo "          <form action=\"$start_page\" method=\"post\">"
            echo "              <input type=\"hidden\" name=\"$app_param\" value=\"$app_name\"></td></tr>"
            echo "              <input type=\"hidden\" name=\"$env_param\" value=\"$env_name\"></td></tr>"
            echo "                  <select class=\"select_large\" name=\"log_subpath\">"
            echo "		                <option value=\"\" selected>Selecionar Caminho...</option>"
            cat $tmp_dir/log_path | sed -r "s|^$upload_dir/(.*)$|\t\t\t\t\t\t<option>\1</option>|"
            echo "                  </select>"
            echo "              <input type=\"submit\" name=\"proceed\" value=\"$proceed_log\">"
            echo "          </form>"
            echo "      </p>"
        fi

    fi

    return 0

}

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
test "$REQUEST_METHOD" == "POST" && test -n "$CONTENT_LENGTH" && read -n "$CONTENT_LENGTH" POST_STRING
mklist "$ambientes" "$tmp_dir/lista_ambientes"
app_param="$(echo "$col_app" | sed -r 's/\[//;s/\]//')"
env_param="$(echo "$col_env" | sed -r 's/\[//;s/\]//')"
proceed_view="Continuar"
proceed_log="Acessar"

valid "upload_dir" "<p><b>Erro. Caminho inválido para o diretório de upload.</b></p>"
test ! -d "$upload_dir" && "<p><b>Erro. Diretório de upload inexistente.</b></p>" && end 1
test ! -x "$upload_dir" && "<p><b>Erro. Permissões insuficientes no diretório de upload.</b></p>" && end 1

if [ -z "$POST_STRING" ]; then

    # Formulário deploy
    echo "      <p>"
    echo "          <form action=\"$start_page\" method=\"post\">"
    # Sistema...
    echo "              <p>"
    echo "      		    <select class=\"select_default\" name=\"app\">"
    echo "		        	<option value=\"\" selected>Sistema...</option>"
    find $upload_dir/ -mindepth $((qtd_dir+1)) -maxdepth $((qtd_dir+1)) -type d | xargs -I{} -d '\n' basename {} | sort | uniq | sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|" 2> /dev/null
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
    echo "              <input type=\"submit\" name=\"proceed\" value=\"$proceed_view\">"
    echo "              </p>"
    echo "          </form>"
    echo "      </p>"

else

    # Processar POST_STRING
    arg_string="&$(web_filter "$POST_STRING")&"
    app_name=$(echo "$arg_string" | sed -rn "s/^.*&app=([^\&]+)&.*$/\1/p")
    env_name=$(echo "$arg_string" | sed -rn "s/^.*&env=([^\&]+)&.*$/\1/p")
    proceed=$(echo "$arg_string" | sed -rn "s/^.*&proceed=([^\&]+)&.*$/\1/p")

    if [ -n "$app" ] && [ -n "$env" ] && [ -n "$proceed" ]; then

        case "$proceed" in

            "$proceed_view")
                find $upload_dir/ -mindepth $((qtd_dir+2)) -maxdepth $((qtd_dir+2)) -type d -regextype posix-extended -iregex "^$upload_dir/$env/.*/$app/log$" > $tmp_dir/log_path
                test "$(cat $tmp_dir/log_path | wc -l)" -eq 0 && echo "<p><b>Nenhum caminho de de acesso a logs encontrado para a aplicação '$app' no ambiente '$env'.</b></p>" && end 1
                echo "          <p>Sistema: $app</p>"
                echo "          <p>Ambiente: $env</p>"
                submit_log || end 1
                ;;

            "$proceed_log")
                log_subpath=$(echo "$arg_string" | sed -rn "s/^.*&log_subpath=([^\&]+)&.*$/\1/p")
                echo "$log_subpath" | grep -Ei "/log$" > /dev/null || end 1
                find $upload_dir/$log_subpath/ -maxdepth 1 -type f | sed -r "s|(.*)|<a href=\"\1\">\1</a>|" || end 1
                ;;

        esac

    else
        echo "      <p><b>Erro. Os parâmetro 'Sistema' e 'Ambiente' devem ser preenchidos.</b></p>"
    fi
fi

end 0

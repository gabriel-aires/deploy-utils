#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

function end() {
    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    clean_locks

    wait
    exit $1
}

trap "end 1" SIGQUIT SIGINT SIGHUP EXIT
mkdir $tmp_dir

### Cabeçalho
web_header

# Inicializar variáveis e constantes
test "$REQUEST_METHOD" == "POST" && test -n "$CONTENT_LENGTH" && read -n "$CONTENT_LENGTH" POST_STRING
mklist "$ambientes" "$tmp_dir/lista_ambientes"
app_param="$(echo "$col_app" | sed -r 's/\[//;s/\]//')"
env_param="$(echo "$col_env" | sed -r 's/\[//;s/\]//')"
save_value='Salvar'
erase_value='Remover'
erase_yes='Sim'
erase_no='Nao'

# Formulário de pesquisa
echo "      <p>"
echo "          <form action=\"$start_page\" method=\"get\">"
# Sistema...
echo "              <table>"
echo "                  <tr>"
echo "                      <td>Sistema:  </td>"
echo "                      <td>"
echo "                          <select style=\"min-width:100px\" name=\"$app_param\">"
echo "		                        <option value=\"\" selected>Adicionar...</option>"
find $app_history_dir_tree/ -mindepth 1 -maxdepth 1 -type d | sort | xargs -I{} -d '\n' basename {} | sed -r "s|(.*)|\t\t\t\t\t\t<option>\1</option>|"
echo "                          </select>"
echo "                      </td>"
echo "                  </tr>"
echo "              </table>"
# Ambiente...
echo "              <table>"
echo "                  <tr>"
echo "                      <td>Ambiente: </td>"
echo "                      <td>"
echo "                          <select style=\"min-width:100px\" name=\"$env_param\">"
echo "                              <option value=\"\" selected>Todos</option>"
cat $tmp_dir/lista_ambientes | sort | sed -r "s|(.*)|\t\t\t\t\t\t<option>\1</option>|"
echo "                          </select>"
echo "                      </td>"
echo "                  </tr>"
echo "              </table>"
# Submit
echo "              <p><input type=\"submit\" name=\"ok\" value=\"OK\"></p>"
echo "          </form>"
echo "      </p>"

if [ -n "$QUERY_STRING" ]; then

    # EDITAR PARÂMETROS
    arg_string="&$(web_filter "$QUERY_STRING")&"
    app_name=$(echo "$arg_string" | sed -rn "s/^.*&$app_param=([^\&]+)&.*$/\1/p")
    env_name=$(echo "$arg_string" | sed -rn "s/^.*&$env_param=([^\&]+)&.*$/\1/p")

    echo "      <p>"
    echo "          <form action=\"$start_page\" method=\"post\">"
    echo "              <table>"
    test -f "$app_conf_dir/$app.conf" && form_file="$app_conf_dir/$app.conf" || form_file="$install_dir/template/app.template"
    while read l; do
        show_param=true
        key="$(echo "$l" | cut -f1 -d '=')"
        value="$(echo "$l" | sed -rn "s/^[^\=]+=//p" | sed -r "s/'//g" | sed -r 's/"//g')"
        if [ -n "$env_name" ]; then
            echo "$key" | grep -Ex ".*_($regex_ambiente)" > /dev/null  && show_param=false
            ! $show_param && echo "$key" | grep -Ex ".*_$env_name" > /dev/null && show_param=true
        fi
        $show_param && echo "              <tr><td>$key:      </td><td><input type=\"text\" size=\"100\" name=\"$key\" value=\"$value\"></td></tr>"
    done < "$form_file"
    echo "              </table>"
    echo "              <input type=\"submit\" name=\"save\" value=\"$save_value\">"
    echo "              <input type=\"submit\" name=\"erase\" value=\"$erase_value\">"
    echo "          </form>"
    echo "      </p>"

elif [ -n "$POST_STRING" ]; then

    # SALVAR/DELETAR PARÂMETROS

    arg_string="&$(web_filter "$POST_STRING")&"
    app_name=$(echo "$arg_string" | sed -rn "s/^.*&app=([^\&]+)&.*$/\1/p")
    save=$(echo "$arg_string" | sed -rn "s/^.*&save=([^\&]+)&.*$/\1/p")
    erase=$(echo "$arg_string" | sed -rn "s/^.*&erase=([^\&]+)&.*$/\1/p")

    if [ -n "$app_name" ]; then

        if [ "$save" == "$save_value" ]; then
            test -f $app_conf_dir/$app_name.conf || cp "$install_dir/template/app.template" "$app_conf_dir/$app_name.conf"
            lock "$app_name" "Aplicação $app_name bloqueada para edição"

            while read l; do
                key="$(echo "$l" | cut -f1 -d '=')"
                new_value="$(echo "$arg_string" | sed -rn "s/^.*&$key=([^\&]+)&.*$/\1/p" | sed -r "s/'//g" | sed -r 's/"//g')"
                editconf "$key" "$new_value" "$app_conf_dir/$app_name.conf"
            done < "$app_conf_dir/$app_name.conf"

            echo "      <p><b>Parâmetros da aplicação $app_name atualizados.</b></p>"

        elif [ "$erase" == "$erase_value" ]; then
            echo "      <p>"
            echo "          <b>Tem certeza de que deseja remover os parâmetros da aplicação $app_name?</b>"
            echo "          <form action=\"$start_page\" method=\"post\">"
            echo "              <input type=\"hidden\" name=\"app\" value=\"$app_name\"></td></tr>"
            echo "              <input type=\"submit\" name=\"erase\" value=\"$erase_yes\">"
            echo "              <input type=\"submit\" name=\"erase\" value=\"$erase_no\">"
            echo "          </form>"
            echo "      </p>"

        elif [ "$erase" == "$erase_yes" ]; then
            rm -f "$app_conf_dir/$app_name.conf"
            echo "      <p><b>Parâmetros da aplicação $app_name removidos.</b></p>"

        elif [ "$erase" == "$erase_no" ]; then
            echo "      <p><b>Deleção dos parâmetros da aplicação $app_name cancelada.</b></p>"

        fi

    else
        echo "      <p><b>Erro. O parâmetro 'app' deve ser preenchido.</b></p>"
    fi
fi

#Links
web_footer

echo '  </body>'
echo '</html>'

end 0

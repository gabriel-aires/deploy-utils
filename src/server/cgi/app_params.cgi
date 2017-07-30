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

    wait
    exit $1
}

trap "end 1" SIGQUIT SIGINT SIGHUP SIGTERM
mkdir $tmp_dir

### Cabeçalho
web_header

# Inicializar variáveis e constantes
test "$REQUEST_METHOD" == "POST" && test -n "$CONTENT_LENGTH" && read -n "$CONTENT_LENGTH" POST_STRING
mklist "$ambientes" "$tmp_dir/lista_ambientes"
app_param="$(echo "${col[app]}" | sed -r 's/\[//;s/\]//')"
env_param="$(echo "${col[env]}" | sed -r 's/\[//;s/\]//')"
save_value='Salvar'
erase_value='Remover'
erase_yes='Sim'
erase_no='Nao'

# Formulário de pesquisa
echo "      <p>"
echo "          <form action=\"$start_page\" method=\"get\">"
echo "              <table cellspacing=\"5px\">"
# Sistema...
echo "                  <tr>"
echo "                      <td>Sistema: </td>"
echo "                      <td>"
echo "                          <select class=\"select_default\" name=\"$app_param\">"
echo "		                        <option value=\"\" selected>Adicionar...</option>"
find $app_conf_dir/ -mindepth 1 -maxdepth 1 -type f -name '*.conf' | sort | xargs -I{} -d '\n' basename {} | cut -f1 -d '.' | sed -r "s|(.*)|\t\t\t\t\t\t<option>\1</option>|"
echo "                          </select>"
echo "                      </td>"
echo "                  </tr>"
# Ambiente...
echo "                  <tr>"
echo "                      <td>Ambiente: </td>"
echo "                      <td>"
echo "                          <select class=\"select_default\" name=\"$env_param\">"
echo "                              <option value=\"\" selected>Todos</option>"
cat $tmp_dir/lista_ambientes | sort | sed -r "s|(.*)|\t\t\t\t\t\t<option>\1</option>|"
echo "                          </select>"
echo "                      </td>"
echo "                  </tr>"
# Submit
echo "                  <tr>"
echo "                      <td><input type=\"submit\" name=\"ok\" value=\"OK\"></td>"
echo "                  </tr>"
echo "              </table>"
echo "          </form>"
echo "      </p>"

if [ -n "$QUERY_STRING" ]; then

    # EDITAR PARÂMETROS
    arg_string="&$(web_filter "$QUERY_STRING")&"
    app_name=$(echo "$arg_string" | sed -rn "s/^.*&$app_param=([^\&]+)&.*$/\1/p")
    env_name=$(echo "$arg_string" | sed -rn "s/^.*&$env_param=([^\&]+)&.*$/\1/p")

    echo "      <p>"
    echo "          <form action=\"$start_page\" method=\"post\">"
    echo "              <div class=\"column zero_padding cfg_color box_shadow\">"
    echo "                  <table>"
    test -f "$app_conf_dir/$app_name.conf" && form_file="$app_conf_dir/$app_name.conf" || form_file="$install_dir/template/app.template"
    while read l; do
        key="$(echo "$l" | cut -f1 -d '=')"
        value="$(echo "$l" | sed -rn "s/^[^\=]+=//p" | sed -r "s/'//g" | sed -r 's/"//g')"
        if echo "$key" | grep -E "^#" > /dev/null; then
            echo "                      <tr><td colspan=\"2\">$key</td></tr>"
        else
            show_param=true
            if [ -n "$env_name" ]; then
                echo "$key" | grep -Ex ".*\[(${regex[ambiente]})\]" > /dev/null  && show_param=false
                ! $show_param && echo "$key" | grep -Ex ".*\[$env_name\]" > /dev/null && show_param=true
            fi
            $show_param && echo "                   <tr><td>$key: </td><td><input type=\"text\" size=\"100\" name=\"$key\" value=\"$value\"></td></tr>"
        fi
    done < "$form_file"
    echo "                      <tr><td><input type=\"submit\" name=\"save\" value=\"$save_value\"> <input type=\"submit\" name=\"erase\" value=\"$erase_value\"></td>"
    echo "                  </table>"
    echo "              </div>"
    echo "          </form>"
    echo "      </p>"

elif [ -n "$POST_STRING" ]; then

    # SALVAR/DELETAR PARÂMETROS

    arg_string="&$(web_filter "$POST_STRING")&"
    app_name=$(echo "$arg_string" | sed -rn "s/^.*&app=([^\&]+)&.*$/\1/p")
    save=$(echo "$arg_string" | sed -rn "s/^.*&save=([^\&]+)&.*$/\1/p")
    erase=$(echo "$arg_string" | sed -rn "s/^.*&erase=([^\&]+)&.*$/\1/p")

    if [ -n "$app_name" ]; then
        valid "$app_name" "app" "<p><b>O nome da aplicação é inválido: '$app_name'.</b></p>" || end 1
        lock "edit_app_$app_name" "<p><b>Aplicação '$app_name' bloqueada para edição.</b></p>" || end 1

        if [ "$save" == "$save_value" ]; then
            test -f $app_conf_dir/$app_name.conf || cp "$install_dir/template/app.template" "$app_conf_dir/$app_name.conf"
            while read l; do
                key="$(echo "$l" | cut -f1 -d '=')"
                echo "$arg_string" | grep -Ex "^.*&$key=([^\&]*)&.*$" > /dev/null || continue
                new_value="$(echo "$arg_string" | sed -rn "s/^.*&$key=([^\&]*)&.*$/\1/p" | sed -r "s/'//g" | sed -r 's/"//g')"
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
            lock "$app_name" "<p><b>Deploy da aplicação '$app_name' em andamento. Tente mais tarde.</b></p>" || end 1
            rm -f "$app_conf_dir/$app_name.conf"
            echo "      <p><b>Parâmetros da aplicação $app_name removidos.</b></p>"

        elif [ "$erase" == "$erase_no" ]; then
            echo "      <p><b>Deleção dos parâmetros da aplicação $app_name cancelada.</b></p>"

        fi

    else
        echo "      <p><b>Erro. O parâmetro 'app' deve ser preenchido.</b></p>"
    fi
fi

end 0

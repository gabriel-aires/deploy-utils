#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

interactive='false'
verbosity='verbose'

function end() {

    web_footer

    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    clean_locks

    wait
    exit $1
}

trap "end 1" SIGQUIT SIGINT SIGHUP
mkdir $tmp_dir

### Cabeçalho
web_header

# Inicializar variáveis e constantes
test "$REQUEST_METHOD" == "POST" && test -n "$CONTENT_LENGTH" && read -n "$CONTENT_LENGTH" POST_STRING
create_value='Criar Conta'

# Form Select
echo "<form action=\"$start_page\" method=\"post\">"
echo "     <table>"
echo "          <tr><td>Usuário:    </td><td><input type=\"text\" class=\"text_small\" name=\"user\"></td></tr>"
echo "          <tr><td>Senha:       </td><td><input type=\"password\" class=\"text_small\" name=\"password\"></td></tr>"
echo "     </table>"
echo "<input type=\"submit\" name=\"create\" value=\"$create_value\">"
echo "</form>"

if [ -n "$POST_STRING" ]; then

    # SALVAR/DELETAR PARÂMETROS

    arg_string="&$(web_filter "$POST_STRING")&"
    user=$(echo "$arg_string" | sed -rn "s/^.*&user=([^\&]+)&.*$/\1/p")
    password=$(echo "$arg_string" | sed -rn "s/^.*&password=([^\&]+)&.*$/\1/p")

    if [ -n "$user" ] && [ -n "$password" ]; then

        valid "user" "<p><b>Login inválido.</b></p>"
        valid "password" "<p><b>Senha inválida.</b></p>"

        if grep -E "^$user:" "$apache_users_file" > /dev/null; then
            echo "      <p><b>O login '$user' não está disponível. Favor escolher outro nome de usuário.</b></p>"
        else
            htpasswd -b "$apache_users_file" "$user" "$password" || end 1
            echo "      <p><b>Usuário '$user' adicionado com sucesso.</b></p>"
        fi

    else
        echo "      <p><b>Os campos 'Usuário' e 'Senha' são obrigatórios.</b></p>"
    fi
fi

end 0

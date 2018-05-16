#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

function end() {
    test "$1" == "0" || echo "      <p><b>Operação inválida.</b></p>"
    echo "<div class=\"spacer\"></div>"
    web_footer

    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    wait
    exit $1
}

trap "end 1" SIGQUIT SIGINT SIGHUP SIGTERM
mkdir $tmp_dir

### Cabeçalho
web_header

# Inicializar variáveis e constantes
test "$REQUEST_METHOD" == "POST" && test -n "$CONTENT_LENGTH" && read -n "$CONTENT_LENGTH" POST_STRING
update_value='Atualizar Conta'
export -f 'get_email'

# Form Select
echo "<div class=\"column\">"
echo "  <form action=\"$start_page\" method=\"post\">"
echo "     <fieldset>"
echo "          <legend>Atualizar Usuário</legend>"
echo "          <table>"
echo "              <tr><td>Login:              </td><td><input type=\"text\" class=\"text_small\" name=\"user\" value=\"$REMOTE_USER\" disabled></td></tr>"
echo "              <tr><td>Email:              </td><td><input type=\"text\" class=\"text_small\" name=\"email\" placeholder=\"$(get_email "$REMOTE_USER")\"></td></tr>"
echo "              <tr><td>Nova Senha:         </td><td><input type=\"password\" class=\"text_small\" name=\"password\" placeholder=\"...\"></td></tr>"
echo "              <tr><td>Confirmar Senha:    </td><td><input type=\"password\" class=\"text_small\" name=\"assure_password\" placeholder=\"...\"></td></tr>"
echo "              <tr><td colspan=\"2\"><input type=\"submit\" name=\"submit\" value=\"$update_value\"></td></tr>"
echo "          </table>"
echo "     </fieldset>"
echo "  </form>"
echo "</div>"

if [ -n "$POST_STRING" ]; then

    # SALVAR/DELETAR PARÂMETROS

    arg_string="&$(web_filter "$POST_STRING")&"
    email=$(echo "$arg_string" | sed -rn "s/^.*&email=([^\&]+)&.*$/\1/p")
    password=$(echo "$arg_string" | sed -rn "s/^.*&password=([^\&]+)&.*$/\1/p")
    assure_password=$(echo "$arg_string" | sed -rn "s/^.*&assure_password=([^\&]+)&.*$/\1/p")
    changes=false

    if [ -n "$email" ]; then
        valid "$email" "email" "<p><b>Email inválido.</b></p>" || end 1
        delete_email "$REMOTE_USER" || end 1
        add_email "$REMOTE_USER" "$email" || end 1
        changes=true
    fi

    if [ -n "$password" ]; then
        test "$password" != "$assure_password" && echo "<p><b>Erro. Senhas não correspondentes.</b></p>" && end 1
        valid "$password" "password" "<p><b>Senha inválida.</b></p>" || end 1
        add_login "$REMOTE_USER" "$password" || end 1
        changes=true
    fi

    $changes && echo "<p><b>Perfil atualizado com sucesso.</b></p>" || echo "<p><b>Nenhum dado modificado.</b></p>"
    
fi

end 0

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

function random_password() {

    echo "$(date +%s%3N)$1" | md5sum | head -c16

}

trap "end 1" SIGQUIT SIGINT SIGHUP SIGTERM
mkdir $tmp_dir

### Cabeçalho
web_header

# Inicializar variáveis e constantes
test "$REQUEST_METHOD" == "POST" && test -n "$CONTENT_LENGTH" && read -n "$CONTENT_LENGTH" POST_STRING
create_value='Criar Conta'
resetpw_value='Recuperar Acesso'
export -f 'random_password'
export -f 'get_email'

# Form signup
echo "<div class=\"column\">"
echo "  <form action=\"$start_page\" method=\"post\">"
echo "     <fieldset>"
echo "          <legend>Novo Usuário</legend>"
echo "          <table>"
echo "              <tr><td>Login:      </td><td><input type=\"text\" class=\"text_small\" name=\"user\"></td></tr>"
echo "              <tr><td>Email:      </td><td><input type=\"text\" class=\"text_small\" name=\"email\"></td></tr>"
echo "              <tr><td>Senha:      </td><td><input type=\"password\" class=\"text_small\" name=\"password\"></td></tr>"
echo "              <tr><td>Confirmar Senha:      </td><td><input type=\"password\" class=\"text_small\" name=\"assure_password\"></td></tr>"
echo "              <tr><td colspan=\"2\"><input type=\"submit\" name=\"submit\" value=\"$create_value\"></td></tr>"
echo "          </table>"
echo "     </fieldset>"
echo "  </form>"
echo "</div>"

echo "<div class=\"spacer\"></div>"

# Form reset password
echo "<div class=\"column\">"
echo "  <form action=\"$start_page\" method=\"post\">"
echo "     <fieldset>"
echo "          <legend>Esqueci Minha Senha</legend>"
echo "          <table>"
echo "              <tr><td>Login Cadastrado:       </td><td><input type=\"text\" class=\"text_small\" name=\"user\"></td></tr>"
echo "              <tr><td>Email Cadastrado:       </td><td><input type=\"text\" class=\"text_small\" name=\"email\"></td></tr>"
echo "              <tr><td colspan=\"2\"><input type=\"submit\" name=\"submit\" value=\"$resetpw_value\"></td></tr>"
echo "          </table>"
echo "     </fieldset>"
echo "  </form>"
echo "</div>"

echo "<br>"

if [ -n "$POST_STRING" ]; then

    # SALVAR/DELETAR PARÂMETROS

    arg_string="&$(web_filter "$POST_STRING")&"
    submit=$(echo "$arg_string" | sed -rn "s/^.*&submit=([^\&]+)&.*$/\1/p")
    user=$(echo "$arg_string" | sed -rn "s/^.*&user=([^\&]+)&.*$/\1/p")
    email=$(echo "$arg_string" | sed -rn "s/^.*&email=([^\&]+)&.*$/\1/p")
    password=$(echo "$arg_string" | sed -rn "s/^.*&password=([^\&]+)&.*$/\1/p")
    assure_password=$(echo "$arg_string" | sed -rn "s/^.*&assure_password=([^\&]+)&.*$/\1/p")

    case "$submit" in

        "$create_value")

            if [ -n "$user" ] && [ -n "$email" ] && [ -n "$password" ] && [ -n "$assure_password" ]; then

                valid "user" "<p><b>Login inválido.</b></p>"
                valid "email" "<p><b>Email inválido.</b></p>"
                valid "password" "<p><b>Senha inválida.</b></p>"

                test "$password" != "$assure_password" && echo "<p><b>Erro. Senhas não correspondentes.</b></p>" && end 1
                grep -E "^$user:" "$web_users_file" > /dev/null && echo "<p><b>O login '$user' não está disponível. Favor escolher outro nome de usuário.</b></p>" && end 1
                    
                delete_email "$user" || end 1
                add_email "$user" "$email" || end 1
                add_login "$user" "$password" || end 1
                
                echo "      <p><b>Usuário '$user' adicionado com sucesso.</b></p>"
                
            else
                echo "      <p><b>Todos os campos são obrigatórios.</b></p>"
            fi

            ;;

        "$resetpw_value")

            if [ -n "$user" ] && [ -n "$email" ]; then

                valid "user" "<p><b>Login inválido.</b></p>"
                valid "email" "<p><b>Email inválido.</b></p>"
                
                grep -E "^$user:" "$web_users_file" > /dev/null || { echo "<p><b>O login '$user' não foi encontrado.</b></p>" && end 1 ; }
                test "$(get_email "$user")" == "$email" > /dev/null || { echo "<p><b>O email informado não corresponde ao usuário '$user'.</b></p>" && end 1 ; }

                new_password="$(random_password "$user")"
                echo "$new_password" | mail -s "$web_app_name: nova senha" "$email" || { echo "<p><b>Não foi possível enviar a senha para o endereço '$email'.</b></p>" && end 1 ; }
                add_login "$user" "$new_password" || end 1
                
                echo "      <p><b>Foi gerada uma nova senha para o usuário '$user'. Favor verificar o email cadastrado.</b></p>"
                
            else
                echo "      <p><b>Todos os campos são obrigatórios.</b></p>"
            fi

            ;;
    
    esac

fi

end 0

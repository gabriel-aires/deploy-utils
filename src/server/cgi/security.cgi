#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

function membership() {

    if [ -n "$1" ]; then
        local user_regex="$(echo "$1" | sed -r 's|\.|\\.|' )"
        grep -Ex "[^:]+:.* +$user_regex +.*|[^:]+:$user_regex +.*|[^:]+:.* +$user_regex|[^:]+:$user_regex" "$apache_groups_file" | cut -f1 -d ':'
    else
        return 1
    fi

    return 0

}

function unsubscribe() {

    if [ -n "$1" ] && [ -n "$2" ]; then
        local user_regex="$(echo "$1" | sed -r 's|\.|\\.|' )"
        local group_regex="$(echo "$2" | sed -r 's|\.|\\.|' )"
        sed -r "s/^($group_regex:.* +)($user_regex +)(.*)$/\1\3/" "$apache_groups_file" > $tmp_dir/unsubscribe_tmp
        sed -i -r "s/^($group_regex:)($user_regex +)(.*)$/\1\3/" $tmp_dir/unsubscribe_tmp
        sed -i -r "s/^($group_regex:.* +)($user_regex)$/\1/" $tmp_dir/unsubscribe_tmp
        sed -r "s/^($group_regex:)($user_regex)$/\1/" $tmp_dir/unsubscribe_tmp > "$apache_groups_file"
    else
        return 1
    fi

    return 0

}

function subscribe() {

    if [ -n "$1" ] && [ -n "$2" ]; then
        local user"$1"
        local group_regex="$(echo "$2" | sed -r 's|\.|\\.|' )"
        sed -r "s/^($group_regex:.*)$/\1 $user/" "$apache_groups_file" > $tmp_dir/subscribe_tmp
        cp -f $tmp_dir/subscribe_tmp "$apache_groups_file"
    else
        return 1
    fi

    return 0

}

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
mklist "$ambientes" "$tmp_dir/lista_ambientes"
operation_erase="Remover"
operation_groups="Gerenciar Grupos"
operation_permissions="Gerenciar Permissões"
submit_continue="Continuar"
submit_erase_yes="Sim"
submit_erase_no="Nao"
submit_groups="Atualizar Grupos"

if [ -z "$POST_STRING" ]; then

    # Formulário de pesquisa
    echo "      <p>"
    echo "          <form action=\"$start_page\" method=\"post\">"
    # Usuário...
    echo "              <p>Gerenciar usuário:</p>"
    echo "              <p>"
    echo "                  <select class=\"select_default\" name=\"user\">"
    cut -f1 -d ':' $apache_users_file | sed -r "s|(.*)|\t\t\t\t\t\t<option>\1</option>|"
    echo "                  </select>"
    echo "              </p>"
    # Operação...
    echo "              <p>Operação:</p>"
    echo "              <input type=\"radio\" name=\"operation\" value=\"$operation_erase\"> $operation_erase<br>"
    echo "              <input type=\"radio\" name=\"operation\" value=\"$operation_groups\"> $operation_groups<br>"
    echo "              <input type=\"radio\" name=\"operation\" value=\"$operation_permissions\" checked> $operation_permissions<br>"
    # Submit
    echo "              <p><input type=\"submit\" name=\"submit\" value=\"$submit_continue\"></p>"
    echo "          </form>"
    echo "      </p>"

else

    arg_string="&$(web_filter "$POST_STRING")&"
    user="$(echo "$arg_string" | sed -rn "s/^.*&user=([^\&]+)&.*$/\1/p")"
    operation="$(echo "$arg_string" | sed -rn "s/^.*&operation=([^\&]+)&.*$/\1/p")"
    submit="$(echo "$arg_string" | sed -rn "s/^.*&submit=([^\&]+)&.*$/\1/p")"

    if [ -n "$user" ] && [ -n "$operation" ] && [ -n "$submit" ]; then

        case "$operation" in

            "$operation_erase")
                case "$submit" in

                    "$submit_continue")
                        echo "      <p>"
                        echo "          <b>Tem certeza de que deseja remover o usuário $user?</b>"
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        echo "              <input type=\"hidden\" name=\"user\" value=\"$user\"></td></tr>"
                        echo "              <input type=\"hidden\" name=\"operation\" value=\"$operation\"></td></tr>"
                        echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_erase_yes\">"
                        echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_erase_no\">"
                        echo "          </form>"
                        echo "      </p>"
                        ;;

                    "$submit_erase_yes")
                        htpasswd -D "$apache_users_file" "$user" || end 1
                        echo "      <p><b>Usuário $user removido.</b></p>"
                        ;;

                    "$submit_erase_no" )
                        echo "      <p><b>Remoção do usuário $user cancelada.</b></p>"
                        ;;

                esac
                ;;

            "$operation_groups")
                case "$submit" in

                    "$submit_continue")

                        cut -f1 -d ':' $apache_groups_file > $tmp_dir/groups_all
                        membership "$user" > $tmp_dir/groups_checked
                        grep -vxF --file=$tmp_dir/groups_checked $tmp_dir/groups_all > $tmp_dir/groups_unchecked

                        echo "      <p>"
                        echo "          Selecione os grupos desejados para o usuário $user:<br>"
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        echo "              <input type=\"hidden\" name=\"user\" value=\"$user\">"
                        echo "              <input type=\"hidden\" name=\"operation\" value=\"$operation\"></td></tr>"
                        cat "$tmp_dir/groups_checked" | sort | sed -r "s|(.*)|\t\t\t\t\t\t<input type=\"checkbox\" name=\"group\" value=\"\1\" checked>\1<br>|"
                        cat "$tmp_dir/groups_unchecked" | sort | sed -r "s|(.*)|\t\t\t\t\t\t<input type=\"checkbox\" name=\"group\" value=\"\1\">\1<br>|"
                        echo "              <p><input type=\"submit\" name=\"submit\" value=\"$submit_groups\"></p>"
                        echo "          </form>"
                        echo "      </p>"
                        ;;

                    "$submit_groups")

                        membership "$user" > $tmp_dir/groups_user
                        touch $tmp_dir/groups_checked
                        group="$(echo "$arg_string" | sed -rn "s/^.*&group=([^\&]+)&.*$/\1/p")"

                        while [ -n "$group" ]; do
                            echo "$group" >> $tmp_dir/groups_checked
                            arg_string="$(echo "$arg_string" | sed -r "s/&group=$group//")"
                            group="$(echo "$arg_string" | sed -rn "s/^.*&group=([^\&]+)&.*$/\1/p")"
                        done

                        grep -vxF --file=$tmp_dir/groups_checked $tmp_dir/groups_user > $tmp_dir/groups_unsubscribe

                        while read remove_group; do
                            unsubscribe "$user" "$remove_group"
                            echo "      <p>Usuário '$user' removido do grupo "$remove_group".</p>"
                        done < $tmp_dir/groups_unsubscribe

                        grep -vxF --file=$tmp_dir/groups_user $tmp_dir/groups_checked > $tmp_dir/groups_subscribe

                        while read add_group; do
                            subscribe "$user" "$add_group"
                            echo "      <p>Usuário '$user' adicionado ao grupo "$add_group".</p>"
                        done < $tmp_dir/groups_subscribe

                        echo "      <p><b>Grupos do usuário '$user' atualizados com sucesso!</b></p>"
                        ;;

                esac
                ;;

            "$operation_permissions")
                ;;

        esac

    fi

fi

end 0

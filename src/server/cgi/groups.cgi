#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

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
operation_add="Adicionar"
operation_erase="Remover"
operation_users="Gerenciar Membros"
operation_permissions="Gerenciar Permissoes"
submit_continue="Continuar"
submit_add="Criar Grupo"
submit_erase_yes="Sim"
submit_erase_no="Nao"
submit_users="Atualizar Membros"
submit_permission_add="Adicionar"
submit_permission_erase="Remover"
submit_permission_save="Salvar"

if [ -z "$POST_STRING" ]; then

    # Formulário de pesquisa
    echo "      <p>"
    echo "          <form action=\"$start_page\" method=\"post\">"
    # Usuário...
    echo "              <p>Gerenciar grupo:</p>"
    echo "              <p>"
    echo "                  <select class=\"select_default\" name=\"group\">"
    cut -f1 -d ':' $web_groups_file | sed -r "s|(.*)|\t\t\t\t\t\t<option>\1</option>|"
    echo "                  </select>"
    echo "              </p>"
    # Operação...
    echo "              <p>Operação:</p>"
    echo "              <input type=\"radio\" name=\"operation\" value=\"$operation_add\"> $operation_add<br>"
    echo "              <input type=\"radio\" name=\"operation\" value=\"$operation_erase\"> $operation_erase<br>"
    echo "              <input type=\"radio\" name=\"operation\" value=\"$operation_users\"> $operation_users<br>"
    echo "              <input type=\"radio\" name=\"operation\" value=\"$operation_permissions\" checked> $operation_permissions<br>"
    # Submit
    echo "              <p><input type=\"submit\" name=\"submit\" value=\"$submit_continue\"></p>"
    echo "          </form>"
    echo "      </p>"

else

    arg_string="&$(web_filter "$POST_STRING")&"
    group="$(echo "$arg_string" | sed -rn "s/^.*&group=([^\&]+)&.*$/\1/p")"
    operation="$(echo "$arg_string" | sed -rn "s/^.*&operation=([^\&]+)&.*$/\1/p")"
    submit="$(echo "$arg_string" | sed -rn "s/^.*&submit=([^\&]+)&.*$/\1/p")"

    if [ -n "$operation" ] && [ -n "$submit" ]; then

        case "$operation" in

            "$operation_add")
                case "$submit" in

                    "$submit_continue")
                        echo "      <p>"
                        echo "          <p>Nome do grupo:</p>"
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        echo "              <p><input type=\"text\" class=\"text_default\" name=\"group\"></input></p>"
                        echo "              <input type=\"hidden\" name=\"operation\" value=\"$operation\"></td></tr>"
                        echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_add\">"
                        echo "          </form>"
                        echo "      </p>"
                        ;;

                    "$submit_add")
                        valid "group" "<p><b>O nome do grupo é inválido: '$group'.</b></p>"
                        if grep -E "^$group:" "$web_groups_file" > /dev/null; then
                            echo "      <p><b>Já existe um grupo chamado '$group'. Favor escolher outro nome.</b></p>"
                        else
                            add_group "$group" && echo "      <p><b>Grupo '$group' adicionado com sucesso.</b></p>" || end 1
                        fi
                        ;;

                esac
                ;;

            "$operation_erase")
                case "$submit" in

                    "$submit_continue")
                        echo "      <p>"
                        echo "          <b>Tem certeza de que deseja remover o grupo '$group'? Os usuários abaixo serão afetados:</b>"
                        members_of "$group" | while read user; do
                            echo "          <p>'$user';</p>"
                        done
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        echo "              <input type=\"hidden\" name=\"group\" value=\"$group\"></td></tr>"
                        echo "              <input type=\"hidden\" name=\"operation\" value=\"$operation\"></td></tr>"
                        echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_erase_yes\">"
                        echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_erase_no\">"
                        echo "          </form>"
                        echo "      </p>"
                        ;;

                    "$submit_erase_yes")
                        delete_group "$group" && echo "      <p><b>Grupo '$group' removido.</b></p>" || end 1
                        ;;

                    "$submit_erase_no" )
                        echo "      <p><b>Remoção do grupo '$group' cancelada.</b></p>"
                        ;;

                esac
                ;;

            "$operation_users")
                case "$submit" in

                    "$submit_continue")

                        cut -f1 -d ':' $web_users_file > $tmp_dir/users_all
                        members_of "$group" > $tmp_dir/users_checked
                        grep -vxF --file=$tmp_dir/users_checked $tmp_dir/users_all > $tmp_dir/users_unchecked

                        echo "      <p>"
                        echo "          Selecione os membros do grupo '$group':<br>"
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        echo "              <input type=\"hidden\" name=\"group\" value=\"$group\">"
                        echo "              <input type=\"hidden\" name=\"operation\" value=\"$operation\"></td></tr>"
                        cat "$tmp_dir/users_checked" | sort | sed -r "s|(.*)|\t\t\t\t\t\t<input type=\"checkbox\" name=\"user\" value=\"\1\" checked>\1<br>|"
                        cat "$tmp_dir/users_unchecked" | sort | sed -r "s|(.*)|\t\t\t\t\t\t<input type=\"checkbox\" name=\"user\" value=\"\1\">\1<br>|"
                        echo "              <p><input type=\"submit\" name=\"submit\" value=\"$submit_users\"></p>"
                        echo "          </form>"
                        echo "      </p>"
                        ;;

                    "$submit_users")

                        members_of "$group" > $tmp_dir/users_group
                        touch $tmp_dir/users_checked
                        user="$(echo "$arg_string" | sed -rn "s/^.*&user=([^\&]+)&.*$/\1/p")"

                        while [ -n "$user" ]; do
                            echo "$user" >> $tmp_dir/users_checked
                            arg_string="$(echo "$arg_string" | sed -r "s/&user=$user//")"
                            user="$(echo "$arg_string" | sed -rn "s/^.*&user=([^\&]+)&.*$/\1/p")"
                        done

                        grep -vxF --file=$tmp_dir/users_checked $tmp_dir/users_group > $tmp_dir/users_unsubscribe

                        while read remove_user; do
                            unsubscribe "$remove_user" "$group"
                            echo "      <p>Usuário '$remove_user' removido do grupo "$group".</p>"
                        done < $tmp_dir/users_unsubscribe

                        grep -vxF --file=$tmp_dir/users_group $tmp_dir/users_checked > $tmp_dir/users_subscribe

                        while read add_user; do
                            subscribe "$add_user" "$group"
                            echo "      <p>Usuário '$add_user' adicionado ao grupo "$group".</p>"
                        done < $tmp_dir/users_subscribe

                        echo "      <p><b>Membros do grupo '$group' atualizados com sucesso!</b></p>"
                        ;;

                esac
                ;;

            "$operation_permissions")
                case "$submit" in

                    "$submit_continue")

                        touch "$tmp_dir/form_output"
                        erase_option=false

                        if [ "$(cat "$web_permissions_file" | wc -l)" -ge 2 ]; then
                            query_file.sh --delim "$delim" --replace-delim "</td><td>" --header 1 \
                                --select $col_resource_type $col_resource_name $col_permission \
                                --from "$web_permissions_file" \
                                --where $col_subject_type=='group' $col_subject_name=="$group" \
                                --order-by $col_resource_type $col_subject_name asc \
                                > $tmp_dir/permissions_group

                            if [ "$(cat "$tmp_dir/permissions_group" | wc -l)" -ge 1 ]; then
                                erase_option=true

                                query_file.sh --delim "$delim" --replace-delim "</th><th>" \
                                    --select $col_resource_type $col_resource_name $col_permission \
                                    --top 1 \
                                    --from "$web_permissions_file" \
                                    > $tmp_dir/permissions_header

                                sed -i -r "s|<th>$|</tr>|" "$tmp_dir/permissions_header"
                                sed -i -r 's|^(.*)$|<tr><th></th><th>\1|' "$tmp_dir/permissions_header"

                                sed -i -r "s|<td>$|</tr>|" "$tmp_dir/permissions_group"
                                sed -i -r "s|^(.*)$|<tr><td><input type=\"checkbox\" name=\"permission_string\" value=\"\1\"></td><td>\1|" "$tmp_dir/permissions_group"
                                sed -i -r "s|value=\"(.*)</td><td>(.*)</td><td>(.*)</td></tr>\">|value=\"group:$group:\1:\2:\3:\">|" "$tmp_dir/permissions_group"

                                echo "          </p>Permissões do grupo '$group':<p>" >> "$tmp_dir/form_output"
                                echo "          <table border=1>" >> "$tmp_dir/form_output"
                                cat "$tmp_dir/permissions_header" >> "$tmp_dir/form_output"
                                cat "$tmp_dir/permissions_group" >> "$tmp_dir/form_output"
                                echo "          </table>" >> "$tmp_dir/form_output"

                            else
                                echo "<p>Não há permissões registradas para o grupo '$group'.</p>"
                            fi

                        else
                            echo "<p>Não há permissões registradas.</p>"
                        fi

                        echo "      <p>"
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        cat "$tmp_dir/form_output"
                        echo "              <input type=\"hidden\" name=\"group\" value=\"$group\">"
                        echo "              <input type=\"hidden\" name=\"operation\" value=\"$operation\"></td></tr>"
                        echo "              <p>"
                        echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_permission_add\">"
                        test $erase_option && echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_permission_erase\">"
                        echo "              </p>"
                        echo "          </form>"
                        echo "      </p>"
                        ;;

                    "$submit_permission_add")

                        # Formulário de permissão.
                        echo "      <p>"
                        echo "          Editando permissões para o grupo '$group'<br>"
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        # Tipo de recurso
                        echo "              <p>"
                        echo "                  Tipo de recurso:<br>"
                        echo "      		    <select class=\"select_default\" name=\"resource_type\">"
                        mklist "$regex_resource_type" | while read resource_type; do
                            echo "		        	<option>$resource_type</option>"
                        done
                        echo "		            </select>"
                        echo "              </p>"
                        # Nome do recurso
                        echo "              <p>"
                        echo "                  Nome do recurso:<br>"
                        echo "                  <input type=\"text\" class=\"text_default\" name=\"resource_name\"></input>"
                        echo "              </p>"
                        # Permissão
                        echo "              <p>"
                        echo "                  Permissão:<br>"
                        echo "      		    <select class=\"select_default\" name=\"permission\">"
                        mklist "$regex_permission" | while read permission; do
                            echo "		        	<option>$permission</option>"
                        done
                        echo "		            </select>"
                        echo "              </p>"
                        echo "              <input type=\"hidden\" name=\"group\" value=\"$group\">"
                        echo "              <input type=\"hidden\" name=\"operation\" value=\"$operation\">"
                        echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_permission_save\">"
                        echo "          </form>"
                        echo "      </p>"
                        ;;

                    "$submit_permission_save")

                        resource_type="$(echo "$arg_string" | sed -rn "s/^.*&resource_type=([^\&]+)&.*$/\1/p")"
                        resource_name="$(echo "$arg_string" | sed -rn "s/^.*&resource_name=([^\&]+)&.*$/\1/p")"
                        permission="$(echo "$arg_string" | sed -rn "s/^.*&permission=([^\&]+)&.*$/\1/p")"
                        add_permission "group" "$group" "$resource_type" "$resource_name" "$permission" || end 1
                        echo "      <p><b>Permissão adicionada com sucesso para o grupo '$group'.</b></p>"
                        ;;

                    "$submit_permission_erase")

                        permission_string="$(echo "$arg_string" | sed -rn "s/^.*&permission_string=([^\&]+)&.*$/\1/p")"

                        while [ -n "$permission_string" ]; do
                            subject_type="$(echo "$permission_string" | cut -f1 -d ":")"
                            subject_name="$(echo "$permission_string" | cut -f2 -d ":")"
                            resource_type="$(echo "$permission_string" | cut -f3 -d ":")"
                            resource_name="$(echo "$permission_string" | cut -f4 -d ":")"
                            permission="$(echo "$permission_string" | cut -f5 -d ":")"

                            delete_permission "$subject_type" "$subject_name" "$resource_type" "$resource_name" "$permission" || end 1
                            echo "      <p>Permissão '$resource_type;$resource_name;$permission' removida para o grupo '$group'.</p>"

                            arg_string="$(echo "$arg_string" | sed -r "s/&permission_string=$permission_string//")"
                            permission_string="$(echo "$arg_string" | sed -rn "s/^.*&permission_string=([^\&]+)&.*$/\1/p")"

                        done

                        echo "      <p></b>Permissões selecionadas removidas com sucesso.</b></p>"
                        ;;
                esac
                ;;
        esac

    fi

fi

end 0

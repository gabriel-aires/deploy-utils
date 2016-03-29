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
operation_add="Adicionar"
operation_erase="Remover"
operation_agents="Gerenciar Agentes"
operation_apps="Gerenciar Aplicacoes"
submit_continue="Continuar"
submit_add="Adicionar"
submit_edit="Configurar"
submit_save="Salvar"
submit_erase="Remover"
submit_erase_yes="Sim"
submit_erase_no="Nao"

valid "upload_dir" "<p><b>Erro. Caminho inválido para o diretório de upload.</b></p>"
valid "agent_conf_dir" "<p><b>Erro. Caminho inválido para o diretório de configuração de agentes.</b></p>"
test ! -d "$upload_dir" && "<p><b>Erro. Diretório de upload inexistente.</b></p>" && end 1
test ! -w "$upload_dir" && "<p><b>Erro. Permissões insuficientes no diretório de upload.</b></p>" && end 1
test ! -d "$agent_conf_dir" && "<p><b>Erro. Diretório de configuração de agentes inexistente.</b></p>" && end 1
test ! -w "$agent_conf_dir" && "<p><b>Erro. Permissões insuficientes no diretório de configuração de agentes.</b></p>" && end 1

if [ -z "$POST_STRING" ]; then

    # Formulário de pesquisa
    echo "      <p>"
    echo "          <form action=\"$start_page\" method=\"post\">"
    # Host...
    echo "              <p>Gerenciar host:</p>"
    echo "              <p>"
    echo "                  <select class=\"select_default\" name=\"host\">"
    find $agent_conf_dir/ -mindepth 1 -maxdepth 1 -type d | sort | xargs -I{} -d '\n' basename {} | sed -r "s|(.*)|\t\t\t\t\t\t<option>\1</option>|"
    echo "                  </select>"
    echo "              </p>"
    # Operação...
    echo "              <p>Operação:</p>"
    echo "              <input type=\"radio\" name=\"operation\" value=\"$operation_add\"> $operation_add<br>"
    echo "              <input type=\"radio\" name=\"operation\" value=\"$operation_erase\"> $operation_erase<br>"
    echo "              <input type=\"radio\" name=\"operation\" value=\"$operation_agents\"> $operation_agents<br>"
    echo "              <input type=\"radio\" name=\"operation\" value=\"$operation_apps\"> $operation_apps<br>"
    # Submit
    echo "              <p><input type=\"submit\" name=\"submit\" value=\"$submit_continue\"></p>"
    echo "          </form>"
    echo "      </p>"

else

    arg_string="&$(web_filter "$POST_STRING")&"
    host="$(echo "$arg_string" | sed -rn "s/^.*&host=([^\&]+)&.*$/\1/p")"
    operation="$(echo "$arg_string" | sed -rn "s/^.*&operation=([^\&]+)&.*$/\1/p")"
    submit="$(echo "$arg_string" | sed -rn "s/^.*&submit=([^\&]+)&.*$/\1/p")"
    agent_conf="$(echo "$arg_string" | sed -rn "s/^.*&agent_conf=([^\&]+)&.*$/\1/p")"
    agent_template="$(echo "$arg_string" | sed -rn "s/^.*&agent_template=([^\&]+)&.*$/\1/p")"

    if [ -n "$operation" ] && [ -n "$submit" ]; then

        case "$operation" in

            "$operation_add")
                case "$submit" in

                    "$submit_continue")
                        echo "      <p>"
                        echo "          <p>Hostname:</p>"
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        echo "              <p><input type=\"text\" class=\"text_default\" name=\"host\"></input></p>"
                        echo "              <input type=\"hidden\" name=\"operation\" value=\"$operation\"></td></tr>"
                        echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_add\">"
                        echo "          </form>"
                        echo "      </p>"
                        ;;

                    "$submit_add")
                        valid "host" "<p><b>O hostname é inválido: '$hostname'.</b></p>"
                        if find $agent_conf_dir/ -mindepth 1 -maxdepth 1 -type d | grep -Ex "$host" > /dev/null; then
                            echo "      <p><b>Já existe um host chamado '$host'. Favor escolher outro nome.</b></p>"
                        else
                            mkdir "$agent_conf_dir/$host" && echo "      <p><b>Host '$host' adicionado com sucesso.</b></p>" || end 1
                        fi
                        ;;

                esac
                ;;

            "$operation_erase")
                case "$submit" in

                    "$submit_continue")
                        echo "      <p>"
                        echo "          <b>Tem certeza de que deseja remover o host '$host'? As configurações abaixo serão deletadas:</b>"
                        find $agent_conf_dir/$host/ -mindepth 1 -maxdepth 1 -type f -iname '*.conf' | xargs -r -I{} basename {} | while read conf; do
                            echo "          <p>'$conf';</p>"
                        done
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        echo "              <input type=\"hidden\" name=\"host\" value=\"$host\"></td></tr>"
                        echo "              <input type=\"hidden\" name=\"operation\" value=\"$operation\"></td></tr>"
                        echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_erase_yes\">"
                        echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_erase_no\">"
                        echo "          </form>"
                        echo "      </p>"
                        ;;

                    "$submit_erase_yes")
                        rm -f $agent_conf_dir/$host/* || end 1
                        rmdir $agent_conf_dir/$host || end 1
                        echo "      <p><b>Host '$host' removido.</b></p>"
                        ;;

                    "$submit_erase_no" )
                        echo "      <p><b>Remoção do host '$host' cancelada.</b></p>"
                        ;;

                esac
                ;;

            "$operation_agents")
                case "$submit" in

                    "$submit_continue")

                        echo "      <p>"
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        echo "              <p>"
                        echo "                  Parâmetros de agente: "
                        echo "                  <select class=\"select_default\" name=\"agent_conf\">"
                        echo "		                <option value=\"\" selected>Adicionar...</option>"
                        find $agent_conf_dir/$host/ -mindepth 1 -maxdepth 1 -type f -name '*.conf' | sort | xargs -I{} -d '\n' basename {} | cut -d '.' -f1 | sed -r "s|(.*)|\t\t\t\t\t\t<option>\1</option>|"
                        echo "                  </select>"
                        echo "              </p>"
                        echo "              <p>"
                        echo "                  <input type=\"hidden\" name=\"host\" value=\"$host\">"
                        echo "                  <input type=\"hidden\" name=\"operation\" value=\"$operation\">"
                        echo "                  <input type=\"submit\" name=\"submit\" value=\"$submit_edit\">"
                        echo "              </p>"
                        echo "          </form>"
                        echo "      </p>"
                        ;;

                    "$submit_edit")

                        if [ -z "$agent_conf" ]; then

                            echo "      <p>"
                            echo "          <p>Adicionar nova configuração...</p>"
                            echo "          <form action=\"$start_page\" method=\"post\">"
                            echo "              <table>"
                            echo "                  <tr>"
                            echo "                      <td>Agente: </td>"
                            echo "                      <td>"
                            echo "                          <select class=\"select_default\" name=\"agent_template\">"
                            find $src_dir/agents/template/ -mindepth 1 -maxdepth 1 -type f -name '*.template' | sort | xargs -I{} -d '\n' basename {} | cut -d '.' -f1 | grep -Exv "agent|global" | sed -r "s|(.*)|\t\t\t\t\t\t<option>\1</option>|"
                            echo "                          </select>"
                            echo "                      </td>"
                            echo "                  <tr>"
                            echo "                  <tr>"
                            echo "                      <td>Nome: </td>"
                            echo "                      <td>"
                            echo "                          <input type=\"text\" class=\"text_default\" name=\"agent_conf\">"
                            echo "                      </td>"
                            echo "                  <tr>"
                            echo "              </table>"
                            echo "              <p>"
                            echo "                  <input type=\"hidden\" name=\"host\" value=\"$host\">"
                            echo "                  <input type=\"hidden\" name=\"operation\" value=\"$operation\">"
                            echo "                  <input type=\"submit\" name=\"submit\" value=\"$submit_edit\">"
                            echo "              </p>"
                            echo "          </form>"
                            echo "      </p>"

                        else

                            test -f "$agent_conf_dir/$host/$agent_conf.conf" && form_file="$agent_conf_dir/$host/$agent_conf.conf" || form_file="$src_dir/agents/template/$agent_template.template"

                            echo "      <p>"
                            echo "          <p>Modificar arquivo de configuração '$agent_conf.conf':</p>"
                            echo "          <form action=\"$start_page\" method=\"post\">"
                            echo "              <table frame=box class=\"cfg_table\">"
                            while read l; do
                                key="$(echo "$l" | cut -f1 -d '=')"
                                value="$(echo "$l" | sed -rn "s/^[^\=]+=//p" | sed -r "s/'//g" | sed -r 's/"//g')"
                                if echo "$key" | grep -E "^#" > /dev/null; then
                                    echo "               <tr><td colspan=\"2\">$key</td></tr>"
                                elif [ "$key" == "agent_name" ]; then
                                    if [ -z "$value" ]; then
                                        echo "               <tr><td>$key: </td><td><input type=\"text\" disabled size=\"100\" name=\"$key\" value=\"$agent_template\"></td></tr>"
                                    else
                                        echo "               <tr><td>$key: </td><td><input type=\"text\" disabled size=\"100\" name=\"$key\" value=\"$value\"></td></tr>"
                                    fi
                                else
                                    echo "               <tr><td>$key: </td><td><input type=\"text\" size=\"100\" name=\"$key\" value=\"$value\"></td></tr>"
                                fi
                            done < "$form_file"
                            echo "                  <tr>"
                            echo "                      <td>"
                            echo "                          <input type=\"hidden\" name=\"host\" value=\"$host\">"
                            echo "                          <input type=\"hidden\" name=\"operation\" value=\"$operation\">"
                            echo "                          <input type=\"hidden\" name=\"agent_conf\" value=\"$agent_conf\">"
                            echo "                          <input type=\"hidden\" name=\"agent_template\" value=\"$agent_template\">"
                            echo "                          <input type=\"submit\" name=\"submit\" value=\"$submit_save\">"
                            echo "                          <input type=\"submit\" name=\"submit\" value=\"$submit_erase\">"
                            echo "                      </td>"
                            echo "                  </tr>"
                            echo "              </table>"
                            echo "          </form>"
                            echo "      </p>"

                        fi
                        ;;

                    "$submit_save")

                        test -f "$agent_conf_dir/$host/$agent_conf.conf" || cp "$src_dir/agents/template/$agent_template.template" "$agent_conf_dir/$host/$agent_conf.conf"
                        lock "${host}_${agent_conf}" "Arquivo de configuração '$agent_conf.conf' do host '$host' bloqueado para para edição."

                        while read l; do
                            if echo "$l" | grep -Ev "^#" > /dev/null; then
                                key="$(echo "$l" | cut -f1 -d '=')"
                                if [ "$key" == "agent_name" ]; then
                                    value="$(echo "$l" | sed -rn "s/^[^\=]+=//p" | sed -r "s/'//g" | sed -r 's/"//g')"
                                    test -z "$value" && new_value="$agent_template" || new_value="$value"
                                else
                                    new_value="$(echo "$arg_string" | sed -rn "s/^.*&$key=([^\&]+)&.*$/\1/p" | sed -r "s/'//g" | sed -r 's/"//g')"
                                fi
                                editconf "$key" "$new_value" "$agent_conf_dir/$host/$agent_conf.conf"
                            fi
                        done < "$agent_conf_dir/$host/$agent_conf.conf"

                        echo "      <p><b>Arquivo de configuração '$agent_conf.conf' atualizado.</b></p>"
                        ;;

                    "$submit_erase")
                        echo "      <p>"
                        echo "          <b>Tem certeza de que deseja remover o arquivo de configuração '$agent_conf.conf'?</b>"
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        echo "              <input type=\"hidden\" name=\"host\" value=\"$host\">"
                        echo "              <input type=\"hidden\" name=\"operation\" value=\"$operation\">"
                        echo "              <input type=\"hidden\" name=\"agent_conf\" value=\"$agent_conf\">"
                        echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_erase_yes\">"
                        echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_erase_no\">"
                        echo "          </form>"
                        echo "      </p>"
                        ;;

                    "$submit_erase_yes")
                        rm -f "$agent_conf_dir/$host/$agent_conf.conf" || end 1
                        echo "      <p><b>Arquivo de configuração '$agent_conf.conf' removido.</b></p>"
                        ;;

                    "$submit_erase_no")
                        echo "      <p><b>Remoção do arquivo de configuração '$agent_conf.conf' cancelada.</b></p>"
                        ;;

                esac
                ;;

            "$operation_apps")
                case "$submit" in

                    "$submit_continue")

                        echo "      <p>"
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        echo "              <p>"
                        echo "                  Selecionar configuração: "
                        echo "                  <select class=\"select_default\" name=\"agent_conf\">"
                        find $agent_conf_dir/$host/ -mindepth 1 -maxdepth 1 -type f -name '*.conf' | sort | xargs -I{} -d '\n' basename {} | cut -d '.' -f1 | sed -r "s|(.*)|\t\t\t\t\t\t<option>\1</option>|"
                        echo "                  </select>"
                        echo "              </p>"
                        echo "              <p>"
                        echo "                  <input type=\"hidden\" name=\"host\" value=\"$host\">"
                        echo "                  <input type=\"hidden\" name=\"operation\" value=\"$operation\">"
                        echo "                  <input type=\"submit\" name=\"submit\" value=\"$submit_edit\">"
                        echo "              </p>"
                        echo "          </form>"
                        echo "      </p>"
                        ;;

                    "$submit_edit")

                        error=false
                        i=0
                        path_id_regex=''
                        upload_path="$upload_dir"

                        while [ "$i" -lt "$qtd_dir" ]; do
                            ((i++)) && path_id_regex="$path_id_regex|$(eval "echo \$dir_$i")"
                        done

                        path_id_regex="$(echo "$path_id_regex" | sed -r "s/^\|//")"

                        while read l; do
                            echo "$(echo "$l" | cut -f1 -d '=')" | grep -Exv "$path_id_regex" > /dev/null && continue
                            subdir="$(echo "$l" | sed -rn "s/^[^\=]+=//p" | sed -r "s/'//g" | sed -r 's/"//g')"
                            test -z "$subdir" && error=true && break
                            upload_path="$path/$subdir"
                        done < "$agent_conf_dir/$host/$agent_conf.conf"

                        if ! "$error"; then

                            echo "      <p>"
                            echo "          Diretórios de aplicação associados à configuração '$agent_conf.conf':<br>"
                            echo "          <form action=\"$start_page\" method=\"post\">"
                            echo "              <input type=\"hidden\" name=\"host\" value=\"$host\">"
                            echo "              <input type=\"hidden\" name=\"operation\" value=\"$operation\">"
                            echo "              <input type=\"hidden\" name=\"agent_conf\" value=\"$agent_conf\">"
                            find $upload_path/ -mindepth 2 -maxdepth 2 | sort | sed -r "s|^$upload_dir(.*)$|\t\t\t\t\t\t<input type=\"checkbox\" name=\"upload_subpath\" value=\"\1\">\1<br>|"
                            echo "              <p>"
                            echo "                  <input type=\"submit\" name=\"submit\" value=\"$submit_add\"> "
                            echo "                  <input type=\"submit\" name=\"submit\" value=\"$submit_erase\">"
                            echo "              </p>"
                            echo "          </form>"
                            echo "      </p>"

                        else
                            echo "      <p><b>Erro. O mapeamento de diretórios do arquivo "$agent_conf_dir/$host/$agent_conf.conf" está incompleto.</b></p>"
                        fi
                        ;;

                    "$submit_erase")

                        upload_subpath="$(echo "$arg_string" | sed -rn "s/^.*&upload_subpath=([^\&]+)&.*$/\1/p")"

                        while [ -n "$upload_subpath" ]; do
                            upload_path="$upload_dir/$upload_subpath"
                            rm -f "$upload_path"/*
                            rmdir "$upload_path"
                            rmdir $(dirname $upload_path) &> /dev/null
                            echo "      <p>Diretório '$upload_subpath' removido .</p>"
                            arg_string="$(echo "$arg_string" | sed -r "s|&upload_subpath=$upload_subpath||")"
                            upload_subpath="$(echo "$arg_string" | sed -rn "s/^.*&upload_subpath=([^\&]+)&.*$/\1/p")"
                        done
                        ;;

                    "$submit_add")

                        echo "      <p>"
                        echo "          <p>Aplicação:</p>"
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        echo "              <p><input type=\"text\" class=\"text_default\" name=\"app\"></input></p>"
                        echo "              <p>"
                        echo "                  <input type=\"checkbox\" name=\"enable_deploy\" value=\"true\"> Deploy<br>"
                        echo "                  <input type=\"checkbox\" name=\"enable_log\" value=\"true\"> Log<br>"
                        echo "              </p>"
                        echo "              <input type=\"hidden\" name=\"host\" value=\"$host\">"
                        echo "              <input type=\"hidden\" name=\"operation\" value=\"$operation\">"
                        echo "              <input type=\"hidden\" name=\"upload_subpath\" value=\"$upload_subpath\">"
                        echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_save\">"
                        echo "          </form>"
                        echo "      </p>"
                        ;;

                    "$submit_save")

                        enable_log=false
                        enable_deploy=false
                        dir_created=false

                        upload_subpath="$(echo "$arg_string" | sed -rn "s/^.*&upload_subpath=([^\&]+)&.*$/\1/p")"
                        enable_log="$(echo "$arg_string" | sed -rn "s/^.*&enable_log=([^\&]+)&.*$/\1/p")"
                        enable_deploy="$(echo "$arg_string" | sed -rn "s/^.*&enable_deploy=([^\&]+)&.*$/\1/p")"

                        upload_path="$upload_dir/$upload_subpath"

                        $enable_log && mkdir -p "$upload_path/$app/log" && echo "<p>Diretório '$upload_path/$app/log' criado.</p>" && dir_created=true
                        $enable_log && mkdir -p "$upload_path/$app/deploy" && echo "<p>Diretório '$upload_path/$app/deploy' criado.</p>" && dir_created=true
                        $dir_created || echo "<p>Nenhum diretório adicionado para a aplicação '$app'.</p>"
                        ;;

                esac
                ;;

        esac

    fi

fi

end 0

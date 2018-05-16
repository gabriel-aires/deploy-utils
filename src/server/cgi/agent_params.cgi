#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

function get_path_id_regex() {

    local i=0
    local path_id=''
    path_id_regex=''

    while [ "$i" -lt "${#dir[@]}" ]; do        
        path_id_regex="${path_id_regex}|${dir[$i]}"
        ((i++))
    done

    path_id_regex="$(echo "$path_id_regex" | sed -r "s/^\|//")"

}

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
qtd_dir="${#dir[@]}"

valid "$upload_dir" "upload_dir" "<p><b>Erro. Caminho inválido para o diretório de upload.</b></p>" || end 1
valid "$agent_conf_dir" "agent_conf_dir" "<p><b>Erro. Caminho inválido para o diretório de configuração de agentes.</b></p>" || end 1
test ! -d "$upload_dir" && "<p><b>Erro. Diretório de upload inexistente.</b></p>" && end 1
test ! -w "$upload_dir" && "<p><b>Erro. Permissões insuficientes no diretório de upload.</b></p>" && end 1
test ! -d "$agent_conf_dir" && "<p><b>Erro. Diretório de configuração de agentes inexistente.</b></p>" && end 1
test ! -w "$agent_conf_dir" && "<p><b>Erro. Permissões insuficientes no diretório de configuração de agentes.</b></p>" && end 1
test ! -n "${regex[bool]}" && "<p><b>Erro. A expressão regular 'regex_bool' não foi definida.</b></p>" && end 1
test ! -n "${regex[ambiente]}" && "<p><b>Erro. A expressão regular 'regex_ambiente' não foi definida.</b></p>" && end 1
test ! -n "${regex[agent_interval]}" && "<p><b>Erro. A expressão regular 'regex_agent_interval' não foi definida.</b></p>" && end 1

if [ -z "$POST_STRING" ]; then

    # Formulário de pesquisa
    echo "      <p>"
    echo "          <form action=\"$start_page\" method=\"post\">"
    # Host...
    echo "              <p>Gerenciar host:</p>"
    echo "              <p>"
    echo "                  <select class=\"select_default\" name=\"host\">"
    echo "		                <option value=\"\" selected>Selecionar Host...</option>"
    find $agent_conf_dir/ -mindepth 1 -maxdepth 1 -type d | sort | xargs -I{} -d '\n' basename {} | sed -r "s|(.*)|\t\t\t\t\t\t<option>\1</option>|"
    echo "                  </select>"
    echo "              </p>"
    # Operação...
    echo "              <p>Operação:</p>"
    echo "              <input type=\"radio\" name=\"operation\" value=\"$operation_add\" checked> $operation_add<br>"
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
    upload_path="$(echo "$arg_string" | sed -rn "s|^.*&upload_path=([^\&]+)&.*$|\1|p")"
    app_subpath="$(echo "$arg_string" | sed -rn "s|^.*&app_subpath=([^\&]+)&.*$|\1|p")"
    enable_log="$(echo "$arg_string" | sed -rn "s/^.*&enable_log=([^\&]+)&.*$/\1/p")"
    enable_deploy="$(echo "$arg_string" | sed -rn "s/^.*&enable_deploy=([^\&]+)&.*$/\1/p")"
    app="$(echo "$arg_string" | sed -rn "s|^.*&app=([^\&]+)&.*$|\1|p")"

    if [ -n "$operation" ] && [ -n "$submit" ]; then

        if [ -n "$host" ]; then
            valid "$host" "host" "<p><b>O hostname é inválido: '$host'.</b></p>" || end 1
            lock "edit_agent_$host" "<p><b>Host $host bloqueado para edição</b></p>" || end 1
            test "$operation" == "$operation_add" || test "$operation" == "$operation_erase" || echo "<p>Host: <b>$host</b></p>"
            running_tasks="$(find "$lock_dir"/ -maxdepth 1 -type f -name "run_agent_${host}_*" | wc -l)"
        fi

        case "$operation" in

            "$operation_add")
                case "$submit" in

                    "$submit_continue")
                        echo "      <p>"
                        echo "          <p>Hostname:</p>"
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        echo "              <p><input type=\"text\" class=\"text_default\" name=\"host\"></input></p>"
                        echo "              <input type=\"hidden\" name=\"operation\" value=\"$operation\">"
                        echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_add\">"
                        echo "          </form>"
                        echo "      </p>"
                        ;;

                    "$submit_add")
                        test -n "$host" || end 1
                        if find $agent_conf_dir/ -mindepth 1 -maxdepth 1 -type d | grep -Ex "$agent_conf_dir/$host" > /dev/null; then
                            echo "      <p><b>Já existe um host chamado '$host'. Favor escolher outro nome.</b></p>"
                        else
                            mkdir "$agent_conf_dir/$host" && echo "      <p><b>Host '$host' adicionado com sucesso.</b></p>" || end 1
                        fi
                        ;;

                esac
                ;;

            "$operation_erase")
                test -n "$host" || end 1
                test -d "$agent_conf_dir/$host" || end 1

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

                        test "$running_tasks" -ge 1 && echo "Há $running_tasks tarefas em execução no host $host. Favor desabilitar os respectivos agentes antes de prosseguir." && end 0
                        rm -f "$agent_conf_dir"/"$host"/* || end 1
                        rmdir "$agent_conf_dir"/"$host" || end 1
                        find "$upload_dir/" -mindepth "$qtd_dir" -maxdepth "$qtd_dir" -type d -name "$host" | xargs -r -d '\n' rm -Rf || end 1
                        echo "      <p><b>Host '$host' removido.</b></p>"
                        ;;

                    "$submit_erase_no" )

                        echo "      <p><b>Remoção do host '$host' cancelada.</b></p>"
                        ;;

                esac
                ;;

            "$operation_agents")
                test -n "$host" || end 1
                test -d "$agent_conf_dir/$host" || end 1

                case "$submit" in

                    "$submit_continue")

                        echo "      <p>"
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        echo "              <p>Parâmetros de agente: </p>"
                        echo "              <p>"
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
                            echo "              <div class=\"column zero_padding cfg_color box_shadow\">"
                            echo "                  <table>"
                            echo "                      <tr>"
                            echo "                          <td>Agente: </td>"
                            echo "                          <td>"
                            echo "                              <select class=\"select_default\" name=\"agent_template\">"
                            echo "  		                        <option value=\"\" selected>Selecionar template...</option>"
                            find $src_dir/agents/template/ -mindepth 1 -maxdepth 1 -type f -name '*.template' | sort | xargs -I{} -d '\n' basename {} | cut -d '.' -f1 | grep -Exv "agent|global|service" | sed -r "s|(.*)|\t\t\t\t\t\t<option>\1</option>|"
                            echo "                              </select>"
                            echo "                          </td>"
                            echo "                      </tr>"
                            echo "                      <tr>"
                            echo "                          <td>Nome: </td>"
                            echo "                          <td>"
                            echo "                              <input type=\"text\" class=\"text_default\" name=\"agent_conf\">"
                            echo "                          </td>"
                            echo "                      </tr>"
                            echo "                  </table>"
                            echo "              </div>"
                            echo "              <p>"
                            echo "                  <input type=\"hidden\" name=\"host\" value=\"$host\">"
                            echo "                  <input type=\"hidden\" name=\"operation\" value=\"$operation\">"
                            echo "                  <input type=\"submit\" name=\"submit\" value=\"$submit_edit\">"
                            echo "              </p>"
                            echo "          </form>"
                            echo "      </p>"

                        else

                            if [ -f "$agent_conf_dir/$host/$agent_conf.conf" ]; then
                                form_file="$agent_conf_dir/$host/$agent_conf.conf"
                            elif [ -n "$agent_template" ] && [ -f "$src_dir/agents/template/$agent_template.template" ]; then
                                form_file="$src_dir/agents/template/$agent_template.template"
                            else
                                end 1
                            fi

                            get_path_id_regex

                            echo "      <p>"
                            echo "          <p>Modificar arquivo de configuração '$agent_conf.conf':</p>"
                            echo "          <form action=\"$start_page\" method=\"post\">"
                            echo "              <div class=\"column zero_padding cfg_color box_shadow\">"
                            echo "                  <table>"

                            while read l; do
                                echo "              <tr>"
                                key="$(echo "$l" | cut -f1 -d '=')"
                                value="$(echo "$l" | sed -rn "s/^[^\=]+=//p" | sed -r "s/'//g" | sed -r 's/"//g')"

                                if echo "$key" | grep -E "^#" > /dev/null; then
                                    echo "                      <td colspan=\"2\">$key</td>"

                                else
                                    echo "                      <td>$key:</td>"
                                    echo "                      <td>"

                                    field_tag="input"
                                    field_type="text"
                                    field_attributes="class=\"text_large\" name=\"$key\""
                                    field_disabled=false

                                    case "$key" in

                                        'hostname')
                                            test -z "$value" && value="$host"
                                            field_disabled=true
                                            ;;

                                        'agent_name')
                                            test -z "$value" && value="$agent_template"
                                            field_disabled=true
                                            ;;

                                        'password')
                                            field_type="password"
                                            ;;

                                        'ambiente')
                                            field_tag="select"
                                            field_attributes="class=\"select_large\" name=\"$key\""
                                            test -n "$value" && field_disabled=true && field_attributes="$field_attributes disabled"
                                            echo "                      <$field_tag $field_attributes>"
                                            echo "                          <option value=\"\">selecionar...</option>"
                                            mklist "${regex[ambiente]}" | while read option; do
                                                test "$option" == "$value" && echo "                          <option selected>$value</option>" || echo "                      <option>$option</option>"
                                            done
                                            echo "                      </$field_tag>"
                                            ;;

                                        'run_deploy_agent'|'run_log_agent')
                                            test -z "$value" && value="true"
                                            field_tag="select"
                                            field_attributes="class=\"select_large\" name=\"$key\""
                                            echo "                      <$field_tag $field_attributes>"
                                            mklist "${regex[bool]}" | while read option; do
                                                test "$option" == "$value" && echo "                 <option selected>$value</option>" || echo "               <option>$option</option>"
                                            done
                                            echo "                      </$field_tag>"
                                            ;;

                                        'deploy_interval'|'log_interval')
                                            test -z "$value" && value="15"
                                            field_tag="select"
                                            field_attributes="class=\"select_large\" name=\"$key\""
                                            echo "                      <$field_tag $field_attributes>"
                                            mklist "${regex[agent_interval]}" | while read option; do
                                                test "$option" == "$value" && echo "                   <option selected>$value</option>" || echo "               <option>$option</option>"
                                            done
                                            echo "                      </$field_tag>"
                                            ;;

                                        *)
                                            echo "$key" | grep -Ex "$path_id_regex" > /dev/null && test -n "$value" && field_disabled=true
                                            ;;

                                    esac

                                    $field_disabled && field_attributes="$field_attributes disabled" && echo "                    <input type=\"hidden\" name=\"$key\" value=\"$value\">"
                                    test "$field_tag" == "input" && echo "                      <$field_tag type=\"$field_type\" $field_attributes value=\"$value\">"

                                    echo "                      <td>"
                                fi

                                echo "                  </tr>"

                            done < "$form_file"

                            echo "                      <tr>"
                            echo "                          <td>"
                            echo "                              <input type=\"hidden\" name=\"host\" value=\"$host\">"
                            echo "                              <input type=\"hidden\" name=\"operation\" value=\"$operation\">"
                            echo "                              <input type=\"hidden\" name=\"agent_conf\" value=\"$agent_conf\">"
                            echo "                              <input type=\"hidden\" name=\"agent_template\" value=\"$agent_template\">"
                            echo "                              <input type=\"submit\" name=\"submit\" value=\"$submit_save\">"
                            echo "                              <input type=\"submit\" name=\"submit\" value=\"$submit_erase\">"
                            echo "                          </td>"
                            echo "                      </tr>"
                            echo "                  </table>"
                            echo "              </div>"
                            echo "          </form>"
                            echo "      </p>"

                        fi
                        ;;

                    "$submit_save")

                        error=false
                        test -f "$agent_conf_dir/$host/$agent_conf.conf" || cp "$src_dir/agents/template/$agent_template.template" "$agent_conf_dir/$host/$agent_conf.conf"

                        while read l; do
                            if echo "$l" | grep -Ev "^#" > /dev/null; then
                                key="$(echo "$l" | cut -f1 -d '=')"
                                new_value="$(echo "$arg_string" | sed -rn "s/^.*&$key=([^\&]*)&.*$/\1/p" | sed -r "s/'//g" | sed -r 's/"//g')"
                                editconf "$key" "$new_value" "$agent_conf_dir/$host/$agent_conf.conf" || { error=true ; break ; }
                            fi
                        done < "$agent_conf_dir/$host/$agent_conf.conf"

                        $error && end 1
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

                        test "$running_tasks" -ge 1 && echo "Há $running_tasks tarefas em execução no host $host. Favor desabilitar os respectivos agentes antes de prosseguir." && end 0
                        rm -f "$agent_conf_dir/$host/$agent_conf.conf" || end 1
                        echo "      <p><b>Arquivo de configuração '$agent_conf.conf' removido.</b></p>"
                        ;;

                    "$submit_erase_no")

                        echo "      <p><b>Remoção do arquivo de configuração '$agent_conf.conf' cancelada.</b></p>"
                        ;;

                esac
                ;;

            "$operation_apps")
                test -n "$host" || end 1
                test -d "$agent_conf_dir/$host" || end 1

                case "$submit" in

                    "$submit_continue")

                        echo "      <p>"
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        echo "              <p>"
                        echo "                  <select class=\"select_default\" name=\"agent_conf\">"
                        echo "		                <option value=\"\" selected>Selecionar Configuração...</option>"
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

                        test -n "$agent_conf" && echo "      <p>Configuração selecionada: <b>$agent_conf</b></p>" || end 1
                        error=false

                        get_path_id_regex

                        upload_path="$upload_dir"
                        while read l; do
                            echo "$(echo "$l" | cut -f1 -d '=')" | grep -Exv "$path_id_regex" > /dev/null && continue
                            subdir="$(echo "$l" | sed -rn "s/^[^\=]+=//p" | sed -r "s/'//g" | sed -r 's/"//g')"
                            test -z "$subdir" && error=true && break
                            upload_path="$upload_path/$subdir"
                        done < "$agent_conf_dir/$host/$agent_conf.conf"

                        mkdir -p "$upload_path"
                        upload_subpath="$(echo $upload_path | sed -r "s|^$upload_dir/||")"

                        if ! "$error"; then

                            echo "      <p>"
                            echo "          Diretórios de aplicação associados à configuração '$agent_conf.conf' ($upload_subpath):<br>"
                            echo "          <form action=\"$start_page\" method=\"post\">"
                            echo "              <input type=\"hidden\" name=\"host\" value=\"$host\">"
                            echo "              <input type=\"hidden\" name=\"operation\" value=\"$operation\">"
                            echo "              <input type=\"hidden\" name=\"agent_conf\" value=\"$agent_conf\">"
                            echo "              <input type=\"hidden\" name=\"upload_path\" value=\"$upload_path\">"
                            find $upload_path/ -mindepth 2 -maxdepth 2 | sort | sed -r "s|^$upload_path/(.*)$|\t\t\t\t\t\t<input type=\"checkbox\" name=\"app_subpath\" value=\"\1\">\1<br>|"
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

                        test -n "$agent_conf" && echo "      <p>Configuração selecionada: <b>$agent_conf</b></p>" || end 1
                        test "$running_tasks" -ge 1 && echo "Há $running_tasks tarefas em execução no host $host. Favor desabilitar os respectivos agentes antes de prosseguir." && end 0

                        app_path="$upload_path/$app_subpath"
                        while [ -n "$app_subpath" ] && [ -d "$app_path" ]; do
                            rm -f "$app_path"/*
                            rmdir "$app_path"
                            rmdir $(dirname $app_path) &> /dev/null
                            echo "      <p>Diretório '$app_path' removido .</p>"
                            arg_string="$(echo "$arg_string" | sed -r "s|&app_subpath=$app_subpath||")"
                            app_subpath="$(echo "$arg_string" | sed -rn "s/^.*&app_subpath=([^\&]+)&.*$/\1/p")"
                            app_path="$upload_path/$app_subpath"
                        done
                        ;;

                    "$submit_add")

                        test -n "$agent_conf" && echo "      <p>Configuração selecionada: <b>$agent_conf</b></p>" || end 1
                        echo "      <p>"
                        echo "          <p>Aplicação:</p>"
                        echo "          <form action=\"$start_page\" method=\"post\">"
                        echo "              <p><input type=\"text\" class=\"text_large\" name=\"app\"></input></p>"
                        echo "              <p>"
                        echo "                  <input type=\"checkbox\" name=\"enable_deploy\" value=\"true\"> Deploy<br>"
                        echo "                  <input type=\"checkbox\" name=\"enable_log\" value=\"true\"> Log<br>"
                        echo "              </p>"
                        echo "              <input type=\"hidden\" name=\"host\" value=\"$host\">"
                        echo "              <input type=\"hidden\" name=\"agent_conf\" value=\"$agent_conf\">"
                        echo "              <input type=\"hidden\" name=\"operation\" value=\"$operation\">"
                        echo "              <input type=\"hidden\" name=\"upload_path\" value=\"$upload_path\">"
                        echo "              <input type=\"submit\" name=\"submit\" value=\"$submit_save\">"
                        echo "          </form>"
                        echo "      </p>"
                        ;;

                    "$submit_save")

                        test -n "$agent_conf" && echo "      <p>Configuração selecionada: <b>$agent_conf</b></p>" || end 1
                        test -n "$enable_log" || enable_log=false
                        test -n "$enable_deploy" || enable_deploy=false

                        mklist "$app" | while read app_name; do
                            valid "$app_name" "app" "<p><b>Erro. Nome de aplicação inválido: $app_name.</b></p>" && dir_created=false || continue
                            $enable_log && mkdir -p "$upload_path/$app_name/log" && echo "<p>Diretório '$upload_path/$app_name/log' criado.</p>" && dir_created=true
                            $enable_deploy && mkdir -p "$upload_path/$app_name/deploy" && echo "<p>Diretório '$upload_path/$app_name/deploy' criado.</p>" && dir_created=true
                            $dir_created || echo "<p>Nenhum diretório adicionado para a aplicação '$app_name'.</p>"
                        done
                        ;;

                esac
                ;;

        esac

    fi

fi

end 0

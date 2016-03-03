#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

function submit_deploy() {

    if [ -z "$proceed" ]; then
        return 1

    elif [ "$proceed" == "$proceed_deploy" ]; then
        return 1

    else
        echo "      <p>"
        echo "          <form action=\"$start_page\" method=\"post\">"
        echo "              <input type=\"hidden\" name=\"$app_param\" value=\"$app_name\"></td></tr>"
        echo "              <input type=\"hidden\" name=\"$rev_param\" value=\"$rev_name\"></td></tr>"
        echo "              <input type=\"hidden\" name=\"$env_param\" value=\"$env_name\"></td></tr>"
        test "$proceed" != "$proceed_simulation" && echo "              <input type=\"submit\" name=\"proceed\" value=\"$proceed_simulation\">"
        echo "              <input type=\"submit\" name=\"proceed\" value=\"$proceed_deploy\">"
        echo "          </form>"
        echo "      </p>"
    fi

    return 0

}

function cat_eof() {
    if [ -r "$1" ] && [ -n "$2" ]; then

        local file="$1"
        local eof_msg="$2"
        local eof=false
        local t=0
        local n=0
        local timeout=$(($cgi_timeout*9/10))                    # tempo máximo para variação no tamanho do arquivo: 90% do timeout do apache
        local size=$(cat "$file" | wc -l)
        local oldsize="$size"
        local line

        sed -n "1,${size}p" "$file" > $tmp_dir/file_part_$n
        grep -x "$eof_msg" $tmp_dir/file_part_$n  > /dev/null && eof=true || cat $tmp_dir/file_part_$n

        while ! $eof; do

            size=$(cat $file | wc -l)

            if [ "$size" -gt "$oldsize" ]; then

                t=0
                rm -f $tmp_dir/file_part_$n
                ((n++))
                sed -n "$((oldsize+1)),${size}p" "$file" > $tmp_dir/file_part_$n
                oldsize="$size"
                grep -x "$eof_msg" $tmp_dir/file_part_$n > /dev/null && eof=true || cat $tmp_dir/file_part_$n

            else
                sleep 1 && ((t++))
            fi

            test $t -ge $timeout && echo 'TIMEOUT' && break

        done

        while read line; do
            echo "$line"
            test "$line" == "$eof_msg" && break
        done < $tmp_dir/file_part_$n

        rm -f $tmp_dir/file_part_$n

    else
        return 1
    fi

    return 0
}

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
rev_param="$(echo "$col_rev" | sed -r 's/\[//;s/\]//')"
env_param="$(echo "$col_env" | sed -r 's/\[//;s/\]//')"
proceed_view="Continuar"
proceed_simulation="Simular"
proceed_deploy="Deploy"

if [ -z "$POST_STRING" ]; then

    # Formulário deploy
    echo "      <p>"
    echo "          <form action=\"$start_page\" method=\"post\">"
    # Sistema...
    echo "              <p>"
    echo "      		    <select style=\"min-width:200px\" name=\"$app_param\">"
    echo "		        	<option value=\"\" selected>Sistema...</option>"
    find $app_conf_dir/ -mindepth 1 -maxdepth 1 -type f -name '*.conf' | sort | xargs -I{} -d '\n' basename {} | cut -f1 -d '.' | sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|"
    echo "		            </select>"
    echo "              </p>"
    # Ambiente...
    echo "              <p>"
    echo "      		<select style=\"min-width:200px\" name=\"$env_param\">"
    echo "		        	<option value=\"\" selected>Ambiente...</option>"
    cat $tmp_dir/lista_ambientes | sort | sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|"
    echo "		        </select>"
    echo "              </p>"
    # Revisão...
    echo "              <p>"
    echo "              <input type=\"text\" style=\"min-width:200px\" name=\"$rev_param\" value=\"Revisão...\"></input>"
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
    app_name=$(echo "$arg_string" | sed -rn "s/^.*&$app_param=([^\&]+)&.*$/\1/p")
    rev_name=$(echo "$arg_string" | sed -rn "s/^.*&$rev_param=([^\&]+)&.*$/\1/p")
    env_name=$(echo "$arg_string" | sed -rn "s/^.*&$env_param=([^\&]+)&.*$/\1/p")
    proceed=$(echo "$arg_string" | sed -rn "s/^.*&proceed=([^\&]+)&.*$/\1/p")

    if [ -n "$app_name" ] && [ -n "$rev_name" ] && [ -n "$env_name" ] && [ -n "$proceed" ]; then

        if [ "$proceed" == "$proceed_view" ]; then

            ### Visualizar parâmetros de deploy
            echo "      <p>"
            echo "          <table>"
            echo "              <tr><td>Sistema: </td><td>$app_name</td></tr>"
            echo "              <tr><td>Revisão: </td><td>$rev_name</td></tr>"
            echo "              <tr><td>Ambiente: </td><td>$env_name</td></tr>"
            echo "          </table>"
            echo "      </p>"
            echo "      <p><b>Parâmetros de deploy:</b></p>"
            echo "      <p>"
            echo "              <table>"
            while read l; do
                show_param=true
                key="$(echo "$l" | cut -f1 -d '=')"
                value="$(echo "$l" | sed -rn "s/^[^\=]+=//p" | sed -r "s/'//g" | sed -r 's/"//g')"
                echo "$key" | grep -Ex ".*_($regex_ambiente)" > /dev/null  && show_param=false
                ! $show_param && echo "$key" | grep -Ex ".*_$env_name" > /dev/null && show_param=true
                $show_param && echo "              <tr><td>$key:      </td><td>$value</td></tr>"
            done < "$app_conf_dir/$app_name.conf"
            echo "              </table>"
            echo "      </p>"

            submit_deploy

        else

            test -p "$deploy_queue" || end 1
            sleep $cgi_timeout > "$deploy_queue" &
            deploy_options="-f"
            deploy_out="$tmp_dir/deploy.out"
            touch $deploy_out

            if [ "$proceed" == "$proceed_simulation" ]; then

                ### Simular deploy
                deploy_options="${deploy_options}n"
                echo "$deploy_options" "$app_name" "$rev_name" "$env_name" "$deploy_out" >> "$deploy_queue"

                echo "      <p>"
                echo "              <table>"
                cat_eof "$deploy_out" "$end_msg" | sed -r "s|^$|<br>|" | sed -r "s|^(.*)$|\t\t\t\t<tr><td>\1</td></tr>|"
                echo "              </table>"
                echo "      </p>"

                submit_deploy

            elif [ "$proceed" == "$proceed_deploy" ]; then

                ### Executar deploy
                echo "$deploy_options" "$app_name" "$rev_name" "$env_name" "$deploy_out" >> "$deploy_queue"

                echo "      <p>"
                echo "              <table>"
                cat_eof "$deploy_out" "$end_msg" | sed -r "s|^$|<br>|" | sed -r "s|^(.*)$|\t\t\t\t<tr><td>\1</td></tr>|"
                echo "              </table>"
                echo "      </p>"

            fi
        fi
    else
        echo "      <p><b>Erro. Os parâmetro 'Sistema', 'Ambiente' e 'Revisão' devem ser preenchidos.</b></p>"
    fi
fi

#Links
web_footer

echo '  </body>'
echo '</html>'

end 0

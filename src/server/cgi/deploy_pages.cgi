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

### HTML
echo 'Content-type: text/html'
echo ''
echo '<html>'
echo '  <head>'
echo '      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">'
echo "  <title>Deploy de aplicação</title"
echo '  </head>'
echo '  <body>'
echo "      <h1>Deploy de aplicação</h1>"

mkdir $tmp_dir
test "$REQUEST_METHOD" == "POST" && test -n "$CONTENT_LENGTH" && read -n "$CONTENT_LENGTH" POST_STRING
mklist "$ambientes" "$tmp_dir/lista_ambientes"

STARTPAGE="$SCRIPT_NAME"
HOMEPAGE="$(dirname "$STARTPAGE")/"
APP_PARAM="$(echo "$col_app" | sed -r 's/\[//;s/\]//')"
REV_PARAM="$(echo "$col_rev" | sed -r 's/\[//;s/\]//')"
ENV_PARAM="$(echo "$col_env" | sed -r 's/\[//;s/\]//')"
PROCEED_VIEW="Continuar"
PROCEED_SIMULATION="Simular"
PROCEED_DEPLOY="Deploy"

if [ -z "$POST_STRING" ]; then

    #Formulário deploy
    echo "      <p>"
    echo "          <form action=\"$STARTPAGE\" method=\"post\">"

    echo "              <p>"
    echo "      		    <select style=\"min-width:200px\" name=\"$APP_PARAM\">"
    echo "		        	<option value=\"\" selected>Sistema...</option>"
    find $app_conf_dir/ -mindepth 1 -maxdepth 1 -type f -name '*.conf' | sort | xargs -I{} -d '\n' basename {} | cut -f1 -d '.' | sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|"
    echo "		            </select>"
    echo "              </p>"

    echo "              <p>"
    echo "      		<select style=\"min-width:200px\" name=\"$ENV_PARAM\">"
    echo "		        	<option value=\"\" selected>Ambiente...</option>"
    cat $tmp_dir/lista_ambientes | sort | sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|"
    echo "		        </select>"
    echo "              </p>"

    echo "              <p>"
    echo "              <input type=\"text\" style=\"min-width:200px\" name=\"$REV_PARAM\" value=\"Revisão...\"></input>"
    echo "              </p>"

    echo "              <p>"
    echo "              <input type=\"submit\" name=\"PROCEED\" value=\"$PROCEED_VIEW\">"
    echo "              </p>"

    echo "          </form>"
    echo "      </p>"

else

    ARG_STRING="&$(web_filter "$POST_STRING")&"
    APP_NAME=$(echo "$ARG_STRING" | sed -rn "s/^.*&$APP_PARAM=([^\&]+)&.*$/\1/p")
    REV_NAME=$(echo "$ARG_STRING" | sed -rn "s/^.*&$REV_PARAM=([^\&]+)&.*$/\1/p")
    ENV_NAME=$(echo "$ARG_STRING" | sed -rn "s/^.*&$ENV_PARAM=([^\&]+)&.*$/\1/p")
    PROCEED=$(echo "$ARG_STRING" | sed -rn "s/^.*&PROCEED=([^\&]+)&.*$/\1/p")

    if [ -n "$APP_NAME" ] && [ -n "$REV_NAME" ] && [ -n "$ENV_NAME" ] && [ -n "$PROCEED" ]; then

        if [ "$PROCEED" == "$PROCEED_VIEW" ]; then

            ### Visualizar parâmetros de deploy
            echo "      <p>"
            echo "          <table>"
            echo "              <tr><td>Sistema: </td><td>$APP_NAME</td></tr>"
            echo "              <tr><td>Revisão: </td><td>$REV_NAME</td></tr>"
            echo "              <tr><td>Ambiente: </td><td>$ENV_NAME</td></tr>"
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
                ! $show_param && echo "$key" | grep -Ex ".*_$ENV_NAME" > /dev/null && show_param=true
                $show_param && echo "              <tr><td>$key:      </td><td>$value</td></tr>"
            done < "$app_conf_dir/$APP_NAME.conf"
            echo "              </table>"
            echo "      </p>"

            echo "      <p>"
            echo "          <form action=\"$STARTPAGE\" method=\"post\">"
            echo "              <input type=\"hidden\" name=\"$APP_PARAM\" value=\"$APP_NAME\"></td></tr>"
            echo "              <input type=\"hidden\" name=\"$REV_PARAM\" value=\"$REV_NAME\"></td></tr>"
            echo "              <input type=\"hidden\" name=\"$ENV_PARAM\" value=\"$ENV_NAME\"></td></tr>"
            echo "              <input type=\"submit\" name=\"PROCEED\" value=\"$PROCEED_SIMULATION\">"
            echo "              <input type=\"submit\" name=\"PROCEED\" value=\"$PROCEED_DEPLOY\">"
            echo "          </form>"
            echo "      </p>"

        else

            deploy_options="-f"
            deploy_out="$tmp_dir/deploy.out"
            deploy_in="$deploy_queue"

            test -p $deploy_in || end 1
            mkfifo "$deploy_out" || end 1

            if [ "$PROCEED" == "$PROCEED_SIMULATION" ]; then

                ### Simular deploy
                deploy_options="$deploy_options -n"
                echo "$deploy_options" "$APP_NAME" "$REV_NAME" "$ENV_NAME" "$deploy_out" >> "$deploy_in"

                echo "      <p>"
                echo "              <table>"
                cat "$deploy_out" | sed -r "s|^(.*)$|\t\t\t\t<tr><td>\1</td></tr>|"
                echo "              </table>"
                echo "      </p>"

            elif [ "$PROCEED" == "$PROCEED_DEPLOY" ]; then

                ### Executar deploy
                echo "$deploy_options" "$APP_NAME" "$REV_NAME" "$ENV_NAME" "$deploy_out" >> "$deploy_in"

                echo "      <p>"
                echo "              <table>"
                cat "$deploy_out" | sed -r "|^(.*)$|\t\t\t\t<tr><td>\1</td></tr>|"
                echo "              </table>"
                echo "      </p>"

            fi
        fi
    else
        echo "      <p><b>Erro. Os parâmetro 'Sistema', 'Ambiente' e 'Revisão' devem ser preenchidos.</b></p>"
    fi
fi

#Links
echo "      <table width=100% style=\"text-align:left;color:black\">"
echo "          <tr> <td><br></td> </tr>"
echo "          <tr> <td><a href=\"$STARTPAGE\" style=\"color:black\" >Início</a> </td></tr>"
echo "          <tr> <td><a href=\"$HOMEPAGE\" style=\"color:black\" >Página Principal</a></td></tr>"
echo "          <tr> <td><a href=\"$apache_log_alias\" style=\"color:black\" >Logs</a></td></tr>"
echo "      </table>"

echo '  </body>'
echo '</html>'

end 0

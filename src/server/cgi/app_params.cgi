#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/init.sh || exit 1
source $install_dir/cgi/input_filter.cgi || exit 1

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
echo "  <title>Parâmetros de aplicação</title"
echo '  </head>'
echo '  <body>'
echo "      <h1>Parâmetros de aplicação</h1>"

mkdir $tmp_dir

STARTPAGE="$SCRIPT_NAME"
HOMEPAGE="$(dirname "$STARTPAGE")/"
APP_PARAM="$(echo "$col_app" | sed -r 's/\[//;s/\]//')"
NEW_PARAM='New'

#Combo aplicações
echo "		<select onchange="javascript:location.href=this.value">"
echo "			<option value=\"Sistema\">Sistema...</option>"
echo "			<option value=\"$STARTPAGE?$NEW_PARAM=1\">Registrar nova aplicação...</option>"
find $app_conf_dir/ -mindepth 1 -maxdepth 1 -type f -name '*.conf' | sort | xargs -I{} -d '\n' basename {} | cut -f1 -d '.' | sed -r "s|(.*)|\t\t<option value=\"$STARTPAGE?$APP_PARAM=\1\">\1</option>|"
echo "		</select>"

if [ -n "$QUERY_STRING" ]; then

    # EDITAR PARÂMETROS

    ARG_STRING="$(input_filter "$QUERY_STRING")"
    echo "$ARG_STRING"
    APP=$(echo "$ARG_STRING" | sed -rn "s/^.*$APP_PARAM=([^\&\=]+)&?.*$/\1/p")
    NEW=$(echo "$ARG_STRING" | sed -rn "s/^.*$NEW_PARAM=([^\&\=]+)&?.*$/\1/p")

    echo "      <p>"
    echo "          <form action=\"$STARTPAGE\" method=\"post\">"
    echo "              <table>"

    test -f "$app_conf_dir/$APP.conf" && form_file="$app_conf_dir/$APP.conf" || form_file="$install_dir/template/app.template"
    while read l; do
        key=$(echo "$l" | cut -f1 -d '=')
        value=$(echo "$l" | sed -rn "s/^[^\=]+=//p")
        echo "              <tr><td>$key:      </td><td><input type=\"text\" size=\"100\" name=\"$key\" value=\"$value\"></td></tr>"
    done < "$form_file"

    echo "              </table>"
    echo "              <input type=\"submit\" name=\"SAVE\" value=\"Salvar\">"
    echo "          </form>"
    echo "      </p>"

elif read POST_STRING; then

    # SALVAR PARÂMETROS

    ARG_STRING="$(input_filter "$POST_STRING")"
    echo "$ARG_STRING"
    APP_NAME=$(echo "$ARG_STRING" | sed -rn "s/^.*app=([^\&\=]+)&?.*$/\1/p")

    if [ -n "$APP_NAME" ]; then
        test -f $app_conf_dir/$APP_NAME.conf && lock $APP_NAME || cp "$install_dir/template/app.template" "$app_conf_dir/$APP_NAME.conf"

        while read l; do
            key="$(echo "$l" | cut -f1 -d '=')"
            old_value="$(echo "$l" | sed -rn "s/^$key=//p")"
            new_value="$(echo "$ARG_STRING" | sed -rn "s/^.*$key=([^\&\=]+)&?.*$/\1/p")"
            test "$new_value" != "$old_value" && edit_var=1
            editconf "$key" "$new_value" "$app_conf_dir/$APP_NAME.conf"
        done < "$app_conf_dir/$APP_NAME.conf"

        echo "Parâmetros da aplicação $APP_NAME atualizados."
    else
        echo "Erro. O parâmetro 'app' deve ser preenchido."
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

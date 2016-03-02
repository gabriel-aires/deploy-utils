#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

function end() {
    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    wait
    exit $1
}

trap "end 1" SIGQUIT SIGINT SIGHUP EXIT
mkdir $tmp_dir

# Cabeçalho
web_header

# Inicializar variáveis e constantes
app_param="$(echo "$col_app" | sed -r 's/\[//;s/\]//')"
WHERE=''
ORDERBY=''
TOP=''
SELECT=''

# Combo aplicações
echo "		<select onchange="javascript:location.href=this.value">"
echo "			<option value=\"Sistema\">Sistema...</option>"
find $app_history_dir_tree/ -mindepth 1 -maxdepth 1 -type d | sort | xargs -I{} -d '\n' basename {} | sed -r "s|(.*)|\t\t<option value=\"$start_page?$app_param=\1\">\1</option>|"
echo "		</select>"

# Processar QUERY_STRING
if [ -z $QUERY_STRING ]; then
	app_name=''
else
    arg_string="&$(web_filter "$QUERY_STRING")&"
	app_name=$(echo "$arg_string" | sed -rn "s/^.*&$app_param=([^\&]+)&.*$/\1/p")
    test -n "$app_name" && WHERE="--where $col_app==$app_name"
fi

# histórico de deploy
web_query_history

# Links
web_footer

echo '  </body>'
echo '</html>'

end 0

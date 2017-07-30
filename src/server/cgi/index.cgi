#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

function end() {
    test "$1" == "0" || echo "      <p><b>Operação inválida.</b></p>"
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

# Cabeçalho
web_header
content_loading

# Inicializar variáveis e constantes
mklist "$ambientes" "$tmp_dir/lista_ambientes"
app_param="$(echo "${col[app]}" | sed -r 's/\[//;s/\]//')"
env_param="$(echo "${col[env]}" | sed -r 's/\[//;s/\]//')"
WHERE=''
ORDERBY=''
TOP=''
SELECT=''

# Formulário de pesquisa
echo "      <p>"
echo "          <form action=\"$start_page\" method=\"get\">"
# Sistema...
echo "      		<select class=\"select_small\" name=\"$app_param\">"
echo "		        	<option value=\"\" selected>Sistema...</option>"
find $app_history_dir_tree/ -mindepth 2 -maxdepth 2 -type d | xargs -I{} -d '\n' basename {} | sort | uniq | sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|"
echo "		        </select>"
# Ambiente...
echo "      		<select class=\"select_small\" name=\"$env_param\">"
echo "		        	<option value=\"\" selected>Ambiente...</option>"
cat $tmp_dir/lista_ambientes | sort | sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|"
echo "		        </select>"
# Paginação...
echo "      		<select class=\"select_small\" name=\"n\">"
echo "		        	<option value=\"\" selected>Paginação..</option>"
echo "		        	<option>10</option>"
echo "		        	<option>20</option>"
echo "		        	<option>30</option>"
echo "		        	<option>40</option>"
echo "		        	<option>50</option>"
echo "		        </select>"
# Submit
echo "              <input type=\"submit\" name=\"search\" value=\"Buscar\">"
echo "          </form>"
echo "      </p>"

# Processar QUERY_STRING
if [ -n $QUERY_STRING ]; then
    arg_string="&$(web_filter "$QUERY_STRING")&"
	app_name=$(echo "$arg_string" | sed -rn "s/^.*&$app_param=([^\&]+)&.*$/\1/p")
    env_name=$(echo "$arg_string" | sed -rn "s/^.*&$env_param=([^\&]+)&.*$/\1/p")
    test -n "$app_name" && WHERE="$WHERE ${col[app]}==$app_name"
    test -n "$env_name" && WHERE="$WHERE ${col[env]}==$env_name"
    test -n "$WHERE" && WHERE="--where$WHERE"
fi

# histórico de deploy
web_query_history
content_ready

end 0

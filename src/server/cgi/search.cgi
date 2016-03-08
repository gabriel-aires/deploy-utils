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
col_day_name=$(echo "$col_day" | sed -r 's|(\[)||' | sed -r 's|(\])||')
col_month_name=$(echo "$col_month" | sed -r 's|(\[)||' | sed -r 's|(\])||')
col_year_name=$(echo "$col_year" | sed -r 's|(\[)||' | sed -r 's|(\])||')
col_time_name=$(echo "$col_time" | sed -r 's|(\[)||' | sed -r 's|(\])||')
col_app_name=$(echo "$col_app" | sed -r 's|(\[)||' | sed -r 's|(\])||')
col_rev_name=$(echo "$col_rev" | sed -r 's|(\[)||' | sed -r 's|(\])||')
col_env_name=$(echo "$col_env" | sed -r 's|(\[)||' | sed -r 's|(\])||')
col_host_name=$(echo "$col_host" | sed -r 's|(\[)||' | sed -r 's|(\])||')
col_obs_name=$(echo "$col_obs" | sed -r 's|(\[)||' | sed -r 's|(\])||')
col_flag_name=$(echo "$col_flag" | sed -r 's|(\[)||' | sed -r 's|(\])||')
SELECT=''
DISTINCT=''
WHERE=''
ORDERBY=''
TOP=''

# Form Select
echo "<form action=\"$start_page\" method=\"get\">"
echo "     <table>"
echo "          <tr><td>SELECT:    </td><td><input type=\"text\" class=\"text_default\" name=\"SELECT\" value=\"Ex: $col_tag_name $col_time_name $col_month_name $col_year_name $col_app_name $col_env_name $col_host_name\"> <input type=\"checkbox\" name=\"DISTINCT\" value=\"1\">DISTINCT</td></tr>"
echo "          <tr><td>TOP:       </td><td><input type=\"text\" class=\"text_default\" value=\"Ex: 10\"></td></tr>"
echo "          <tr><td>WHERE:     </td><td><input type=\"text\" class=\"text_default\" name=\"WHERE\" value=\"Ex: $col_host_name=%rh $col_app_name==sgq\"></td></tr>"
echo "          <tr><td>ORDER BY:  </td><td><input type=\"text\" class=\"text_default\" name=\"ORDERBY\" value=\"Ex: $col_year_name $col_month_name $col_time_name desc\"></td></tr>"
# Paginação
echo "          <tr>"
echo "              <td>PAGINAÇÃO: </td>"
echo "              <td>"
echo "      		    <select class=\"select_default\" name=\"n\">"
echo "		        	   <option>10</option>"
echo "		        	   <option selected>20</option>"
echo "		        	   <option>30</option>"
echo "		        	   <option>40</option>"
echo "		        	   <option>50</option>"
echo "		            </select>"
echo "              </td>"
echo "          </tr>"
echo "     </table>"
echo "<input type=\"submit\" name=\"SEARCH\" value=\"Buscar\">"
echo "</form>"

echo "      <p>"
if [ -z "$QUERY_STRING" ]; then
    # Exibir texto explicativo
    echo "<table>"
    echo "<tr><th>UTILIZAÇÃO:</th></tr>"
    echo "<tr><th><br></th></tr>"
    echo "<tr><th>SELECT:</th><td>Especificar a colunas a serem selecionadas.<b> Ex: nome_coluna1 nome_coluna2 all, etc (padrão=all)</b></td></tr>"
    echo "<tr><th>DISTINCT:</th><td>Marcar para suprimir linhas repetidas.<b> Deve ser utilizada em conjunto com a opção ORDER BY. (padrão=desmarcado)</b></td></tr>"
    echo "<tr><th>TOP:</th><td>Especificar a quantidade de linhas a serem retornadas.<b> Ex: 10 500, etc (padrão=retornar todas as linhas)</b></td></tr>"
    echo "<tr><th>WHERE:</th><td>Especificar filtro(s) .<b> Ex: nome_coluna2==valor_exato nome_coluna3!=diferente_valor nome_coluna4=%contem_valor, etc (padrão=sem filtros)</b></td></tr>"
    echo "<tr><th>ORDER BY</th><td>Especificar ordenação dos resultados.<b> Ex: nome_coluna3 nome_coluna4 asc, nome_coluna1 desc, etc (padrão=Ano Mes Dia desc)</b></td></tr>"
    echo "</table>"

else
    # Processar QUERY_STRING
    arg_string="&$(web_filter "$QUERY_STRING")&"

    SELECT="$(echo "$arg_string" | sed -rn "s/^.*&SELECT=([^\&]+)&.*$/\1/p")"
    test -n "$SELECT" && SELECT="--select $(echo $SELECT | sed -r 's/^(.*)$/\[\1\]/' | sed -r 's/( +)/\] \[/g' | sed -r 's/\[all\]/all/' )"

    DISTINCT="$(echo "$arg_string" | sed -rn "s/^.*&DISTINCT=([^\&]+)&.*$/\1/p")"
    test -n "$DISTINCT" && DISTINCT="--distinct"

    TOP="$(echo "$arg_string" | sed -rn "s/^.*&TOP=([^\&]+)&.*$/\1/p")"
    test -n "$TOP" && TOP="--top $TOP"

    WHERE="$(echo "$arg_string" | sed -rn "s/^.*&WHERE=([^\&]+)&.*$/\1/p")"
    test -n "$WHERE" && WHERE="--where $(echo $WHERE | sed -r 's/^(.)/\[\1/' | sed -r 's/( +)/ \[/g' | sed -r 's/([\=\!][\=\%\~])/\]\1/g')"

    ORDERBY="$(echo "$arg_string" | sed -rn "s/^.*&ORDERBY=([^\&]+)&.*$/\1/p")"
    test -n "$ORDERBY" && ORDERBY="--order-by $(echo $ORDERBY | sed -r 's/^(.*)$/\[\1\]/' | sed -r 's/( +)/\] \[/g' | sed -r 's/\[asc\]/asc/' | sed -r 's/\[desc\]/desc/')"

    # Consultar Histórico de Deploy
    web_query_history

fi
echo "      </p>"

# Links
web_footer

echo '  </body>'
echo '</html>'

end 0

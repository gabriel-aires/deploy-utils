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

trap "end 1" SIGQUIT SIGINT SIGHUP
mkdir $tmp_dir

# Cabeçalho
web_header

# Inicializar variáveis e constantes
col_day_name=$(echo "$col_day" | sed -r 's|(\[)||' | sed -r 's|(\])||')
col_month_name=$(echo "$col_month" | sed -r 's|(\[)||' | sed -r 's|(\])||')
col_year_name=$(echo "$col_year" | sed -r 's|(\[)||' | sed -r 's|(\])||')
col_time_name=$(echo "$col_time" | sed -r 's|(\[)||' | sed -r 's|(\])||')
col_user_name=$(echo "$col_user" | sed -r 's|(\[)||' | sed -r 's|(\])||')
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
echo "          <tr><td>SELECT:    </td><td><input type=\"text\" class=\"text_large\" name=\"SELECT\" value=\"\"> <input type=\"checkbox\" name=\"DISTINCT\" value=\"1\">DISTINCT</td></tr>"
echo "          <tr><td>TOP:       </td><td><input type=\"text\" class=\"text_large\" name=\"TOP\" value=\"\"></td></tr>"
echo "          <tr><td>WHERE:     </td><td><input type=\"text\" class=\"text_large\" name=\"WHERE\" value=\"\"></td></tr>"
echo "          <tr><td>ORDER BY:  </td><td><input type=\"text\" class=\"text_large\" name=\"ORDERBY\" value=\"\"></td></tr>"
# Paginação
echo "          <tr>"
echo "              <td>PAGINAÇÃO: </td>"
echo "              <td>"
echo "      		    <select class=\"select_large\" name=\"n\">"
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
    echo "<table class=\"cfg_color\">"
    echo "<tr><th colspan=\"3\">UTILIZAÇÃO:</th></tr>"
    echo "<tr><th>INSTRUÇÃO</th><th>DESCRIÇÃO</th><th>EXEMPLO</th></tr>"
    echo "<tr><td>SELECT:</td><td>Especificar a colunas a serem selecionadas.</td><td> Ex: $(test -f $history_dir/$history_csv_file && query_file.sh -d "$delim" -r ' ' -s all -t 1 -f $history_dir/$history_csv_file) (padrão=all)</td></tr>"
    echo "<tr><td>DISTINCT:</td><td>Marcar para suprimir linhas repetidas.</td><td> Deve ser utilizada em conjunto com a opção ORDER BY. (padrão=desmarcado)</td></tr>"
    echo "<tr><td>TOP:</td><td>Especificar a quantidade de linhas a serem retornadas.</td><td> Ex: 10 500, etc (padrão=retornar todas as linhas)</td></tr>"
    echo "<tr><td>WHERE:</td><td>Especificar filtro(s) .</td><td> Ex: Coluna2<span style=\"color:red\">==</span>valor_exato Coluna3<span style=\"color:red\">!=</span>diferente_valor Coluna4<span style=\"color:red\">=%</span>contem_valor, etc (padrão=sem filtros)</td></tr>"
    echo "<tr><td>ORDER BY:</td><td>Especificar ordenação dos resultados.</td><td> Ex: Coluna3 Coluna4 asc, Coluna1 desc, etc (padrão=Ano Mes Dia desc)</td></tr>"
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

end 0

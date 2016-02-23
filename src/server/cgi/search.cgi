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
echo "  <title>Busca Avançada</title"
echo '  </head>'
echo '  <body>'
echo "      <h1>Busca Avançada</h1>"

### QUERY FILE

file=$history_dir/$history_csv_file

if [ ! -f "$file" ]; then
    echo "<p>Arquivo de histórico inexistente</p>"
    end 1
fi

mkdir $tmp_dir

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

STARTPAGE="$SCRIPT_NAME"
MIN_PAGE=1
SELECT=''
WHERE=''
ORDERBY=''
TOP=''

if [ -z "$QUERY_STRING" ]; then

    PAGE=1
    NEXT=2
    PREV=0
    NEXT_URI="$STARTPAGE?p=$NEXT"

else

    ARG_STRING="$(input_filter "$QUERY_STRING")"

    SELECT="$(echo "$ARG_STRING" | sed -r "s/^.*SELECT=([^\&]+)&?.*$/\1/")"
    test "$SELECT" != "$ARG_STRING" && SELECT="--select $(echo $SELECT | sed -r 's/^(.*)$/\[\1\]/' | sed -r 's/( +)/\] \[/g' | sed -r 's/\[all\]/all/' )" || SELECT=''

    DISTINCT="$(echo "$ARG_STRING" | sed -r "s/^.*DISTINCT=([^\&]+)&?.*$/\1/")"
    test "$DISTINCT" != "$ARG_STRING" && DISTINCT="--distinct" || DISTINCT=''

    TOP="$(echo "$ARG_STRING" | sed -r "s/^.*TOP=([^\&]+)&?.*$/\1/")"
    test "$TOP" != "$ARG_STRING" && TOP="--top $TOP" || TOP=''

    WHERE="$(echo "$ARG_STRING" | sed -r "s/^.*WHERE=([^\&]+)&?.*$/\1/")"
    test "$WHERE" != "$ARG_STRING" && WHERE="--where $(echo $WHERE | sed -r 's/^(.)/\[\1/' | sed -r 's/( +)/ \[/g' | sed -r 's/([\=\!][\=\%\~])/\]\1/g')" || WHERE=''

    ORDERBY="$(echo "$ARG_STRING" | sed -r "s/^.*ORDERBY=([^\&]+)&?.*$/\1/")"
    test "$ORDERBY" != "$ARG_STRING" && ORDERBY="--order-by $(echo $ORDERBY | sed -r 's/^(.*)$/\[\1\]/' | sed -r 's/( +)/\] \[/g' | sed -r 's/\[asc\]/asc/' | sed -r 's/\[desc\]/desc/')" || ORDERBY=''

    PAGE=$(echo "$ARG_STRING" | sed -r "s/^.*p=([^\&]+)&?.*$/\1/")
    test "$PAGE" == "$ARG_STRING" && PAGE=1

    NEXT=$(($PAGE+1))
    PREV=$(($PAGE-1))

    NEXT_URI="$(echo "$REQUEST_URI" | sed -r "s/^(.*p=)$PAGE(.*)$/\1$NEXT\2/")"
    test "$NEXT_URI" != "$REQUEST_URI" || NEXT_URI="$REQUEST_URI&p=$NEXT"

    PREV_URI="$(echo "$REQUEST_URI" | sed -r "s/^(.*p=)$PAGE(.*)$/\1$PREV\2/")"
    test "$PREV_URI" != "$REQUEST_URI" || PREV_URI="$REQUEST_URI&p=$PREV"

fi

export 'SELECT' 'DISTINCT' 'TOP' 'WHERE' 'ORDERBY'

HOMEPAGE="$(dirname "$STARTPAGE")/"
NAV="$PAGE"

# Form Select
echo "<form action=\"$STARTPAGE\" method=\"get\">"
echo "     <table>"
echo "          <tr><td>SELECT:   </td><td><input type=\"text\" size=\"100\" name=\"SELECT\" value=\"Ex: $col_tag_name $col_time_name $col_month_name $col_year_name $col_app_name $col_env_name $col_host_name\"> <input type=\"checkbox\" name=\"DISTINCT\" value=\"1\">DISTINCT</td></tr>"
echo "          <tr><td>TOP:      </td><td><input type=\"text\" size=\"100\" name=\"TOP\" value=\"Ex: 10\"></td></tr>"
echo "          <tr><td>WHERE:    </td><td><input type=\"text\" size=\"100\" name=\"WHERE\" value=\"Ex: $col_host_name=%rh $col_app_name==sgq\"></td></tr>"
echo "          <tr><td>ORDER BY: </td><td><input type=\"text\" size=\"100\" name=\"ORDERBY\" value=\"Ex: $col_year_name $col_month_name $col_time_name desc\"></td></tr>"
echo "     </table>"
echo "<input type=\"submit\" name=\"SEARCH\" value=\"Buscar\">"
echo "</form>"

#Histórico / Ajuda

echo "      <p>"
if [ -z "$QUERY_STRING" ]; then
    echo "<table width=\"70%\">"
    echo "<tr><th><br></th></tr>"
    echo "<tr><th><br></th></tr>"
    echo "<tr><th>UTILIZAÇÃO:</th></tr>"
    echo "<tr><th><br></th></tr>"
    echo "<tr><th>SELECT:</th><td>Especificar a colunas a serem selecionadas.<b> Ex: nome_coluna1 nome_coluna2 all, etc (padrão=all)</b></td></tr>"
    echo "<tr><th>DISTINCT:</th><td>Marcar para suprimir linhas repetidas.<b> Deve ser utilizada em conjunto com a opção ORDER BY. (padrão=desmarcado)</b></td></tr>"
    echo "<tr><th>TOP:</th><td>Especificar a quantidade de linhas a serem retornadas.<b> Ex: 10 500, etc (padrão=retornar todas as linhas)</b></td></tr>"
    echo "<tr><th>WHERE:</th><td>Especificar filtro(s) .<b> Ex: nome_coluna2==valor_exato nome_coluna3!=diferente_valor nome_coluna4=%contem_valor, etc (padrão=sem filtros)</b></td></tr>"
    echo "<tr><th>ORDER BY</th><td>Especificar ordenação dos resultados.<b> Ex: nome_coluna3 nome_coluna4 asc, nome_coluna1 desc, etc (padrão=Ano Mes Dia desc)</b></td></tr>"
    echo "</table>"
else

    $install_dir/cgi/table_data.cgi $file > $tmp_dir/html_table

    DATA_SIZE=$(($(cat "$tmp_dir/html_table" | wc -l)-1))
    test $DATA_SIZE -lt $html_table_size && print_size=$DATA_SIZE || print_size=$html_table_size

    MAX_PAGE=$(($DATA_SIZE/$html_table_size))

    if [ $NEXT -le $MAX_PAGE ]; then
        NAV="$NAV <a href=\"$NEXT_URI\" style=\"color:black\">$NEXT</a>"
    fi

    if [ $PREV -ge $MIN_PAGE ]; then
        NAV="<a href=\"$PREV_URI\" style=\"color:black\">$PREV</a> $NAV"
    fi

    echo "<table cellpadding=5 width=100% style=\"$html_table_style\">"
    head -n 1 "$tmp_dir/html_table"
    head -n $((($PAGE*$html_table_size)+1)) $tmp_dir/html_table | tail -n $print_size
    echo "</table>"
fi

echo "      </p>"

#Links
echo "      <table width=100% style=\"text-align:left;color:black\">"
echo "          <tr> <td><br></td> </tr>"
echo "          <tr> <td><a href=\"$STARTPAGE\" style=\"color:black\" >Início</a> </td> <td style=\"text-align:right\">Página: $NAV</td> </tr>"
echo "          <tr> <td><a href=\"$HOMEPAGE\" style=\"color:black\" >Página Principal</a></td></tr>"
echo "          <tr> <td><a href=\"$apache_log_alias\" style=\"color:black\" >Logs</a></td></tr>"
echo "      </table>"

echo '  </body>'
echo '</html>'

end 0

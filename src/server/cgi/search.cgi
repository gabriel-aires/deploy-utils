#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/init.sh || exit 1

### HTML
echo 'Content-type: text/html'
echo ''
echo '<html>'
echo '  <head>'
echo '      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">'
echo "  <title>$html_title</title"
echo '  </head>'
echo '  <body>'
echo "      <h1>$html_header</h1>"

### QUERY FILE

file=$history_dir/$history_csv_file

if [ ! -f "$file" ]; then
	echo "<p>Arquivo de histórico inexistente</p>"
	exit 1
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

MIN_PAGE=1
SELECT=''
WHERE=''
ORDERBY=''
TOP=''

if [ -z $QUERY_STRING ]; then
	STARTPAGE="$REQUEST_URI"
	PAGE=1
	NEXT=2
	PREV=0

	NEXT_URI="$STARTPAGE?p=$NEXT"

elif [ "$(echo "$QUERY_STRING" | sed -r "s/^.*SEARCH=([^\&]+)&?.*$/\1/" | sed -r "s/%20/ /g" | sed -r "s/\+/ /g" | grep -vx "$QUERY_STRING")" == "Buscar" ]; then
	STARTPAGE="$(echo "$REQUEST_URI" | sed -r "s/\?$QUERY_STRING$//")"

	SELECT="$(echo "$QUERY_STRING" | sed -r "s/^.*SELECT=([^\&]+)&?.*$/\1/" | sed -r "s/%20/ /g" | sed -r "s/\+/ /g" | grep -vx "$QUERY_STRING")"
    test -n "$SELECT" && SELECT="--select $(echo $SELECT | sed -r 's/^(.*)$/\[\1\]/' | sed -r 's/( +)/\] \[/')"

    TOP=$(echo "$QUERY_STRING" | sed -r "s/^.*TOP=([^\&]+)&?.*$/\1/" | sed -r "s/%20/ /g" | sed -r "s/\+/ /g"  | grep -vx "$QUERY_STRING")
    test -n "$TOP" && TOP="--top $TOP"

    WHERE=$(echo "$QUERY_STRING" | sed -r "s/^.*WHERE=([^\&]+)&?.*$/\1/" | sed -r "s/%20/ /g" | sed -r "s/%3D/=/g"  | sed -r "s/%25/%/g" | sed -r "s/%21/!/g" | sed -r "s/\+/ /g" | grep -vx "$QUERY_STRING")
    test -n "$WHERE" && WHERE="--where $(echo $WHERE | sed -r 's/^(.)/\[\1/' | sed -r 's/( +)/ \[/' | sed -r 's/([\=\!][\=\%\~])/\]\1/')"

    ORDERBY=$(echo "$QUERY_STRING" | sed -r "s/^.*ORDERBY=([^\&]+)&?.*$/\1/" | sed -r "s/%20/ /g" | sed -r "s/\+/ /g"  | grep -vx "$QUERY_STRING")
    test -n "$ORDERBY" && ORDERBY="--order-by $(echo $ORDERBY | sed -r 's/^(.*)$/\[\1\]/' | sed -r 's/( +)/\] \[/' | sed -r 's/\[asc\]/asc/' | sed -r 's/\[desc\]/desc/')"

	PAGE=$(echo "$QUERY_STRING" | sed -r "s/^.*p=([0-9]+).*$/\1/" | sed -r "s/%20/ /g" | sed -r "s/\+/ /g"  | grep -vx "$QUERY_STRING")
	test -n "$PAGE" || PAGE=1

	NEXT=$(($PAGE+1))
	PREV=$(($PAGE-1))

	NEXT_URI="$(echo "$REQUEST_URI" | sed -r "s/^(.*p=)$PAGE(.*)$/\1$NEXT\2/")"
        test "$NEXT_URI" != "$REQUEST_URI" || NEXT_URI="$REQUEST_URI&p=$NEXT"

	PREV_URI="$(echo "$REQUEST_URI" | sed -r "s/^(.*p=)$PAGE(.*)$/\1$PREV\2/")"
        test "$PREV_URI" != "$REQUEST_URI" || PREV_URI="$REQUEST_URI&p=$PREV"

fi

echo "s=$SELECT t=$TOP w=$WHERE o=$ORDERBY"
export 'SELECT' 'TOP' 'WHERE' 'ORDERBY'

$install_dir/cgi/table_data.cgi $file > $tmp_dir/html_table

DATA_SIZE=$(($(cat "$tmp_dir/html_table" | wc -l)-1))
test $DATA_SIZE -lt $history_html_size && print_size=$DATA_SIZE || print_size=$history_html_size

MAX_PAGE=$(($DATA_SIZE/$history_html_size))

NAV="$PAGE"

if [ $NEXT -le $MAX_PAGE ]; then
	NAV="$NAV <a href=\"$NEXT_URI\" style=\"color:black\">$NEXT</a>"
fi

if [ $PREV -ge $MIN_PAGE ]; then
	NAV="<a href=\"$PREV_URI\" style=\"color:black\">$PREV</a> $NAV"
fi

# Form Select
echo "<form action=\"$STARTPAGE\" method=\"get\">"
echo "SELECT:   <input type=\"text\" name=\"SELECT\">Ex: $col_app_name $col_env_name $col_host_name</input><br>"
echo "TOP:      <input type=\"text\" name=\"TOP\">Ex: 10</input><br>"
echo "WHERE:    <input type=\"text\" name=\"WHERE\">Ex: $col_rev_name=%v1 $col_app_name==visao </input><br>"
echo "ORDER BY: <input type=\"text\" name=\"ORDERBY\">Ex: $col_year_name $col_month_name $col_time_name desc</input><br>"
echo "<input type=\"submit\" name=\"SEARCH\" value=\"Buscar\">"
echo "</form>"

#Histórico
echo "      <p>"
echo "          <table cellpadding=5 width=100% style=\"$html_table_style\">"
head -n 1 "$tmp_dir/html_table"
head -n $((($PAGE*$history_html_size)+1)) $tmp_dir/html_table | tail -n $print_size
echo "          </table>"
echo "      </p>"

#Links
echo "      <table width=100% style=\"text-align:left;color:black\">"
echo "		    <tr> <td><br></td> </tr>"
echo "          <tr> <td><a href=\"$STARTPAGE\" style=\"color:black\" >Início</a> </td> <td style=\"text-align:right\">Página: $NAV</td> </tr>"
echo "          <tr> <td><a href=\"${STARTPAGE}detalhe/\" style=\"color:black\">Logs</td> </tr>"
echo "      </table>"

rm -f $tmp_dir/*
rmdir $tmp_dir

echo '  </body>'
echo '</html>'

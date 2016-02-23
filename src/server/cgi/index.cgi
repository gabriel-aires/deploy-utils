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
echo "  <title>$html_title</title"
echo '  </head>'
echo '  <body>'
echo "      <h1>$html_header</h1>"

### QUERY FILE

file=$history_dir/$history_csv_file

if [ ! -f "$file" ]; then
	echo "<p>Arquivo de histórico inexistente</p>"
	end 1
fi

mkdir $tmp_dir

STARTPAGE="$(dirname $SCRIPT_NAME)"
MIN_PAGE=1
WHERE=''
ORDERBY=''
TOP=''
SELECT=''

if [ -z $QUERY_STRING ]; then

	PAGE=1
	NEXT=2
	PREV=0
	APP=''
	NEXT_URI="$STARTPAGE?p=$NEXT"

else

    input_filter 'ARG_STRING' "$QUERY_STRING"

	APP="$(echo "$col_app" | sed -r 's/\[//;s/\]//')"
	APP=$(echo "$ARG_STRING" | sed -rn "s/^.*$APP=([^\&\=]+)&?.*$/\1/p")
    test -n "$APP" && WHERE="--where $col_app==$APP"

	PAGE=$(echo "$ARG_STRING" | sed -rn "s/^.*p=([^\&\=]+)&?.*$/\1/p")
	test -z "$PAGE" && PAGE=1

	NEXT=$(($PAGE+1))
	PREV=$(($PAGE-1))

	NEXT_URI="$(echo "$REQUEST_URI" | sed -rn "s/^(.*p=)$PAGE(.*)$/\1$NEXT\2/p")"
    test -z "$NEXT_URI" && NEXT_URI="$REQUEST_URI&p=$NEXT"

	PREV_URI="$(echo "$REQUEST_URI" | sed -rn "s/^(.*p=)$PAGE(.*)$/\1$PREV\2/p")"
    test -z "$PREV_URI" && PREV_URI="$REQUEST_URI&p=$PREV"

fi

export 'WHERE'

$install_dir/cgi/table_data.cgi $file > $tmp_dir/html_table

DATA_SIZE=$(($(cat "$tmp_dir/html_table" | wc -l)-1))
test $DATA_SIZE -lt $html_table_size && print_size=$DATA_SIZE || print_size=$html_table_size

MAX_PAGE=$(($DATA_SIZE/$html_table_size))

NAV="$PAGE"

if [ $NEXT -le $MAX_PAGE ]; then
	NAV="$NAV <a href=\"$NEXT_URI\" style=\"color:black\">$NEXT</a>"
fi

if [ $PREV -ge $MIN_PAGE ]; then
	NAV="<a href=\"$PREV_URI\" style=\"color:black\">$PREV</a> $NAV"
fi

#Combo aplicações
echo "		<select onchange="javascript:location.href=this.value">"
echo "			<option value=\"Sistema\">Sistema...</option>"
find $app_history_dir_tree/ -mindepth 1 -maxdepth 1 -type d | sort | xargs -I{} -d '\n' basename {} | sed -r "s|(.*)|\t\t<option value=\"$STARTPAGE?Sistema=\1\">\1</option>|"
echo "		</select>"

#Histórico
echo "      <p>"
echo "          <table cellpadding=5 width=100% style=\"$html_table_style\">"
head -n 1 "$tmp_dir/html_table"
head -n $((($PAGE*$html_table_size)+1)) $tmp_dir/html_table | tail -n $print_size
echo "          </table>"
echo "      </p>"

#Links
echo "      <table width=100% style=\"text-align:left;color:black\">"
echo "		    <tr> <td><br></td> </tr>"
echo "          <tr> <td><a href=\"$STARTPAGE\" style=\"color:black\" >Início</a> </td> <td style=\"text-align:right\">Página: $NAV</td> </tr>"
echo "          <tr> <td><a href=\"$apache_log_alias\" style=\"color:black\">Logs</td> </tr>"
echo "          <tr> <td><a href=\"${STARTPAGE}/search.cgi\" style=\"color:black\">Pesquisa Avançada</td> </tr>"
echo "      </table>"

echo '  </body>'
echo '</html>'

end 0

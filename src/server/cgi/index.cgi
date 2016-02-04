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

MIN_PAGE=1

if [ -z $QUERY_STRING ]; then
	STARTPAGE="$REQUEST_URI"
	PAGE=1
	NEXT=2
	PREV=0
	APP=''
	NEXT_URI="$STARTPAGE?p=$NEXT"

else
	STARTPAGE="$(echo "$REQUEST_URI" | sed -r "s/\?$QUERY_STRING$//")"

	APP="$(echo "$col_app" | sed -r 's/\[//' | sed -r 's/\]//')"
	APP=$(echo "$QUERY_STRING" | sed -r "s/^.*$APP=([^\&\=]+)&?.*$/\1/" | sed -r "s/%20/ /g" | grep -vx "$QUERY_STRING")

	PAGE=$(echo "$QUERY_STRING" | sed -r "s/^.*p=([^\&\=]+)&?.*$/\1/" | sed -r "s/%20/ /g" | grep -vx "$QUERY_STRING")
	test -n "$PAGE" || PAGE=1

	NEXT=$(($PAGE+1))
	PREV=$(($PAGE-1))

	NEXT_URI="$(echo "$REQUEST_URI" | sed -r "s/^(.*p=)$PAGE(.*)$/\1$NEXT\2/")"
        test "$NEXT_URI" != "$REQUEST_URI" || NEXT_URI="$REQUEST_URI&p=$NEXT"

	PREV_URI="$(echo "$REQUEST_URI" | sed -r "s/^(.*p=)$PAGE(.*)$/\1$PREV\2/")"
        test "$PREV_URI" != "$REQUEST_URI" || PREV_URI="$REQUEST_URI&p=$PREV"
       
fi

export 'APP'


$install_dir/cgi/html_table.cgi $file > $tmp_dir/html_table

DATA_SIZE=$(($(cat "$tmp_dir/html_table" | wc -l)-2))
test $DATA_SIZE -lt $history_html_size && print_size=$DATA_SIZE || print_size=$history_html_size

MAX_PAGE=$(($DATA_SIZE/$history_html_size))

FOOTER="$PAGE"

if [ $NEXT -le $MAX_PAGE ]; then
	FOOTER="$FOOTER <a href=\"$NEXT_URI\" style=\"color:black\">$NEXT</a>"
fi

if [ $PREV -ge $MIN_PAGE ]; then
	FOOTER="<a href=\"$PREV_URI\" style=\"color:black\">$PREV</a> $FOOTER"
fi

FOOTER="	<table width=100% style=\"text-align:left;color:black\">\
			<tr> <td><br></td> </tr>\
			<tr> <td><a href=\"${STARTPAGE}detalhe/\" style=\"color:black\">Logs</td> </tr>\
			<tr> <td><a href=\"$STARTPAGE\" style=\"color:black\" >Início</a> </td> <td style=\"text-align:right\">Página: $FOOTER</td> </tr>\
		</table>"

echo "		<select onchange="javascript:location.href=this.value">"
echo "			<option value=\"Sistema\">Sistema...</option>"
find $app_history_dir_tree/ -mindepth 1 -maxdepth 1 -type d | xargs -I{} -d '\n' basename {} | sed -r "s|(.*)|\t\t<option value=\"$STARTPAGE?Sistema=\1\">\1</option>|"
echo "		</select>"

echo "		<p>"
head -n 2 "$tmp_dir/html_table"
head -n $((($PAGE*$history_html_size)+2)) $tmp_dir/html_table | tail -n $print_size
echo "		</p>"
echo "$FOOTER"
echo '  </body>'
echo '</html>'

rm -f $tmp_dir/*
rmdir $tmp_dir

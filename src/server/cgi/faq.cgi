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

    test -n "$sleep_pid" && kill "$sleep_pid" &> /dev/null
    clean_locks
    wait &> /dev/null

    exit $1
}

trap "end 1" SIGQUIT SIGINT SIGHUP
mkdir $tmp_dir

# Cabeçalho
web_header

test -d "$faq_dir_tree" || end 1

regex_faq_question="[a-zA-Z0-9][a-zA-Z0-9 \.\?\!_,-]*"
regex_faq_tag="[a-zA-Z0-9\.-]+"

# listas de tópicos, categorias e tags
find $faq_dir_tree/ -mindepth 2 -type f | xargs -I{} grep -m 1 -H ".*" {} | tr -d ":" | sed -r "s|(.)$|\1\%|"> $tmp_dir/questions.list
find $faq_dir_tree/ -mindepth 1 -type d | sed -r "s|^$faq_dir_tree/||" | sort > $tmp_dir/categories.list
cut -d '%' -f 3 $tmp_dir/questions.list | tr " " "\n" | sort | uniq > $tmp_dir/tags.list

# Formulário de pesquisa
echo "      <p>"
echo "          <form action=\"$start_page\" method=\"get\">"
echo "      		<select class=\"select_small\" name=\"category\">"
echo "		        	<option value=\"\" selected>Categoria...</option>"
sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|" $tmp_dir/categories.list
echo "		        </select>"
echo "      		<select class=\"select_small\" name=\"tag\">"
echo "		        	<option value=\"\" selected>Tag...</option>"
sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|" $tmp_dir/tags.list
echo "		        </select>"
echo "              <input type=\"text\" class=\"text_large\" placeholder=\"Pesquisar nos artigos...\" name=\"search\"></input>"
echo "              <input type=\"submit\" name=\"proceed\" value=\"Buscar\">"
echo "          </form>"
echo "      </p>"

parsed=false

if [ "$REQUEST_METHOD" == "POST" ]; then
    if [ "$CONTENT_TYPE" == "application/x-www-form-urlencoded" ]; then
        test -n "$CONTENT_LENGTH" && read -n "$CONTENT_LENGTH" POST_STRING
        arg_string="&$(web_filter "$POST_STRING")&"
        proceed=$(echo "$arg_string" | sed -rn "s/^.*&proceed=([^\&]+)&.*$/\1/p")
        test -n "$proceed" && parsed=true

    elif echo "$CONTENT_TYPE" | grep -Ex "multipart/form-data; +boundary=.*" > /dev/null; then
        cat > "$tmp_dir/POST_CONTENT"
        parse_multipart_form "$tmp_dir/POST_CONTENT"
        rm -f "$tmp_dir/POST_CONTENT"
        test -n "$proceed" && parsed=true

    fi

else
    arg_string="&$(web_filter "$QUERY_STRING")&"
    proceed=$(echo "$arg_string" | sed -rn "s/^.*&proceed=([^\&]+)&.*$/\1/p")
    test -n "$proceed" && parsed=true

fi

if ! $parsed; then

    query_file.sh -d "%" -r ";" -s 1 2 3 4 -f $tmp_dir/questions.list -o 1 4 asc | \
    sed -r "s|^$faq_dir_tree/||" | \
    sed -r "s|^([^;]*);([^;]*);([^;]*);([^;]*);$|<a_href=\"$start_page\?category=\1\">\1</a>;<a_href=\"$start_page\?category=\1\&question=\2\">\4</a>;\3;|" \
    > $tmp_dir/results

    while grep -Ex "([^;]*;){2}(<a_href.*/a>)?$regex_faq_tag [^;]+;" $tmp_dir/results > /dev/null; do
        sed -i -r "s|^(([^;]*;){2}(<a_href.*/a>)?)($regex_faq_tag) ([^;]+;)$|\1<a_href=\"$start_page?tag=\2\">\2</a>\3|" $tmp_dir/results
    done

    sed -i -r "s|<a_href=|<a href=|g" $tmp_dir/results
    sed -i -r "s|;|</td><td>|g" $tmp_dir/results
    sed -i -r "s|^(.)|<tr><td>\1|" $tmp_dir/results
    sed -i -r "s|<td>$|</tr>|" $tmp_dir/results


    echo "<table>"
    echo "<tr><th>Categoria</th><th>Tópico</th><th>Tags</th></tr>"
    cat $tmp_dir/results
    echo "</table>"

fi

end 0

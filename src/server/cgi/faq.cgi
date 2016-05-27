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

regex_question="[a-zA-Z0-9][a-zA-Z0-9 \.\?\!_,-]*"
code_question_mark="___________"
code_exclamation_mark="_______"
code_comma="_____"
code_space="___"
sed_decode_question_cmd="s|$code_question_mark|\?|g;s|$code_exclamation_mark|\!|g;s|$code_comma|,|g;s|$code_space| |g"

# listas de tópicos, categorias e tags
find $faq_dir_tree/ -mindepth 2 -type f | sort > $tmp_dir/files.list
find $faq_dir_tree/ -mindepth 1 -type d | sort > $tmp_dir/categories.list
mklist "$(find $faq_dir_tree/ -mindepth 2 -type f | cut -d '%' -f 2 | sed -r 's/(.)$/\1 /;s/ +/ /g' | tr -d "\n")" | sort | uniq > $tmp_dir/tags.list

# Formulário de pesquisa
echo "      <p>"
echo "          <form action=\"$start_page\" method=\"get\">"
echo "      		<select class=\"select_default\" name=\"category\">"
echo "		        	<option value=\"\" selected>Categoria...</option>"
sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|" $tmp_dir/categories.list
echo "		        </select>"
echo "      		<select class=\"select_default\" name=\"tag\">"
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

    query_file.sh -d "%" -r "</td><td>" -s all -f $tmp_dir/files.list | sed -r "s|^(.)|<tr><td>\1|;s|<td>$|</tr>|;$sed_decode_question_cmd"

fi

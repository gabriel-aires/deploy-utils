#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

function end() {
    test "$1" == "0" || echo "      <p><b>Operação inválida.</b></p>"
    echo "</div>"
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

function chk_conflict() {

    local test_filename="$1"
    local test_dir="$2"

    test -d "$faq_dir_tree" || end 1
    test -f "$tmp_dir/questions.list" || end 1
    test -n "$test_filename" || end 1
    test -n "$test_dir" || end 1

    query_file.sh -d "%" -r ";" \
        -s 1 2 3 4 \
        -f $tmp_dir/questions.list \
        -w "1==$test_dir/" "2==$test_filename" \
        -o 1 4 asc \
        > $tmp_dir/results

    if [ "$(cat $tmp_dir/results | wc -l)" -ne 0 ]; then
        echo "<p><b>Há um tópico conflitante. Favor removê-lo antes de continuar:</b></p>"
        echo "<pre>"
        cat $tmp_dir/results | sed -r "s|^([^;]*);([^;]*);([^;]*);([^;]*);$|arquivo:\t\2|"
        cat $tmp_dir/results | sed -r "s|^([^;]*);([^;]*);([^;]*);([^;]*);$|tópico: \t\4|"
        cat $tmp_dir/results | sed -r "s|^$faq_dir_tree/([^;]*);([^;]*);([^;]*);([^;]*);$|categoria:\t\1|"
        cat $tmp_dir/results | sed -r "s|^([^;]*);([^;]*);([^;]*);([^;]*);$|tags:   \t\3|"
        echo "</pre>"
        end 1
    fi
}

function clean_category() {

    local clean_dir="$1"

    test -d "$faq_dir_tree" || end 1
    test -d "$clean_dir" || end 1

    rmdir "$clean_dir" &> /dev/null
    clean_dir="$(dirname "$clean_dir")"

    while [ "$clean_dir" != "$faq_dir_tree" ]; do
        rmdir "$clean_dir" &> /dev/null
        clean_dir="$(dirname "$clean_dir")"
    done

}

function display_faq() {

    test -f $tmp_dir/results || return 1

    local content_file="$(head -n 1 $tmp_dir/results | sed -r "s|^([^;]*);([^;]*);[^;]*;[^;]*;$|\1\2|")"
    local category_txt="$(sed -r "s|^$faq_dir_tree/([^;]*);[^;]*;[^;]*;[^;]*;$|\1|" $tmp_dir/results)"
    local tag_txt="$(sed -r "s|^[^;]*;[^;]*;([^;]*);[^;]*;$|\1|" $tmp_dir/results)"

    sed -i -r "s|^$faq_dir_tree/||" $tmp_dir/results
    sed -i -r "s|^([^;]*);([^;]*);([^;]*);([^;]*);$|<a_href=\"$start_page\?category=\1\&proceed=$proceed_search\">\1</a>;<a_href=\"$start_page\?category=\1\&question=\2\&proceed=$proceed_view\">\4</a>;\3;|" $tmp_dir/results

    while grep -Ex "([^;]*;){2}(<a_href.*/a> )?$regex_faq_tag [^;]*;" $tmp_dir/results > /dev/null; do
        sed -i -r "s|^(([^;]*;){2}(<a_href.*/a> )?)($regex_faq_tag) ([^;]*;)$|\1<a_href=\"$start_page\?tag=\4\&proceed=$proceed_search\">\4</a> \5|" $tmp_dir/results
    done

    sed -i -r "s|^(([^;]*;){2}(<a_href.*/a> )?)($regex_faq_tag);$|\1<a_href=\"$start_page\?tag=\4\&proceed=$proceed_search\">\4</a>;|" $tmp_dir/results

    while grep -E "<a_href=\"$start_page\?[^\"]*/[^\"]*\">" $tmp_dir/results > /dev/null; do
        sed -i -r "s|(<a_href=\"$start_page\?[^\"]*)/([^\"]*\">)|\1\%2F\2|" $tmp_dir/results
    done

    sed -i -r "s|<a_href=|<a href=|g" $tmp_dir/results

    if [ $(cat $tmp_dir/results | wc -l) -eq 1 ]; then

        local category_href="$(sed -r "s|^([^;]*);[^;]*;[^;]*;$|\1|" $tmp_dir/results)"
        local tag_href="$(sed -r "s|^[^;]*;[^;]*;([^;]*);$|\1|" $tmp_dir/results)"

        echo "<h3>"
        head -n 1 "$content_file"
        echo "</h3>"
        echo "<div class=\"cfg_color column faq_override\">"
        sed '1d;$d' "$content_file" | tr "\n" '<' | sed -r 's|<|<br>|g'
        echo "</div>"
        echo "<p><b>Categoria:</b> $category_href</p>"
        echo "<p><b>Tags:</b> $tag_href</p>"
        # Formulário de Edição
        if "$allow_edit"; then

            echo "<fieldset>"
            echo "  <legend> Editar... </legend>"

            # Sobrescrever
            echo "      <div class=\"column faq_override\">"
            echo "          <form action=\"$start_page\" method=\"post\" enctype=\"multipart/form-data\">"
            echo "              <p>"
            echo "                  <b>Atualizar tópico:</b>"
            echo "                  <input type=\"file\" name=\"update_file\"></input>"
            echo "                  <input type=\"hidden\" name=\"question_file\" value=\"$content_file\">"
            echo "                  <input type=\"submit\" name=\"proceed\" value=\"$proceed_overwrite\">"
            echo "              </p>"
            echo "          </form>"
            echo "      </div>"

            # Modificar
            echo "      <div class=\"column faq_override\">"
            echo "          <form action=\"$start_page\" method=\"post\">"
            echo "              <p>"
            echo "                  <b>Categoria:</b>"
            echo "                  <input type=\"text\" name=\"update_category\" value=\"$category_txt\"></input>"
            echo "                  <input type=\"hidden\" name=\"category\" value=\"$category_txt\">"
            echo "                  <b>Tags:</b>"
            echo "                  <input type=\"text\" name=\"update_tag\" value=\"$tag_txt\"></input>"
            echo "                  <input type=\"hidden\" name=\"tag\" value=\"$tag_txt\">"
            echo "                  <input type=\"hidden\" name=\"question_file\" value=\"$content_file\">"
            echo "                  <input type=\"submit\" name=\"proceed\" value=\"$proceed_modify\">"
            echo "              </p>"
            echo "          </form>"
            echo "      </div>"

            # Remover
            echo "      <div class=\"column faq_override\">"
            echo "          <form action=\"$start_page\" method=\"post\">"
            echo "              <p>"
            echo "                  <b>Excluir tópico:</b>"
            echo "                  <input type=\"hidden\" name=\"question_file\" value=\"$content_file\">"
            echo "                  <input type=\"submit\" name=\"proceed\" value=\"$proceed_remove\">"
            echo "              </p>"
            echo "          </form>"
            echo "      </div>"

            echo "</fieldset>"
        fi

    else

        sed -i -r "s|^([^;]*;)([^;]*;)([^;]*;)$|\2\1\3|" $tmp_dir/results
        sed -i -r "s|;|</td><td>|g" $tmp_dir/results
        sed -i -r "s|^(.)|<tr class=\"cfg_color\"><td width=80%>\1|" $tmp_dir/results
        sed -i -r "s|<td>$|</tr>|" $tmp_dir/results

        web_tr_pagination "$tmp_dir/results" "0"

        echo "<h3>Tópicos:</h3>"
        echo "<table id=\"faq\" width=100%>"
        echo "<tr class=\"header_color\"><td width=80%>Tópico</td><td>Categoria</td><td>Tags</td></tr>"
        eval "$print_page_cmd"
        echo "</table>"

    fi

    return 0

}

trap "end 1" SIGQUIT SIGINT SIGHUP
mkdir $tmp_dir

# Cabeçalho
web_header

proceed_search="Buscar"
proceed_view="Exibir"
proceed_new="Novo"
proceed_remove="Remover"
proceed_overwrite="Sobrescrever"
proceed_modify="Modificar Atributos"
allow_edit=false
membership "$REMOTE_USER" | grep -Ex 'admin' > /dev/null && allow_edit=true

# Sidebar
echo "      <div class=\"column_small\" id=\"faq_sidebar\">"

test -d "$faq_dir_tree" || end 1
test -n "$regex_faq_category" || end 1
test -n "$regex_faq_tag" || end 1
test -n "$regex_faq_taglist" || end 1

# listas de tópicos, categorias e tags
touch $tmp_dir/questions.list
touch $tmp_dir/categories.list
touch $tmp_dir/tags.list

find $faq_dir_tree/ -mindepth 2 -type f | while read file; do
    file_question="$(sed -n '1p' "$file")"
    file_tags="$(sed -n '$p' "$file")"
    file_category="$(dirname "$file" | sed -r "s|^$faq_dir_tree/||")"
    file_name="$(basename "$file")"
    echo "$faq_dir_tree/$file_category/%$file_name%$file_tags%$file_question%" >> $tmp_dir/questions.list
done

cut -d '%' -f 3 $tmp_dir/questions.list | tr " " "\n" | sort | uniq >> $tmp_dir/tags.list
cut -d '%' -f 1 $tmp_dir/questions.list | sed -r "s|^$faq_dir_tree/||;s|/$||" | sort | uniq >> $tmp_dir/categories.list

# Formulário de pesquisa
echo "          <h3>Busca:</h3>"
echo "          <form action=\"$start_page\" method=\"get\">"
echo "              <p>"
echo "                  <select class=\"select_large_percent\" name=\"category\">"
echo "                          <option value=\"\" selected>Categoria...</option>"
sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|" $tmp_dir/categories.list
echo "                  </select>"
echo "              </p>"
echo "              <p>"
echo "                  <select class=\"select_large_percent\" name=\"tag\">"
echo "                          <option value=\"\" selected>Tag...</option>"
sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|" $tmp_dir/tags.list
echo "                  </select>"
echo "              </p>"
echo "              <p>"
echo "                  <input type=\"text\" class=\"text_large_percent\" placeholder=\" Pesquisar...\" name=\"search\"></input>"
echo "              </p>"
echo "              <p>"
echo "                  <input type=\"submit\" name=\"proceed\" value=\"$proceed_search\">"
echo "              </p>"
echo "          </form>"

# Formulário de upload
if "$allow_edit"; then
    echo "          <br>"
    echo "          <h3>Adicionar:</h3>"
    echo "          <form action=\"$start_page\" method=\"post\" enctype=\"multipart/form-data\">"
    echo "              <p>"
    echo "                  <button type=\"button\" class=\"text_large_percent\"><label for=\"question_file\">Selecionar Arquivo...</label></button>"
    echo "                  <input type=\"file\" style=\"visibility: hidden\" id=\"question_file\" name=\"question_file\"></input>"
    echo "                  <input type=\"text\" class=\"text_large_percent\" placeholder=\" Categoria (obrigatório)\" name=\"category\"></input>"
    echo "              </p>"
    echo "              <p>"
    echo "                  <input type=\"text\" class=\"text_large_percent\" placeholder=\" Lista de tags\" name=\"tag\"></input>"
    echo "              </p>"
    echo "              <p>"
    echo "                  <input type=\"submit\" name=\"proceed\" value=\"$proceed_new\">"
    echo "              </p>"
    echo "          </form>"
fi

echo "      </div>"

# Tópicos
echo "<div class=\"column_large\" id=\"faq_topics\">"

parsed=false
var_string=false

if [ "$REQUEST_METHOD" == "POST" ]; then

    if [ "$CONTENT_TYPE" == "application/x-www-form-urlencoded" ]; then
        test -n "$CONTENT_LENGTH" && read -n "$CONTENT_LENGTH" POST_STRING
        var_string=true
        arg_string="&$(web_filter "$POST_STRING")&"

    elif echo "$CONTENT_TYPE" | grep -Ex "multipart/form-data; +boundary=.*" > /dev/null; then
        cat > "$tmp_dir/POST_CONTENT"
        parse_multipart_form "$tmp_dir/POST_CONTENT"
        rm -f "$tmp_dir/POST_CONTENT"
    fi

else
    var_string=true
    arg_string="&$(web_filter "$QUERY_STRING")&"
fi

if $var_string; then
    category=$(echo "$arg_string" | sed -rn "s/^.*&category=([^\&]+)&.*$/\1/p")
    tag=$(echo "$arg_string" | sed -rn "s/^.*&tag=([^\&]+)&.*$/\1/p")
    question=$(echo "$arg_string" | sed -rn "s/^.*&question=([^\&]+)&.*$/\1/p")
    question_file=$(echo "$arg_string" | sed -rn "s/^.*&question_file=([^\&]+)&.*$/\1/p")
    update_category=$(echo "$arg_string" | sed -rn "s/^.*&update_category=([^\&]+)&.*$/\1/p")
    update_tag=$(echo "$arg_string" | sed -rn "s/^.*&update_tag=([^\&]+)&.*$/\1/p")
    update_file=$(echo "$arg_string" | sed -rn "s/^.*&update_file=([^\&]+)&.*$/\1/p")
    search=$(echo "$arg_string" | sed -rn "s/^.*&search=([^\&]+)&.*$/\1/p")
    proceed=$(echo "$arg_string" | sed -rn "s/^.*&proceed=([^\&]+)&.*$/\1/p")
fi

test -n "$proceed" && parsed=true

if ! $parsed; then

    query_file.sh -d "%" -r ";" -s 1 2 3 4 -f $tmp_dir/questions.list -o 1 4 asc > $tmp_dir/results
    display_faq

else

    case "$proceed" in

        "$proceed_search")

            if [ -n "$search" ]; then
                touch $tmp_dir/questions.aux

                cat $tmp_dir/questions.list | while read l; do
                    file="$(echo "$l" | cut -f1,2 -d '%' --output-delimiter='')"
                    grep -ilF "$search" "$file" &> /dev/null && echo "$l" >> $tmp_dir/questions.aux
                done

                mv -f $tmp_dir/questions.aux $tmp_dir/questions.list
            fi

            where=''
            test -n "$category" && category_aux="$(echo "$category" | sed -r 's|([\.-])|\\\1|g;s|/$||')" && where="$where 1=~$faq_dir_tree/${category_aux}/.*"
            test -n "$tag" && tag_aux="$(echo "$tag" | sed -r 's|([\.-])|\\\1|g')" && where="$where 3=~(.+[[:blank:]])*${tag_aux}([[:blank:]].+)*"
            test -n "$where" && where="-w $where"

            query_file.sh -d "%" -r ";" \
                -s 1 2 3 4 \
                -f $tmp_dir/questions.list \
                $where \
                -o 1 4 asc \
                > $tmp_dir/results

            display_faq

        ;;

        "$proceed_view")

            query_file.sh -d "%" -r ";" \
                -s 1 2 3 4 \
                -f $tmp_dir/questions.list \
                -w "1==$faq_dir_tree/$category" "2==$question" \
                -o 1 4 asc \
                > $tmp_dir/results

            display_faq

        ;;

        "$proceed_new")

            $allow_edit || end 1
            test -f "$question_file" || end 1

            dos2unix "$question_file" &> /dev/null
            question_filename="$(basename "$question_file")"
            question_filetype="$(file -bi "$question_file")"
            question_txt="$(head -n 1 "$question_file")"
            question_dir="$(echo "$faq_dir_tree/$category" | sed -r "s|/+|/|g;s|/$||")"

            test -n "$tag" && valid "tag" "regex_faq_taglist" "<p><b>Erro. Lista de tags inválida: '$tag'</b></p>"
            valid "category" "regex_faq_category" "<p><b>Erro. Categoria inválida: '$category'</b></p>"
            valid "question_filetype" "regex_faq_filetype" "<p><b>Erro. Tipo de arquivo inválido: '$question_filetype'</b></p>"
            chk_conflict "$question_filename" "$question_dir"

            mkdir -p "$question_dir"
            echo "$tag" >> "$question_file"
            cp "$question_file" "$question_dir/${question_filename}"
            echo "<p><b>Tópico '$question_txt' adicionado com sucesso.</b></p>"

        ;;

        "$proceed_remove")

            $allow_edit || end 1
            test -f "$question_file" || end 1

            question_txt="$(head -n 1 "$question_file")"
            question_dir="$(dirname "$question_file")"

            rm -f "$question_file"
            clean_category "$question_dir"

            echo "<p><b>Tópico '$question_txt' removido.</b></p>"

        ;;

        "$proceed_overwrite")

            $allow_edit || end 1
            test -f "$question_file" || end 1
            test -f "$update_file" || end 1

            dos2unix "$update_file" &> /dev/null
            update_filetype="$(file -bi "$update_file")"
            update_txt="$(head -n 1 "$update_file")"
            question_txt="$(head -n 1 "$question_file")"
            question_tag="$(tail -n 1 "$question_file")"

            valid "update_filetype" "regex_faq_filetype" "<p><b>Erro. Tipo de arquivo inválido: '$update_filetype'</b></p>"

            if [ "$update_txt" != "$question_txt" ]; then
                echo "<p><b>Erro. O tópico '$update_txt' não corresponde ao original: '$question_txt'.</b></p>"
                end 1
            else
                cp -f "$update_file" "$question_file"
                echo "$question_tag" >> "$question_file"
                echo "<p><b>Tópico '$question_txt' atualizado.</b></p>"
            fi

        ;;

        "$proceed_modify")

            $allow_edit || end 1
            test -f "$question_file" || end 1
            test -n "$category" || end 1
            test -n "$update_category" || end 1
            valid "update_category" "regex_faq_category" "<p><b>Erro. Categoria inválida: '$update_category'</b></p>"
            question_txt="$(head -n 1 "$question_file")"
            category="$(echo "$category" | sed -r "s|/+|/|g;s|/$||")"
            update_category="$(echo "$update_category" | sed -r "s|/+|/|g;s|/$||")"
            question_updated=false

            # Alterar tags
            if [ "$update_tag" != "$tag" ]; then
                test -n "$update_tag" && valid "update_tag" "regex_faq_taglist" "<p><b>Erro. Lista de tags inválida: '$update_tag'</b></p>"
                sed -i -r "\$s|^$tag$|$update_tag|" "$question_file"
                echo "<p><b>Tags atualizadas para o tópico '$question_txt'.</b></p>"
                question_updated=true
            fi

            # Alterar Categoria
            if [ "$update_category" != "$category" ]; then
                question_dir="$(dirname "$question_file")"
                question_filename="$(basename "$question_file")"
                update_dir="$faq_dir_tree/$update_category"
                chk_conflict "$question_filename" "$update_dir"
                mkdir -p "$update_dir"
                mv "$question_file" "$update_dir/${question_filename}"
                clean_category "$question_dir"
                echo "<p><b>Categoria atualizada para o tópico '$question_txt'.</b></p>"
                question_updated=true
            fi

            $question_updated || echo "<p><b>Nenhuma alteração indicada para o tópico '$question_txt'.</b></p>"

        ;;

        *) end 1 ;;

    esac

fi

end 0

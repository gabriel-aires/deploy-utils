#!/bin/bash

# Funções comuns do servidor

function web_filter() {   # Filtra o input de formulários cgi

    set -f

    # Decodifica caracteres necessários,
    # Remove demais caracteres especiais,
    # Realiza substituições auxiliares

    echo "$1" | \
        sed -r 's|\+| |g' | \
        sed -r 's|%21|\!|g' | \
        sed -r 's|%25|::percent::|g' | \
        sed -r 's|%2C|,|g' | \
        sed -r 's|%2F|/|g' | \
        sed -r 's|%3A|\:|g' | \
        sed -r 's|%3D|=|g' | \
        sed -r 's|%40|@|g' | \
        sed -r 's|%..||g' | \
        sed -r 's|\*||g' | \
        sed -r 's|::percent::|%|g' | \
        sed -r 's| +| |g' | \
        sed -r 's| $||g'

    set +f

}

function web_header () {

    test "$(basename $SCRIPT_NAME)" == 'index.cgi' && start_page="$(dirname $SCRIPT_NAME)/" || start_page="$SCRIPT_NAME"
    page_name=$(basename $SCRIPT_NAME | cut -f1 -d '.')
    page_title="$(eval "echo \$cgi_${page_name}_title")"
    test -n "$REMOTE_USER" && welcome_msg="Bem vindo, $REMOTE_USER" || welcome_msg=""

    echo 'Content-type: text/html'
    echo ''
    echo '<html>'
    echo '  <head>'
    echo '      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">'
    echo "      <title>$page_title</title>"
    echo "      <link rel=\"stylesheet\" type=\"text/css\" href=\"$apache_css_alias/default.css\">"
    echo '  </head>'
    echo "  <body>"
    echo "      <div id=\"header\" class=\"header_color\">"
    echo "          <div id=\"title\">$page_title</div>"
    echo "          <div id=\"welcome\">$welcome_msg</div>"
    echo "      </div>"
    echo "      <div id=\"main\">"

    return 0
}

function web_query_history () {

    file=$history_dir/$history_csv_file

    if [ -f "$file" ]; then

        export 'SELECT' 'DISTINCT' 'TOP' 'WHERE' 'ORDERBY'
        table_content="$tmp_dir/html_table"
        $install_dir/cgi/table_data.cgi $file > $table_content

        if [ -z "$QUERY_STRING" ]; then
            view_size="$cgi_table_size"
            page=1
            next=2
            prev=0
            next_uri="$start_page?p=$next"
        else
            view_size=$(echo "$arg_string" | sed -rn "s/^.*&n=([^\&]+)&.*$/\1/p")
            test -z "$view_size" && view_size="$cgi_table_size"

            page=$(echo "$arg_string" | sed -rn "s/^.*&p=([^\&]+)&.*$/\1/p")
            test -z "$page" && page=1

            next=$(($page+1))
            prev=$(($page-1))

            next_uri="$(echo "$REQUEST_URI" | sed -rn "s/^(.*[&\?]p=)$page(.*)$/\1$next\2/p")"
            test -z "$next_uri" && next_uri="$REQUEST_URI&p=$next"

            prev_uri="$(echo "$REQUEST_URI" | sed -rn "s/^(.*[&\?]p=)$page(.*)$/\1$prev\2/p")"
            test -z "$prev_uri" && prev_uri="$REQUEST_URI&p=$prev"
        fi

        data_size=$(($(cat "$table_content" | wc -l)-1))
        min_page=1
        max_page=$(($data_size/$view_size))
        test $(($max_page*$view_size)) -lt $data_size && ((max_page++))
        test $page -eq $max_page && print_size=$(($view_size-($view_size*$max_page-$data_size))) || print_size=$view_size
        nav="$page"

        if [ $next -le $max_page ]; then
            nav="$nav <a href=\"$next_uri\">$next</a>"
        fi

        if [ $prev -ge $min_page ]; then
            nav="<a href=\"$prev_uri\">$prev</a> $nav"
        fi

        echo "      <p>"
        echo "          <table class=\"query_table\">"
        head -n 1 "$table_content"
        test $data_size -ge 1 && head -n $((($page*$view_size)+1)) "$table_content" | tail -n "$print_size" || echo "<tr><td colspan=\"100\">Nenhum registro encontrado.</td></tr>"
        echo "          </table>"
        echo "      </p>"

        nav_right="<div id=\"nav_right\"><p>Página: $nav</p></div>"

    else

        echo "<p>Arquivo de histórico inexistente</p>"

    fi

    return 0
}

function web_footer () {

    mklist "$cgi_list_pages" $tmp_dir/cgi_list_pages
    local index=1
    local count=0
    local max=3

    echo "      <div id=\"navbar\">"
    echo "          <div id=\"nav_left\">"
    echo "              <p><a href=\"$start_page\">Início</a></p>"
    echo "          </div>"
    echo "          $nav_right"
    echo "      </div>"
    echo "      <hr>"
    echo "      <div id=\"footer\">"
    echo "          <div id=\"links_$index\">"
    while read link_name; do

        link_uri="$(dirname $SCRIPT_NAME)/$link_name.cgi"
        link_title="$(eval "echo \$cgi_${link_name}_title")"
        if [ "$SCRIPT_NAME" != "$link_uri" ]; then
            ((count++))
            echo "              <p><a href=\"$link_uri\">"$link_title"</a></p>"
            if [ "$count" -eq "$max" ]; then
                ((index++))
                echo "          </div>"
                echo "          <div id=\"links_$index\">"
                count=0
            fi
        fi

    done < $tmp_dir/cgi_list_pages
    echo "              <p><a href=\"$apache_log_alias\">Logs</a></p>"
    echo "          </div>"
    echo "      </div>"
    echo "  </div>"
    echo '  </body>'
    echo '</html>'

    return 0

}

function add_login() {

    test -f "$web_users_file" || return 1

    if [ -n "$1" ] && [ -n "$2" ]; then
        local user="$1"
        local password="$2"
        htpasswd -b "$web_users_file" "$user" "$password" || return 1
    else
        return 1
    fi

    return 0

}

function delete_login() {

    test -f "$web_users_file" || return 1

    if [ -n "$1" ]; then
        local user="$1"
        htpasswd -D "$web_users_file" "$user" || end 1
    else
        return 1
    fi

    return 0

}

function add_group() {

    test -f "$web_groups_file" && echo "$1:" >> "$web_groups_file" || return 1
    return 0

}

function delete_group() {

    test -f "$web_groups_file" || return 1
    touch "$web_groups_file" || return 1
    delete_regex="^$(echo "$1" | sed -r 's|([\.\-])|\\\1|g'):.*\$"
    sed -r "/$delete_regex/d" "$web_groups_file" > $tmp_dir/delete_group_tmp || return 1
    cp -f $tmp_dir/delete_group_tmp "$web_groups_file" || return 1

    return 0

}

function membership() {

    if [ -n "$1" ]; then
        local user_regex="$(echo "$1" | sed -r 's|([\.\-])|\\\1|g' )"
        grep -Ex "[^:]+:.* +$user_regex +.*|[^:]+:$user_regex +.*|[^:]+:.* +$user_regex|[^:]+:$user_regex" "$web_groups_file" | cut -f1 -d ':'
    else
        return 1
    fi

    return 0

}

function members_of() {

    if [ -n "$1" ]; then
        local group_regex="$(echo "$1" | sed -r 's|([\.\-])|\\\1|g' )"
        local members="$(grep -Ex "$group_regex:.*" "$web_groups_file" | cut -f2 -d ':' | sed -r 's|^ +||' | sed -r 's| +$||')"
        test -n "$members" && mklist "$members"
    else
        return 1
    fi

    return 0

}

function unsubscribe() {

    if [ -n "$1" ] && [ -n "$2" ]; then
        local user_regex="$(echo "$1" | sed -r 's|([\.\-])|\\\1|g' )"
        local group_regex="$(echo "$2" | sed -r 's|([\.\-])|\\\1|g' )"
        sed -r "s/^($group_regex:.* +)($user_regex +)(.*)$/\1\3/" "$web_groups_file" > $tmp_dir/unsubscribe_tmp
        sed -i -r "s/^($group_regex:)($user_regex +)(.*)$/\1\3/" $tmp_dir/unsubscribe_tmp
        sed -i -r "s/^($group_regex:.* +)($user_regex)$/\1/" $tmp_dir/unsubscribe_tmp
        sed -r "s/^($group_regex:)($user_regex)$/\1/" $tmp_dir/unsubscribe_tmp > "$web_groups_file"
    else
        return 1
    fi

    return 0

}

function subscribe() {

    if [ -n "$1" ] && [ -n "$2" ]; then
        local user="$1"
        local group_regex="$(echo "$2" | sed -r 's|([\.\-])|\\\1|g' )"
        sed -r "s/^($group_regex:.*)$/\1 $user/" "$web_groups_file" > $tmp_dir/subscribe_tmp
        cp -f $tmp_dir/subscribe_tmp "$web_groups_file"
    else
        return 1
    fi

    return 0

}

function chk_permission() { #subject_type (user/group), #subject_name, #resource_type, #resource_name, #permission (read/write)

    test -f "$web_permissions_file" || return 1
    test "$#" -eq 5 || return 1

    local subject_type="$1"
    local subject_name="$2"
    local resource_type="$3"
    local resource_name="$4"
    local permission="$5"

    valid "subject_type" "Erro: subject_type inválido<br>." "continue" || return 1
    valid "subject_name" "Erro: subject_name inválido<br>." "continue" || return 1
    valid "resource_type" "Erro: resource_type inválido<br>." "continue" || return 1
    valid "resource_name" "Erro: resource_name inválido<br>." "continue" || return 1
    valid "permission" "Erro: o parâmetro permission é inválido<br>." "continue" || return 1

    return 0

}

function add_permission() { #subject_type (user/group), #subject_name, #resource_type, #resource_name, #permission (read/write)

    chk_permission $@ || return 1
    touch "$web_permissions_file" || return 1

    if [ "$(cat $web_permissions_file | wc -l)" -eq 0 ]; then
        local header="$(echo "$col_subject_type$col_subject_name$col_resource_type$col_resource_name$col_permission" | sed -r 's/\[//g' | sed -r "s/\]/$delim/g")"
        echo "$header" >> "$web_permissions_file"
    fi

    if grep -Ex "$1$delim$2$delim$3$delim$4$delim($regex_permission)$delim" "$web_permissions_file" > /dev/null; then
        echo "<p>Já foi atribuída uma permissão correspondente ao sujeito '$2' / recurso '$4'. Favor remover a permissão conflitante e tentar novamente.</p>"
        return 1
    else
        echo "$1$delim$2$delim$3$delim$4$delim$5$delim" >> "$web_permissions_file"
    fi

    return 0

}

function delete_permission() { #subject_type (user/group), #subject_name, #resource_type, #resource_name, #permission (read/write)

    chk_permission $@ || return 1

    touch "$web_permissions_file" || return 1
    delete_regex="^$(echo "$1$delim$2$delim$3$delim$4$delim$5$delim" | sed -r 's|([\.\-])|\\\1|g')\$"
    sed -r "/$delete_regex/d" "$web_permissions_file" > $tmp_dir/delete_permission_tmp || return 1
    cp -f $tmp_dir/delete_permission_tmp "$web_permissions_file" || return 1

    return 0

}

function clearance() { #subject_type (user/group), #subject_name, #resource_type, #resource_name, #permission (read/write)

    test "$1" == "user" || return 1
    test "$#" -eq "5" || return 1
    chk_permission "$1" "$2" "$3" "$4" "$5" || return 1
    membership "$2" | grep -Ex "admin" > /dev/null && return 0

    local groups_regex=''
    local groups_permissions=''
    local permission="$5"
    local effective="$(query_file.sh -d "$delim" -r "" -x 1 -s 5 -t 1 -f $web_permissions_file -w 1=="user" 2=="$2" 3=="$3" 4=="$4")" || return 1

    if [ -z "$effective" ]; then
        groups_regex="($(membership "$2" | tr "\n" "|" | sed -r 's|([\.\-])|\\\1|g' | sed -r "s/\|$//"))"
        groups_permissions="$(query_file.sh -d "$delim" -r "" -x 1 -s 5 -u -f $web_permissions_file -w 1=="group" 2=~"$groups_regex" 3=="$3" 4=="$4" -o 5 asc)"
        if [ -n "$groups_permissions" ]; then
            echo "$groups_permissions" | grep -Ex "read.*" > /dev/null && effective="read" || effective="write"
        fi
    fi

    test "$effective" = "write" && return 0
    test "$effective" = "$permission" && return 0
    return 1

}

function editconf () {      # Atualiza entrada em arquivo de configuração

    local exit_cmd="end 1 2> /dev/null || exit 1"
    local campo="$1"
    local valor_campo="$2"
    local arquivo_conf="$3"

    if [ -n "$campo" ] && [ -n "$arquivo_conf" ]; then

        touch $arquivo_conf || eval "$exit_cmd"

        if [ $(grep -Ex "^$campo\=.*$" $arquivo_conf | wc -l) -ne 1 ]; then
            sed -i -r "/^$campo\=.*$/d" "$arquivo_conf"
            echo "$campo='$valor_campo'" >> "$arquivo_conf"
        else
            grep -Ex "$campo='$valor_campo'|$campo=\"$valor_campo\"" "$arquivo_conf" > /dev/null
            test "$?" -eq 1 && sed -i -r "s|^($campo\=).*$|\1\'$valor_campo\'|" "$arquivo_conf"
        fi

    else
        echo "Erro. Não foi possível editar o arquivo de configuração." && $exit_cmd
    fi

}

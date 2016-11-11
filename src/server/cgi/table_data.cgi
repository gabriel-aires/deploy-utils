#!/bin/bash
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

data_file=$1
header_file=$tmp_dir/header

function end() {
    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    wait
    exit $1
}

trap "end 1" SIGQUIT SIGINT SIGHUP SIGTERM

mkdir -p $tmp_dir

# Valores default para a construção da query
test -z "$SELECT" && SELECT="--select all ${col[flag]}"
test -z "$DISTINCT" && DISTINCT=''
test -z "$TOP" && TOP=''
test -z "$WHERE" && WHERE=''
test -z "$ORDERBY" && ORDERBY="--order-by ${col[year]} ${col[month]} ${col[day]} desc"

# Para que haja diferenciação entre deploys com erro e sucesso, a flag de deploy deve ser a última coluna
change_color=false
col_flag_aux=$(echo "${col[flag]}" | sed -r 's|(\[)|\\\1|' | sed -r 's|(\])|\\\1|')
col_flag_name=$(echo "${col[flag]}" | sed -r 's|(\[)||' | sed -r 's|(\])||')
if echo "$SELECT" | grep -E " ${col[flag]}_aux" > /dev/null; then
    SELECT="$(echo "$SELECT" | sed -r "s| ${col[flag]}_aux||") ${col[flag]}"
    change_color=true
fi

# CABEÇALHO
head -n 1 $data_file > $header_file
query_file.sh --delim "$delim" --replace-delim '</th><th>' $SELECT --from $header_file > $tmp_dir/html 2> /dev/null

# DADOS
query_file.sh --delim "$delim" --replace-delim '</td><td>' --header 1 $SELECT $DISTINCT $TOP --from $data_file $WHERE $ORDERBY  >> $tmp_dir/html 2> /dev/null

if $change_color; then
    sed -i -r "s|^(.*)<th>${col[flag]}_name</th><th>$|\t\t\t<tr><th>\1</tr>|" $tmp_dir/html
    sed -i -r "s|^(.*)<td>1</td><td>$|\t\t\t<tr><td>\1</tr>|" $tmp_dir/html
    sed -i -r "s|^(.*)<td>0</td><td>$|\t\t\t<tr class=\"warning\"><td>\1</tr>|" $tmp_dir/html
else
    sed -i -r "s|^(.*)<th>$|\t\t\t<tr><th>\1</tr>|" $tmp_dir/html
    sed -i -r "s|^(.*)<td>$|\t\t\t<tr><td>\1</tr>|" $tmp_dir/html
fi

cat $tmp_dir/html

end 0

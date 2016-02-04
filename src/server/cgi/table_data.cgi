#!/bin/bash
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/init.sh || exit 1

data_file=$1

function end() {
    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    wait
    exit $1
}

trap "end 1" SIGQUIT SIGINT SIGHUP EXIT ERR

mkdir -p $tmp_dir

# Valores default para a construção da query
test -z $SELECT && SELECT="--select all"
test -z $TOP && TOP=''
test -z $WHERE && WHERE=''
test -z $ORDERBY && ORDERBY="--order-by $col_year $col_month $col_day desc"

# A última coluna deve ser a flag de deploy (possibilita diferenciação entre deploys com erro e sucesso)
col_flag_aux=$(echo "$col_flag" | sed -r 's|(\[)|\\\1|' | sed -r 's|(\])|\\\1|')
col_flag_name=$(echo "$col_flag" | sed -r 's|(\[)||' | sed -r 's|(\])||')
if echo "$SELECT" | grep -Ev " (all|$col_flag_aux)$" > /dev/null; then
    SELECT="$SELECT $col_flag"
fi

# CABEÇALHO
query_file.sh --delim "$delim" --replace-delim '</th><th>' $SELECT --top 1 --from $data_file > $tmp_dir/html

# DADOS
query_file.sh --delim "$delim" --replace-delim '</td><td>' --header 1 $SELECT --from $data_file $WHERE $ORDERBY >> $tmp_dir/html

sed -i -r "s|^(.*)<th>$col_flag_name</th><th>$|\t\t\t<tr style=\"$html_th_style\"><th>\1</tr>|" $tmp_dir/html
sed -i -r "s|^(.*)<td>1</td><td>$|\t\t\t<tr style=\"$html_tr_style_default\"><td>\1</tr>|" $tmp_dir/html
sed -i -r "s|^(.*)<td>0</td><td>$|\t\t\t<tr style=\"$html_tr_style_warning\"><td>\1</tr>|" $tmp_dir/html

cat $tmp_dir/html

end 0

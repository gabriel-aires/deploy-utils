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

test -z $SELECT && SELECT="--select \'\*\'"
test -z $TOP && TOP=''
test -z $WHERE && WHERE=''
test -z $ORDERBY && ORDERBY="--order-by $col_year $col_month $col_day desc"

# CABEÇALHO
query_file.sh --delim "$delim" --replace-delim '</th><th>' $SELECT --top 1 --from $data_file > $tmp_dir/html 2> /dev/null

# DADOS
query_file.sh --delim "$delim" --replace-delim '</td><td>' --header 1 $SELECT --from $data_file $WHERE $ORDERBY >> $tmp_dir/html 2> /dev/null

sed -i -r 's|^(.*)<th>Flag</th><th>$|\t\t\t<tr style="@@html_th_style@@"><th>\1</tr>|' $tmp_dir/html
sed -i -r 's|^(.*)<td>1</td><td>$|\t\t\t<tr style="@@html_tr_style_default@@"><td>\1</tr>|' $tmp_dir/html
sed -i -r 's|^(.*)<td>0</td><td>$|\t\t\t<tr style="@@html_tr_style_warning@@"><td>\1</tr>|' $tmp_dir/html

sed -i -r "s|@@html_table_style@@|$html_table_style|" $tmp_dir/html
sed -i -r "s|@@html_th_style@@|$html_th_style|" $tmp_dir/html
sed -i -r "s|@@html_tr_style_default@@|$html_tr_style_default|" $tmp_dir/html
sed -i -r "s|@@html_tr_style_warning@@|$html_tr_style_warning|" $tmp_dir/html

cat $tmp_dir/html

end 0

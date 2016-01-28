#!/bin/bash
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1

function end() {
    if [ -d "$tmp_dir" ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    break 10 2> /dev/null
    exit $1
}

trap "end 1; exit 1" SIGQUIT SIGINT SIGHUP

pid="$$"
tmp_dir="$work_dir/$pid"
file=''
delim=''
output_delim='\t'
columns=()
set_value=()
s_index=0
filter=()
filter_type=()
filter_value=()
filter_cmd=()
filter_regex=()
f_index=0
grep_cmd="grep -E -x"
selection=''
preview=''

while true; do
    case "$1" in

        "-d"|"--delim")
            delim="$(echo "$2" | sed -r "s|([\\\+\-\.\?\^\$])|\\\\\1|g")"
            shift 2
            ;;

        "-r"|"--replace-delim")
            output_delim="$(echo "$2" | sed -r "s|([\\\+\-\.\?\^\$])|\\\\\1|g")"
            shift 2
            ;;

        "-s"|"--select")
            while echo "$2" | grep -Ex "[0-9]+"; do
                columns[$s_index]="$2"
                ((s_index++))
                shift
            done
            shift
            ;;

        "-f"|"--from")
            file="$2"
            shift 2
            ;;

        "-w"|"--where")
            while echo "$2" | grep -Ex "[0-9]+(==|=~|=%|!=).*"; do
                filter[$f_index]="$(echo "$2" | sed -r 's|^([0-9]+).*$|\1|')"
                filter_type[$f_index]="$(echo "$2" | sed -r 's/^[0-9]+(==|=~|=%|!=).*$/\1/')"
                filter_value[$f_index]="$(echo "$2" | sed -r 's/^[0-9]+(==|=~|=%|!=)(.*)$/\2/')"
                ((f_index++))
                shift
            done
            shift
            ;;

        "-h"|"--help")
            echo "Utilização: query_file [nomearquivo] [opções]"
            echo "Opções:"
            echo "-d|--delim: especificar caractere ou string que delimita os campos do arquivo. Ex: ';' (obrigatório)"
            echo "-r|--replace-delim: especificar caractere ou string que delimitará os campos exibidos. Ex: '|' (opcional)"
            echo "-s|--select: especificar ordem das colunas a serem selecionadas. Ex: "1" "2", etc (obrigatório)"
            echo "-f|--from: especificar arquivo. Ex: dados.csv (obrigatório)"
            echo "-w|--where: especificar filtro. Ex: '1==valor_exato' '2=~regex_valor' '3!=diferente_valor' '4=%contem_valor', etc (opcional)"
            end 1
            ;;

        '')
            break
            ;;

        *)
            echo "'$1':Argumento inválido." 1>&2
            end 1
            ;;

    esac
done

if [ ! -f "$file" ] || [ -z "$delim" ] || [ -z "${columns[0]}" ]; then
    echo "Erro. Argumentos insuficientes." 1>&2; end 1
elif ! echo "$delim" | grep -Ex "[[:print:]]+" > /dev/null; then
    echo "Delimitador inválido." 1>&2; end 1
fi

mkdir -p $tmp_dir

header="$(head -n 1 $file )"
size=1
part_regex="(.*)$delim"
line_regex=''
filter_regex=()
filter_cmd=()

while $(echo "$header" | grep -E "^(.*$delim){$size}" > /dev/null); do

    line_regex="$line_regex$part_regex"
    index=0

    while [ $index -lt $f_index ]; do

        if [ $size -eq ${filter[$index]} ]; then

            case ${filter_type[$index]} in
                '==') # match exato
                    filter_value[$index]=$(echo "${filter_value[$index]}" | sed -r "s|([\\\+\-\.\?\^\$])|\\\\\1|g")
                    filter_cmd[$index]="$grep_cmd"
                    ;;
                '=%') # contains
                    filter_value[$index]=$(echo "${filter_value[$index]}" | sed -r "s|([\\\+\-\.\?\^\$])|\\\\\1|g" | sed -r "s|^(.*)$|\.\*\1\.\*|")
                    filter_cmd[$index]="$grep_cmd"
                    ;;
                '=~') # regex
                    filter_cmd[$index]="$grep_cmd"
                    ;;
                '!=') # match inverso
                    filter_value[$index]=$(echo "${filter_value[$index]}" | sed -r "s|([\\\+\-\.\?\^\$])|\\\\\1|g")
                    filter_cmd[$index]="$grep_cmd -v"
                    ;;
            esac

            filter_regex[$index]="${filter_regex[$index]}${filter_value[$index]}$delim"

        else

            filter_regex[$index]="${filter_regex[$index]}$part_regex"

        fi

        ((index++))

    done

    ((size++))

done

index=0
cp $file $tmp_dir/preview_$index
while [ $index -lt $f_index ]; do
    ${filter_cmd[$index]} "${filter_regex[$index]}" "$tmp_dir/preview_$index" > "$tmp_dir/preview_$(($index+1))" || end 1
    ((index++))
done
preview="$tmp_dir/preview_$index"

index=0
while [ $index -lt $s_index ]; do
    selection="$selection\\${columns[$index]}$output_delim"
    ((index++))
done

sed -r "s|$line_regex|$selection|" $preview || end 1

end 0

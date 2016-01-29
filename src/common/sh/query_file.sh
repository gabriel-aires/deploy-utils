#!/bin/bash
# TODO: utilizar awk para as substituições em arquivo, pois o sed pode armazenar no máximo nove referências (\1 até \9)

source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1

function end() {
    if [ -d "$tmp_dir" ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    wait
    exit $1
}

trap "break 10 2> /dev/null; end 1" SIGQUIT SIGINT SIGHUP

end_flag=0
pid="$$"
tmp_dir="$work_dir/$pid"
file=''
delim=''
output_delim='\t'
columns=()
max_column=0
s_index=0
filter=()
filter_type=()
filter_value=()
filter_cmd=()
filter_regex=()
max_filter=0
f_index=0
order=()
max_order=0
o_index=0
top=''
head_cmd="head -n"
top_cmd='cat'
grep_cmd="grep -E -x"
sort_cmd="sort"
order_cmd='cat'
size=1
line_regex=''
output_regex=''
preview=''
order_by=''
selection=''

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
            while echo "$2" | grep -Ex "[1-9]" > /dev/null; do
                columns[$s_index]="$2"
                test ${columns[$s_index]} -gt $max_column && max_column=${columns[$s_index]}
                ((s_index++))
                shift
            done
            shift
            ;;

        "-t"|"--top")
            if echo "$2" | grep -Ex "[1-9][0-9]*" > /dev/null; then
                top="$2"
                top_cmd="$head_cmd $top"
                shift
            fi
            shift
            ;;

        "-f"|"--from")
            file="$2"
            shift 2
            ;;

        "-w"|"--where")
            while echo "$2" | grep -Ex "[1-9](==|=~|=%|!=).*" > /dev/null; do
                filter[$f_index]="$(echo "$2" | sed -r 's|^([0-9]+).*$|\1|')"
                filter_type[$f_index]="$(echo "$2" | sed -r 's/^[0-9]+(==|=~|=%|!=).*$/\1/')"
                filter_value[$f_index]="$(echo "$2" | sed -r 's/^[0-9]+(==|=~|=%|!=)(.*)$/\2/')"
                test ${filter[$f_index]} -gt $max_filter && max_filter=${filter[$f_index]}
                ((f_index++))
                shift
            done
            shift
            ;;

        "-o"|"--order-by")
            while echo "$2" | grep -Ex "[1-9]|asc|desc" > /dev/null; do
                order_cmd="$sort_cmd"
                if [ "$2" == "asc" ]; then
                    shift; break
                elif [ "$2" == "desc" ]; then
                    order_cmd="$sort_cmd -r"
                    shift; break
                else
                    order[$o_index]="$2"
                    test ${order[$o_index]} -gt $max_order && max_order=${order[$o_index]}
                    ((o_index++))
                    shift
                fi
            done
            shift
            ;;

        "-h"|"--help")
            echo "Utilização: query_file [nomearquivo] [opções]"
            echo "Opções:"
            echo "-d|--delim: especificar caractere ou string que delimita os campos do arquivo. Ex: ';' (obrigatório)"
            echo "-r|--replace-delim: especificar caractere ou string que delimitará os campos exibidos. Ex: '|' (opcional)"
            echo "-s|--select: especificar ordem das colunas a serem selecionadas. Ex: '1' '2', etc (obrigatório)"
            echo "-t|--top: especificar quantidade de linhas a serem retornadas. Ex: '10' '500', etc (opcional)"
            echo "-f|--from: especificar arquivo. Ex: dados.csv (obrigatório)"
            echo "-w|--where: especificar filtro. Ex: '1==valor_exato' '2=~regex_valor' '3!=diferente_valor' '4=%contem_valor', etc (opcional)"
            echo "-o|--order-by: especificar ordenação dos resultados. Ex: '1' '2' 'asc', '4' ' 5' 'desc', etc (opcional)"
            end_flag=1
            break
            ;;

        '')
            break
            ;;

        *)
            echo "'$1':Argumento inválido." 1>&2
            end_flag=1
            break
            ;;

    esac
done

if [ $end_flag -eq 1 ]; then
    end 1
elif [ $(($s_index+$o_index)) -gt 9 ]; then
    echo "Erro. Devido a uma limitação do comando sed, a quantidade total de campos indicados para seleção/ordenação não deve exceder 9." 1>&2; end 1    
elif [ ! -f "$file" ] || [ -z "$delim" ] || [ -z "${columns[0]}" ]; then
    echo "Erro. Argumentos insuficientes." 1>&2; end 1
elif ! echo "$delim" | grep -Ex "[[:print:]]+" > /dev/null; then
    echo "Delimitador inválido." 1>&2; end 1
fi

mkdir -p $tmp_dir

header="$(head -n 1 $file )"
part_regex="(.*)$delim"
part_output_regex="(.*)$output_delim"

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
((size--))

test $max_column -gt $size && end_flag=1
test $max_filter -gt $size && end_flag=1
test $max_order -gt $size && end_flag=1

if [ $end_flag -eq 1 ]; then
    echo "Erro. O arquivo $file possui apenas $size campos. Favor indicar colunas entre 1 e $size." 1>&2; end 1
fi

preview=$file

# Filtro
index=0
cp $preview $tmp_dir/preview_filter_$index
while [ $index -lt $f_index ]; do
    ${filter_cmd[$index]} "${filter_regex[$index]}" "$tmp_dir/preview_filter_$index" > "$tmp_dir/preview_filter_$(($index+1))" || end_flag=1
    ((index++))
done
preview="$tmp_dir/preview_filter_$index"

test $end_flag -eq 1 && end 1

# Ordenação
index=0
while [ $index -lt $o_index ]; do
    order_by="$order_by\\${order[$index]}$output_delim"
    output_regex="$output_regex$part_output_regex"
    ((index++))
done

#Seleção
output_size=$index
index=0
while [ $index -lt $s_index ]; do
    ((output_size++))
    selection="$selection\\${columns[$index]}$output_delim"
    output_selection="$output_selection\\$output_size$output_delim"
    output_regex="$output_regex$part_output_regex"
    ((index++))
done

# Seleciona colunas de ordenação auxiliares + seleção do usuário, ordena, remove colunas de ordenação auxiliares, exibe n primeiras linhas
sed -r "s|$line_regex|${order_by}$selection|" $preview | $order_cmd | sed -r "s|$output_regex|$output_selection|" | $top_cmd || end 1

end 0

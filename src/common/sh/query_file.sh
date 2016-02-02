#!/bin/bash

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
uniq_cmd='uniq'
distinct_cmd='cat'
grep_cmd="grep -E -x"
sort_cmd="sort"
order_cmd='cat'
file_size=0
header_size=0
size=1
col_name_regex='[a-zA-Z0-9 \-\_]+'
arg_name_regex="\[$col_name_regex\]"
arg_num_regex='[1-9][0-9]*'
line_regex=''
line_output_regex=''
output_regex=''
preview=''
last_preview=''
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

        "-x"|"--header")
            if echo "$2" | grep -Ex "$arg_num_regex" > /dev/null; then
                header_size="$2"
                shift
            fi
            shift
            ;;

        "-s"|"--select")
            while echo "$2" | grep -Ex "$arg_num_regex|$arg_name_regex|\*" > /dev/null; do
                test "$2" == '*' && columns[$s_index]="&" || columns[$s_index]="$2"
                ((s_index++))
                shift
            done
            shift
            ;;

        "-u"|"--unique"|"--distinct")
            distinct_cmd="$uniq_cmd"
            shift
            ;;

        "-t"|"--top")
            if echo "$2" | grep -Ex "$arg_num_regex" > /dev/null; then
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
            while echo "$2" | grep -Ex "($arg_num_regex|$arg_name_regex)(==|=~|=%|!=).*" > /dev/null; do
                filter[$f_index]="$(echo "$2" | sed -r "s|^($arg_num_regex|$arg_name_regex).*$|\1|")"
                filter_type[$f_index]="$(echo "$2" | sed -r "s/^($arg_num_regex|$arg_name_regex)(==|=~|=%|!=).*$/\2/")"
                filter_value[$f_index]="$(echo "$2" | sed -r "s/^($arg_num_regex|$arg_name_regex)(==|=~|=%|!=)(.*)$/\3/")"
                ((f_index++))
                shift
            done
            shift
            ;;

        "-o"|"--order-by")
            while echo "$2" | grep -Ex "$arg_num_regex|$arg_name_regex|asc|desc" > /dev/null; do
                order_cmd="$sort_cmd"
                if [ "$2" == "asc" ]; then
                    shift; break
                elif [ "$2" == "desc" ]; then
                    order_cmd="$sort_cmd -r"
                    shift; break
                else
                    order[$o_index]="$2"
                    ((o_index++))
                    shift
                fi
            done
            shift
            ;;

        "-h"|"--help")
            echo "Utilização: query_file.sh [opções]"
            echo "Opções:"
            echo ""
            echo "-d|--delim: especificar caractere ou string que delimita os campos do arquivo. Ex: ';' (obrigatório)"
            echo "-r|--replace-delim: especificar caractere ou string que delimitará os campos exibidos. Ex: '/' (opcional)"
            echo "-x|--header: especificar a linha que contém o cabeçalho do arquivo. Ex: '1' (opcional)"
            echo "-s|--select: especificar ordem das colunas a serem selecionadas. Ex: '[nome_coluna1]' '2' '*', etc (obrigatório)"
            echo "-u|--unique|--distinct: (sem argumentos). Suprime linhas duplicadas da saída padrão (opcional)"
            echo "-t|--top: especificar quantidade de linhas a serem retornadas. Ex: '10' '500', etc (opcional)"
            echo "-f|--from: especificar arquivo. Ex: dados.csv (obrigatório)"
            echo "-w|--where: especificar filtro. Ex: '1==valor_exato' '[nome_coluna2]=~regex_valor' '3!=diferente_valor' '[nome_coluna4]=%contem_valor', etc (opcional)"
            echo "-o|--order-by: especificar ordenação dos resultados. Ex: '1' '2' '[nome_coluna3]' 'asc', '4' ' 5' 'desc', etc (opcional)"
            echo ""
            echo "OBS: Nas opções select, order-by e where, as colunas podem ser especificadas por número (1 2, etc) ou nome ([coluna1] [coluna2], etc)."
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
elif [ ! -f "$file" ] || [ -z "$delim" ] || [ -z "${columns[0]}" ]; then
    echo "Erro. Argumentos insuficientes." 1>&2; end 1
elif [ "$distinct_cmd" == "$uniq_cmd" ] && [ "$order_cmd" == 'cat' ]; then
    echo "Erro. A opção '-u|--unique|--distinct' deve ser utilizada em conjunto com a opção '-o|--order-by'." 1>&2; end 1
elif ! echo "$delim" | grep -Ex "[[:print:]]+" > /dev/null; then
    echo "Delimitador inválido." 1>&2; end 1
fi

mkdir -p $tmp_dir
file_size=$(cat $file | wc -l)
preview=$tmp_dir/raw_data

tail -n $(($header_size-$file_size)) $file > $preview
header="$(head -n $header_size $file | tail -n 1)"
part_regex="(.*)$delim"
part_output_regex=".*$delim"

while $(echo "$header" | grep -E "^(.*$delim){$size}" > /dev/null); do
    line_regex="$line_regex$part_regex"
    line_output_regex="$line_output_regex$part_output_regex"
    ((size++))
done
((size--))

# associar nomes de coluna ao número correspondente
for position in $(seq 1 $size); do

    for index in $(seq 0 $(($s_index-1))) ; do
        if echo ${$columns[$index]} | grep -Ex "$arg_name_regex" &> /dev/null
            test "$(echo ${$columns[$index]} | sed -r "s|\[($col_name_regex)\]|\1|")" == "$(echo $header | perl -pe "s|$line_regex|\$$position|")" && columns[$index]=$position
        fi
    done

    for index in $(seq 0 $(($f_index-1))) ; do
        if echo ${$filter[$index]} | grep -Ex "$arg_name_regex" &> /dev/null
            test "$(echo ${$filter[$index]} | sed -r "s|\[($col_name_regex)\]|\1|")" == "$(echo $header | perl -pe "s|$line_regex|\$$position|")" && filter[$index]=$position
        fi
    done

    for index in $(seq 0 $(($o_index-1))) ; do
        if echo ${$order[$index]} | grep -Ex "$arg_name_regex" &> /dev/null
            test "$(echo ${$order[$index]} | sed -r "s|\[($col_name_regex)\]|\1|")" == "$(echo $header | perl -pe "s|$line_regex|\$$position|")" && order[$index]=$position
        fi
    done

done

# Verificar se todos os argumentos encontram-se dentro do range do arquivo.
for index in $(seq 0 $(($s_index-1))) ; do
    if echo ${columns[$index]} | grep -Ex "$arg_num_regex" &> /dev/null; then
        test ${columns[$index]} -gt $max_column && max_column=${columns[$s_index]}
    elif echo ${columns[$index]} | grep -Ex "$arg_name_regex" &> /dev/null; then
        echo "Coluna de seleção inválida. O campo ${$columns[$index]} não foi encontrado no cabeçalho."
        end_flag=1
    fi
done

for index in $(seq 0 $(($f_index-1))) ; do
    if echo ${filter[$index]} | grep -Ex "$arg_num_regex" &> /dev/null; then
        test ${filter[$index]} -gt $max_filter && max_filter=${filter[$f_index]}
    else
        echo "Coluna de filtro inválida. O campo ${$filter[$index]} não foi encontrado no cabeçalho."
        end_flag=1
    fi
done

for index in $(seq 0 $(($o_index-1))) ; do
    if echo ${order[$index]} | grep -Ex "$arg_num_regex" &> /dev/null; then
        test ${order[$index]} -gt $max_order && max_order=${order[$o_index]}
    else
        echo "Coluna de ordenação inválida. O campo ${$order[$index]} não foi encontrado no cabeçalho."
        end_flag=1
    fi
done

test $end_flag -eq 1 && end 1
test $max_column -gt $size && end_flag=1
test $max_filter -gt $size && end_flag=1
test $max_order -gt $size && end_flag=1

if [ $end_flag -eq 1 ]; then
    echo "Erro. O arquivo $file possui apenas $size campos. Favor indicar colunas entre 1 e $size." 1>&2; end 1
fi

# construir filtros
for position in $(seq 1 $size); do
    for index in $(seq 0 $(($f_index-1))) ; do

        if [ $position -eq ${filter[$index]} ]; then

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

    done
done

# Filtro
last_preview=$preview
preview=$tmp_dir/preview_filter_0
mv $last_preview $preview

for index in $(seq 0 $(($f_index-1))) ; do
    last_preview=$preview
    preview="$tmp_dir/preview_filter_$(($index+1))"
    ${filter_cmd[$index]} "${filter_regex[$index]}" $last_preview > $preview && rm -f $last_preview || end_flag=1
done

test $end_flag -eq 1 && end 1

# Ordenação
for index in $(seq 0 $(($o_index-1))) ; do
    order_by="$order_by\$${order[$index]}$delim"
    output_regex="$output_regex$part_output_regex"
done

#Seleção
output_regex="$output_regex("
for index in $(seq 0 $(($s_index-1))) ; do
    if [ ${columns[$index]} == '&' ]; then
        selection="$selection\$${columns[$index]}"
        output_regex="$output_regex$line_output_regex"
    else
        selection="$selection\$${columns[$index]}$delim"
        output_regex="$output_regex$part_output_regex"
    fi
done
output_regex="$output_regex)"

# Retorna colunas de (ordenação auxiliares + ) seleção do usuário, (ordena), (remove colunas de ordenação auxiliares), (remove linhas duplicadas), (exibe n primeiras linhas), substitui delimitador
perl -pe "s|$line_regex|${order_by}$selection|" $preview | $order_cmd | sed -r "s|$output_regex|\1|" | $distinct_cmd | $top_cmd | sed -r "s|$delim|$output_delim|g" && end 0 || end 1

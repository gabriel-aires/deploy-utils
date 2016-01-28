#!/bin/bash
# Este arquivo deve ser carregado no cabeçalho de cada script através do comando "source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1"

# Define/Carrega variáveis comuns.

install_dir="$(dirname $(dirname $(readlink -f $0)))"
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/conf/include.conf || exit 1

# Define funções comuns.

function paint () {

    if $interactive; then
        local color

        case $2 in
            black) color=0;;
            red) color=1;;
            green) color=2;;
            yellow) color=3;;
            blue) color=4;;
            magenta) color=5;;
            cyan) color=6;;
            white) color=7;;
        esac

        case $1 in
            fg) tput setaf $color;;
            bg) tput setab $color;;
            default) tput sgr0;;
        esac
    fi

    return 0

}

function lock () {                                            #argumentos: nome_trava, mensagem_erro, (instrução)

    if [ -d $lock_dir ] && [ ! -z "$1" ] && [ ! -z "$2" ]; then

        local lockfile="$(echo "$1" | sed -r "s|[;, \:\.]+|_|g")"
        local msg="$2"

        if [ -f "$lock_dir/$lockfile" ]; then
            case $execution_mode in
                'agent') log "INFO" "$msg";;
                'server') echo -e "\n$msg";;
            esac

            end 0 2> /dev/null || exit 0
        else
            lock_array[$lock_index]="$lock_dir/$lockfile" && ((lock_index++))
            touch "$lock_dir/$lockfile"
        fi
    else
        end 1 2> /dev/null || exit 1
    fi

    return 0

}

function clean_locks () {

    if [ -d $lock_dir ]; then
        local i=0
        while [ $i -le $lock_index ]; do
            test -f "${lock_array[$i]}" && rm -f "${lock_array[$i]}"
            ((i++))
        done
    fi

    if $lock_history; then
        case $execution_mode in
            'agent') rm -f ${remote_lock_dir}/$history_lock_file;;
            'server') rm -f ${lock_dir}/$history_lock_file;;
        esac
    fi

}

function mklist () {

    if [ ! -z "$1" ] && [ ! -z "$2" ]; then
        local lista=$(echo "$1" | sed -r 's/,/ /g' | sed -r 's/;/ /g' | sed -r 's/ +/ /g' | sed -r 's/ $//g' | sed -r 's/^ //g' | sed -r 's/ /\n/g')
        echo "$lista" > $2
    else
        end 1 2> /dev/null || exit 1
    fi

}

function chk_template () {

    if [ -f "$1" ] && [ "$#" -le 3 ]; then

        local arquivo="$1"
        local nome_template="$2"        # parâmetro opcional, especifica um template para validação do arquivo.
        local flag="$3"                    # indica se o script deve ser encerrado ou não ao encontrar inconsistências. Para prosseguir, deve ser passado o valor "continue"

        paint 'fg' 'yellow'

        if [ -z "$nome_template" ] && [ -f "$install_dir/template/$(basename $arquivo | cut -f1 -d '.').template" ]; then
            nome_template="$(basename $arquivo | cut -f1 -d '.')"
        fi

        if [ -z $nome_template ]; then
            case $execution_mode in
                'agent') log "ERRO" "Não foi indentificado um template para validação do arquivo $arquivo.";;
                'server') echo -e "\nErro. Não foi indentificado um template para validação do arquivo $arquivo.";;
            esac
            paint 'default'
            end 1 2> /dev/null || exit 1

        elif [ ! -f "$install_dir/template/$nome_template.template" ]; then
            case $execution_mode in
                'agent') log "ERRO" "O template espeficicado não foi encontrado: $nome_template.";;
                'server') echo -e "\nErro. O template espeficicado não foi encontrado.";;
            esac
            paint 'default'
            end 1 2> /dev/null || exit 1

        elif [ "$(cat $arquivo | grep -Ev "^$|^#" | sed -r 's|(=).*$|\1|' | grep -vx --file=$install_dir/template/$nome_template.template | wc -l)" -ne "0" ]; then
            case $execution_mode in
                'agent') log "ERRO" "Há parâmetros incorretos no arquivo $arquivo:";;
                'server') echo -e "\nErro. Há parâmetros incorretos no arquivo $arquivo:";;
            esac
            cat $arquivo | grep -Ev "^$|^#" | sed -r 's|(=).*$|\1|' | grep -vx --file=$install_dir/template/$nome_template.template

            paint 'default'
            if [ "$flag" == "continue" ]; then
                return 1
            else
                end 1 2> /dev/null || exit 1
            fi
        fi

        paint 'default'

    else
        end 1 2> /dev/null || exit 1
    fi

    return 0

}

function valid () {

    #argumentos: nome_variável (nome_regra) (nome_regra_inversa) mensagem_erro ("continue").
    #O comportamento padrão é a finalização do script quando a validação falha.
    #Esse comportamento pode ser alterado se a palavra "continue" for adicionada como último argumento,
    #nesse caso a função simplesmente retornará 1 caso a validação falhe.

    if [ ! -z "$1" ] && [ ! -z "${!#}" ]; then

        #argumentos
        local nome_var="$1"            # obrigatório
        local nome_regra            # opcional, se informado, é o segundo argumento.
        local nome_regra_inversa    # opcional, se informado, é o terceiro argumento.
        local msg                    # mensagem de erro: obrigatório.

        #variaveis internas
        local exit_cmd="end 1 2> /dev/null || exit 1"
        local flag_count=0
        local valor
        local regra
        local regra_inversa

        if [ "${!#}" == "continue" ]; then
            ((flag_count++))
            exit_cmd="return 1"
            msg=$(eval "echo \$$(($#-1))")
        else
            msg="${!#}"
        fi

        if [ "$#" -gt "$((2 + $flag_count))" ] && [ ! -z "$2" ]; then
            nome_regra="$2"

            if [ $(echo "$nome_regra" | grep -Ex "^regex_[a-z_]+$" | wc -l) -ne 1 ]; then
                echo "Erro. O argumento especificado não é uma regra de validação."
                eval "$exit_cmd"
            fi

            if [ "$#" -gt "$((3 + $flag_count))" ] && [ ! -z "$3" ]; then
                nome_regra_inversa="$3"

                if [ $(echo "${nome_regra_inversa}" | grep -Ex "^not_regex_[a-z_]+$" | wc -l) -ne 1 ]; then
                    echo "Erro. O argumento especificado não é uma regra de validação inversa."
                    eval "$exit_cmd"
                fi
            fi
        fi

        if [ -z "$nome_regra" ]; then
            regra="echo \$regex_${nome_var}"
        else
            regra="echo \$$nome_regra"
        fi

        if [ -z "${nome_regra_inversa}" ]; then
            regra_inversa="echo \$not_regex_${nome_var}"
        else
            regra_inversa="echo \$${nome_regra_inversa}"
        fi

        regra="$(eval $regra)"
        regra_inversa="$(eval ${regra_inversa})"

        valor="echo \$${nome_var}"
        valor="$(eval $valor)"

        if [ -z "$regra" ]; then
            case "$execution_mode" in
                'agent') log "ERRO" "Não há uma regra para validação da variável $nome_var";;
                'server') echo "Erro. Não há uma regra para validação da variável $nome_var";;
            esac
            eval "$exit_cmd"

        elif "$interactive"; then    #o modo interativo somente é possível caso $execution_mode='server'
            edit_var=0
            while [ $(echo "$valor" | grep -Ex "$regra" | grep -Exv "${regra_inversa}" | wc -l) -eq 0 ]; do
                paint 'fg' 'yellow'
                echo -e "$msg"
                paint 'default'
                read -p "$nome_var: " -e -r $nome_var
                edit_var=1
                valor="echo \$${nome_var}"
                valor="$(eval $valor)"
            done

        elif [ $(echo "$valor" | grep -Ex "$regra" | grep -Exv "${regra_inversa}" | wc -l) -eq 0 ]; then
            case "$execution_mode" in
                'agent') log "ERRO" "$msg";;
                'server') echo -e "$msg";;
            esac
            eval "$exit_cmd"

        fi

    else
        eval "$exit_cmd"
    fi

    return 0        # o script continua somente se a variável tiver sido validada corretamente.

}

function write_history () {

    local date_log=$(echo "$(date +%F)" | sed -r "s|^(....)-(..)-(..)$|\3/\2/\1|")
    local time_log=$(echo "$(date +%Hh%Mm%Ss)")
    local app_log="$(echo "$app" | tr '[:upper:]' '[:lower:]')"
    local rev_log="$(echo "$rev" | sed -r 's|;|_|g')"
    local ambiente_log="$(echo "$ambiente" | tr '[:upper:]' '[:lower:]')"
    local host_log="$(echo "$host" | cut -f1 -d '.' | tr '[:upper:]' '[:lower:]')"
    local obs_log="$1"
    local flag_log="$2"

    local aux="$interactive"; interactive=false
    valid "regex_csv_value" "obs_log" "'$obs_log': mensagem inválida." "continue" || return 1
    valid "regex_flag" "flag_log" "'$flag_log': flag de deploy inválida." "continue" || return 1
    interactive=$aux

    local msg_log="$date_log;$time_log;$app_log;$rev_log;$ambiente_log;$host_log;$obs_log;$flag_log;"

    local lock_path
    local history_path
    local app_history_path

    case $execution_mode in
        "agent")
            lock_path=${remote_lock_dir}
            history_path=${remote_history_dir}
            app_history_path=${remote_app_history_dir}
            ;;
        "server")
            lock_path=$lock_dir
            history_path=$history_dir
            app_history_path=${app_history_dir}
            ;;
    esac

    ##### ABRE O ARQUIVO DE LOG PARA EDIÇÃO ######

    while [ -f "${lock_path}/$history_lock_file" ]; do                        #nesse caso, o processo de deploy não é interrompido. O script é liberado para escrever no log após a remoção do arquivo de trava.
        sleep 1
    done

    lock_history=true
    touch "${lock_path}/$history_lock_file"

    touch ${history_path}/$history_csv_file
    touch ${app_history_path}/$history_csv_file

    echo -e "$msg_log" >> ${history_path}/$history_csv_file
    echo -e "$msg_log" >> ${app_history_path}/$history_csv_file

    rm -f ${lock_path}/$history_lock_file                                #remove a trava sobre o arquivo de log tão logo seja possível.
    lock_history=false

    return 0

}

function set_app_history_dirs () {

    deploy_id=$(echo $(date +%F_%Hh%Mm%Ss)_${rev}_${ambiente} | sed -r "s|[/;]|_|g" | tr '[:upper:]' '[:lower:]')

    case $execution_mode in
        'server')
            app_history_dir="${app_history_dir_tree}/${app}"
            deploy_log_dir="${app_history_dir}/${deploy_id}"
            ;;
        'agent')
            remote_app_history_dir="${remote_app_history_dir_tree}/${app}"
            deploy_log_dir="${remote_app_history_dir}/${deploy_id}"
            ;;
    esac

    mkdir -p $deploy_log_dir || return 1

    return 0

}

function query_file () {

    local file=''
    local delim=''
    local output_delim='\t'
    local columns=()
    local set_value=()
    local s_index=0
    local filter=()
    local filter_type=()
    local filter_value=()
    local f_index=0
    local grep_cmd="grep -E -x"
    local selection=''
    local where=''

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
                    columns[$s]="$2"
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
                    filter[$f]="$(echo "$2" | sed -r 's|^([0-9]+).*$|\1|')"
                    filter_type[$f]="$(echo "$2" | sed -r 's/^[0-9]+(==|=~|=%|!=).*$/\1/')"
                    filter_value[$f]="$(echo "$2" | sed -r 's/^[0-9]+(==|=~|=%|!=)(.*)$/\2/')"
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
                return 0
                ;;

            '')
                break
                ;;

            *)
                echo "'$1':Argumento inválido." 1>&2
                return 1
                ;;

        esac
    done

    if [ ! -f "$file" ] || [ -z "$delim" ] || [ -z "${columns[0]}" ]; then
        echo "Erro. Argumentos insuficientes." 1>&2; return 1
    elif ! echo "$delim" | grep -Ex "[[:print:]]+" > /dev/null; then
        echo "Delimitador inválido." 1>&2; return 1
    fi

    local header="$(head -n 1 $file )"
    local size=1
    local part_regex="(.*)$delim"
    local line_regex=''
    local filter_regex=()
    local filter_cmd=()
    local index

    while $(echo "$header" | grep -E "^(.*$delim){$size}" > /dev/null); do

        line_regex="$line_regex$part_regex"
        index=0

        while [ $index -lt $f_index ]; do

            if [ $size -eq $filter[$index] ]; then

                case $filter_type[$index] in
                    '==') # match exato
                        filter_value[$index]=$(echo "$filter_value[$index]" | sed -r "s|([\\\+\-\.\?\^\$])|\\\\\1|g")
                        filter_cmd[$index]="$grep_cmd"
                        ;;
                    '=%') # contains
                        filter_value[$index]=$(echo "$filter_value[$index]" | sed -r "s|([\\\+\-\.\?\^\$])|\\\\\1|g" | sed -r "s|^(.*)$|\.\*\1\.\*|")
                        filter_cmd[$index]="$grep_cmd"
                        ;;
                    '=~') # regex
                        filter_cmd[$index]="$grep_cmd"
                        ;;
                    '!=') # match inverso
                        filter_value[$index]=$(echo "$filter_value[$index]" | sed -r "s|([\\\+\-\.\?\^\$])|\\\\\1|g")
                        filter_cmd[$index]="$grep_cmd -v"
                        ;;
                esac

                filter_regex[$index]="$filter_regex[$index]$filter_value[$index]$delim"

            else

                filter_regex[$index]="$filter_regex[$index]$part_regex"

            fi

            ((index++))

        done

        ((size++))

    done

    index=0
    while [ $index -lt $f_index ]; do
        where="$where $filter_cmd[$index] $filter_regex[$index] |"
        ((index++))
    done

    index=0
    while [ $index -lt $s_index ]; do
        selection="$selection\\$columns[$index]$output_delim"
        ((index++))
    done

    cat $file | $where sed -r "s|$line_regex|$selection|" || return 1

    return 0

}

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

    local file="$1"
    local selection="$(echo "\\$2" | sed -r "s| |\\|g")"
    local delim="$(echo "$3" | sed -r "s|([\\\+\-\.\^\$])|\\\1|g")"
    local filter="$4"
    local value="$5"
    local output

    case $execution_mode in
        'server') output="echo";;
        'agent') output="log 'ERRO'"
    esac

    if [ ! -f "$file" ]; then
        $output "$1: Arquivo inexistente." && return 1
    elif [ $(grep -Ex "(\\[0-9]+ )+\\[0-9]+" "$selection") ]; then
        $output "$2: Seleção inválida." && return 1
    elif [ $(grep -Ex "[[:print]]+" "$delim") ]; then
        $output "$3: Delimitador inválido." && return 1
    elif [ "$filter" -ge 1 ]; then
        $output "$4: Filtro inválido." && return 1
    elif [ $(grep -Ex "[[:print:]]+" "$value" | grep -Ev "$delim") ]; then
        $output "$5: Valor inválido." && return 1
    fi

    local size=1
    local part_regex="(.*$delim)"
    local line_regex='^'
    local filter_regex='^'

    while $(grep -Eil "^(.*$delim){$size}" $file > /dev/null); do

        line_regex="$line_regex$part_regex"

        if [ $size -eq $filter ]; then
            filter_regex="$filter_regex$value$delim"
        else
            filter_regex="$filter_regex$part_regex"
        fi

        ((size++))

    done

    line_regex="$line_regex$"
    filter_regex="$filter_regex$"

    test "$filter_regex" != '^$' && grep -Ei "$filter_regex" $file | sed -r "s|$line_regex|$selection|" || return 1

    return 0

}

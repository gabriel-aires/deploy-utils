#!/bin/bash

# Define funções comuns.

function join_path () {
    echo "$@" | sed -r 's%[[:blank:]]%%g;s%/+%/%g;s%/$%%'
}

function option () {
    [ -n "$1" ] && return 0 || return 1
}

function chk_arg () {
    local forbidden_chars='[[:blank:];&`<>]'  #forbidden_user_input
    [[ ! "$1" =~ $forbidden_chars ]] && return 0 || return 1
}

function chk_num () {
    chk_arg "$1" && [ "$1" -gt 0 ] 2> /dev/null && return 0 || return 1
}

function chk_bool () {
    [[ "$1" =~ ^(true|false)$ ]] && return 0 || return 1
}

function chk_path () {
    chk_arg "$1" && [ -d "$1" ] && return 0 || return 1
}

function chk_pipe () {
    chk_arg "$1" && [ -p "$1" ] && return 0 || return 1
}

function chk_file () {
    chk_arg "$1" && [ -f "$1" ] && return 0 || return 1
}

function chk_read () {
    chk_arg "$1" && [ -r "$1" ] && return 0 || return 1
}

function chk_write () {
    chk_arg "$1" && [ -w "$1" ] && return 0 || return 1
}

function chk_exec () {
    chk_arg "$1" && [ -x "$1" ] && return 0 || return 1
}

function starts_with () {
    chk_arg "$2" && [[ "$1" =~ ^$2 ]] && return 0 || return 1
}

function ends_with () {
    chk_arg "$2" && [[ "$1" =~ $2$ ]] && return 0 || return 1
}

function contains () {
    chk_arg "$2" && [[ "$1" =~ $2 ]] && return 0 || return 1
}

function assert () {
    #test_message="$1", param="$2", value="$3"
    [ "$2" == "$3" ] && return 0 || return 1
}

function set_state () {
    [[ "$1" =~ ^(r|w|x)$ ]] && state="$1" && return 0 || return 1    
}

function try_catch () {
    #try
    last_command="$1"
    log "DEBUG" "Executando $last_command..."
    $1 2>&1 && return 0
    #catch
    obs="Falha ao executar: $last_command."
    $simulation || write_history "$obs" "0"
    log "ERRO" "$obs" && return 1
}

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

function log () {    ##### log de execução detalhado.

    local msg="$(date +"%F %Hh%Mm%Ss")  $1  $HOSTNAME  $(basename  $(readlink -f $0))  (${FUNCNAME[1]})"
    local len=$(echo "$msg" | wc -c)

    if [ $len -lt 90 ]; then
        local fill=$((90 - $len))
        local spaces="$(seq -s ' ' 0 $fill | sed -r "s|[0-9]||g")"
        echo -e "$msg$spaces\t$2"
    else
        echo -e "$msg    \t$2"
    fi

}

function compress () {         ##### padroniza a metodologia de compressão de arquivos (argumentos: pacote [arquivo1 arquivo2 arquivo3...])

    local error_msg='Impossível criar arquivo zip'
    local error_cmd='return 1'

    case $verbosity in
        'quiet') error_cmd="log 'ERRO' '$error_msg'; $error_cmd";;
        'verbose') error_cmd="echo -e '\n$error_msg'; $error_cmd";;
    esac

    if [ "$#" -ge 2 ]; then

        local success="false"
        local filename="$1"
        shift 1
        local filelist="$@"

        touch "$filename" || eval "$error_cmd"                                                              #verifica se o pacote pode ser escrito
        zip -rql9 --filesync "$filename" $filelist &> /dev/null && success="true"                           #tenta utilizar o parâmetro --filesync (disponível a partir da versão 3.0)
        ! $success && rm -f "$filename" && zip -rql1 "$filename" $filelist &> /dev/null && success="true"   #recria o pacote (caso exista) e usa taxa de compressão menor para reduzir tempo
        $success || eval "$error_cmd"

    else

        eval "$error_cmd"

    fi

}

function lock () {                                            #argumentos: nome_trava, mensagem_erro, (instrução)

    local exit_cmd="end 1 2> /dev/null || exit 1"

    if [ -d $lock_dir ] && [ -n "$1" ] && [ -n "$2" ]; then

        local lockfile="$(echo "$1" | sed -r "s|[;, \:\.]+|_|g")"
        local miliseconds=$(date +%s%3N)
        local timeout=$(($lock_timeout+$miliseconds))

        case $verbosity in
            'quiet') exit_cmd="log 'INFO' '$2'; $exit_cmd";;
            'verbose') exit_cmd="echo -e '\n$2'; $exit_cmd";;
        esac

        while [ -f "$lock_dir/$lockfile" ] && [ $miliseconds -le $timeout ]; do
            sleep 0.001
            miliseconds=$(date +%s%3N)
        done

        if [ ! -f "$lock_dir/$lockfile" ]; then
            touch "$lock_dir/$lockfile" && echo "$$" >> "$lock_dir/$lockfile"
            # se mais de um processo realizar append sobre o lockfile, prevalece o lock do que escreveu a primeira linha.
            if [ $(head -n 1 "$lock_dir/$lockfile") == "$$" ]; then
                lock_array[$lock_index]="$lock_dir/$lockfile" && ((lock_index++))
            else
                eval "$exit_cmd"
            fi

        else
            eval "$exit_cmd"
        fi

    else
        eval "$exit_cmd"
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

    if [ -n "$1" ]; then
        local lista=$(echo "$1" | sed -r 's/,/ /g' | sed -r 's/;/ /g' | sed -r 's/\|/ /g' | sed -r 's/ +/ /g' | sed -r 's/ $//g' | sed -r 's/^ //g' | sed -r 's/ /\n/g')
        test -n "$2" && echo "$lista" > $2 || echo -e "$lista"
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
            case $verbosity in
                'quiet') log "ERRO" "Não foi indentificado um template para validação do arquivo $arquivo.";;
                'verbose') echo -e "\nErro. Não foi indentificado um template para validação do arquivo $arquivo.";;
            esac
            paint 'default'
            end 1 2> /dev/null || exit 1

        elif [ ! -f "$install_dir/template/$nome_template.template" ]; then
            case $verbosity in
                'quiet') log "ERRO" "O template espeficicado não foi encontrado: $nome_template.";;
                'verbose') echo -e "\nErro. O template espeficicado não foi encontrado.";;
            esac
            paint 'default'
            end 1 2> /dev/null || exit 1

        elif [ "$(cat $arquivo | grep -Ev "^$|^#" | sed -r 's|(=).*$|\1|' | grep -vx --file=$install_dir/template/$nome_template.template | wc -l)" -ne "0" ]; then
            case $execution_mode in
                'quiet') log "ERRO" "Há parâmetros incorretos no arquivo $arquivo:";;
                'verbose') echo -e "\nErro. Há parâmetros incorretos no arquivo $arquivo:";;
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
        local retry="$interactive"

        test "$retry" == "true" || retry=false

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

        set -f
        regra="$(eval $regra)"
        regra_inversa="$(eval ${regra_inversa})"
        valor="echo \$${nome_var}"
        valor="$(eval $valor)"
        set +f

        if [ -z "$regra" ]; then
            case "$verbosity" in
                'quiet') log "ERRO" "Não há uma regra para validação da variável $nome_var";;
                'verbose') echo "Erro. Não há uma regra para validação da variável $nome_var";;
            esac
            eval "$exit_cmd"

        elif "$retry"; then

            while [ $(echo "$valor" | grep -Ex "$regra" | grep -Exv "${regra_inversa}" | wc -l) -eq 0 ]; do
                paint 'fg' 'yellow'
                echo -e "$msg"
                paint 'default'
                read -p "$nome_var: " -e -r $nome_var
                valor="echo \$${nome_var}"
                valor="$(eval $valor)"
            done

        elif [ $(echo "$valor" | grep -Ex "$regra" | grep -Exv "${regra_inversa}" | wc -l) -eq 0 ]; then
            case "$verbosity" in
                'quiet') log "ERRO" "$msg";;
                'verbose') echo -e "$msg";;
            esac
            eval "$exit_cmd"

        fi

    else
        eval "$exit_cmd"
    fi

    return 0        # o script continua somente se a variável tiver sido validada corretamente.

}

function write_history () {

    local day_log=$(echo "$(date +%d)")
    local month_log=$(echo "$(date +%m)")
    local year_log=$(echo "$(date +%Y)")
    local time_log=$(echo "$(date +%Hh%Mm%Ss)")
    local user_log="$(echo "$user_name" | tr '[:upper:]' '[:lower:]')"
    local app_log="$(echo "$app" | tr '[:upper:]' '[:lower:]')"
    local rev_log="$(echo "$rev" | sed -r "s|$delim|_|g")"
    local ambiente_log="$(echo "$ambiente" | tr '[:upper:]' '[:lower:]')"
    local host_log="$(echo "$host" | grep -Eiv '[a-z]' || echo "$host" | cut -f1 -d '.' | tr '[:upper:]' '[:lower:]')"
    local obs_log="<a href=\"$web_context_path/deploy_logs.cgi?app=$app&env=$ambiente&deploy_id=$deploy_id\">$1</a>"
    local flag_log="$2"

    local aux="$interactive"; interactive=false
    valid "obs_log" "regex_csv_value" "'$obs_log': mensagem inválida." "continue" || return 1
    valid "flag_log" "regex_flag" "'$flag_log': flag de deploy inválida." "continue" || return 1
    interactive=$aux

    local header="$(echo "$col_day$col_month$col_year$col_time$col_user$col_app$col_rev$col_env$col_host$col_obs$col_flag" | sed -r 's/\[//g' | sed -r "s/\]/$delim/g")"
    local msg_log="$day_log$delim$month_log$delim$year_log$delim$time_log$delim$user_log$delim$app_log$delim$rev_log$delim$ambiente_log$delim$host_log$delim$obs_log$delim$flag_log$delim"

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
        sleep 0.001
    done

    lock_history=true
    touch "${lock_path}/$history_lock_file"

    test -f ${history_path}/$history_csv_file && touch ${history_path}/$history_csv_file || echo -e "$header" > ${history_path}/$history_csv_file

    echo -e "$msg_log" >> ${history_path}/$history_csv_file

    rm -f ${lock_path}/$history_lock_file                                #remove a trava sobre o arquivo de log tão logo seja possível.
    lock_history=false

    return 0

}

function set_app_history_dirs () {

    deploy_id=$(echo "date-$(date +%F-%Hh%Mm%Ss)-rev-${rev}" | sed -r "s|[^a-zA-Z0-9\._-]|_|g" | tr '[:upper:]' '[:lower:]')

    case $execution_mode in
        'server')
            app_history_dir="${app_history_dir_tree}/${ambiente}/${app}"
            deploy_log_dir="${app_history_dir}/${deploy_id}"
            ;;
        'agent')
            remote_app_history_dir="${remote_app_history_dir_tree}/${ambiente}/${app}"
            deploy_log_dir="${remote_app_history_dir}/${deploy_id}"
            ;;
    esac

    mkdir -p $deploy_log_dir || return 1

    return 0

}

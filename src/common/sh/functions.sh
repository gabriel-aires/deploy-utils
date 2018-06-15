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

    case "$1" in
	INFO) paint fg blue; paint bg white;;
	ERRO) paint fg white; paint bg red;;
	WARN) paint fg black; paint bg yellow;;
    esac

    local msg="$(date +"%F %Hh%Mm%Ss")  $1  $HOSTNAME  $(basename  $(readlink -f $0))  (${FUNCNAME[1]})"
    local len=$(echo "$msg" | wc -c)

    if [ $len -lt 90 ]; then
        local fill=$((90 - $len))
        local spaces="$(seq -s ' ' 0 $fill | sed -r "s|[0-9]||g")"
        echo -e "$msg$spaces\t$2"
    else
        echo -e "$msg    \t$2"
    fi

    paint default
}

function message () {

    local type="$1"
    local msg="$2"

    case $message_format in
        'detailed') log "$type" "$msg";;
        'simple') echo -e "\n$msg";;
    esac
}

function compress () {         ##### padroniza a metodologia de compressão de arquivos (argumentos: pacote [arquivo1 arquivo2 arquivo3...])

    local error_msg='Impossível criar arquivo zip'

    if [ "$#" -ge 2 ]; then

        local success="false"
        local filename="$1"
        shift 1
        local filelist="$@"

        touch "$filename" || { message "ERRO" "$error_msg" ; return 1 ; }                                                            #verifica se o pacote pode ser escrito
        zip -rql9 --filesync "$filename" $filelist &> /dev/null && success="true"                           #tenta utilizar o parâmetro --filesync (disponível a partir da versão 3.0)
        ! $success && rm -f "$filename" && zip -rql1 "$filename" $filelist &> /dev/null && success="true"   #recria o pacote (caso exista) e usa taxa de compressão menor para reduzir tempo
        $success || { message "ERRO" "$error_msg" ; return 1 ; }

    else
        message "ERRO" "$error_msg" ; return 1
    fi

    return 0
}

function lock () {                                            #argumentos: nome_trava, mensagem_erro, (instrução)

    if [ -d $lock_dir ] && [ -n "$1" ] && [ -n "$2" ]; then

        local lockfile="$(echo "$1" | sed -r "s|[;, \:\.]+|_|g")"
        local miliseconds=$(date +%s%3N)
        local timeout=$(($lock_timeout+$miliseconds))
        local msg="$2"

        while [ -f "$lock_dir/$lockfile" ] && [ $miliseconds -le $timeout ]; do
            sleep 0.05
            miliseconds=$(date +%s%3N)
        done

        if [ ! -f "$lock_dir/$lockfile" ]; then
            touch "$lock_dir/$lockfile" && echo "$$" >> "$lock_dir/$lockfile"
            # se mais de um processo realizar append sobre o lockfile, prevalece o lock do que escreveu a primeira linha.
            if [ $(head -n 1 "$lock_dir/$lockfile") == "$$" ]; then
                lock_array[$lock_index]="$lock_dir/$lockfile" && ((lock_index++))
            else
                message 'INFO' "$msg" ; return 1
            fi

        else
            message 'INFO' "$msg" ; return 1
        fi

    else
        return 1
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

    test -n "$1" || return 1
    echo "$1" | sed -r 's/,/ /g;s/;/ /g;s/\|/ /g;s/ +/ /g;s/ $//g;s/^ //g;s/ /\n/g' || return 1
    return 0

}

function build_template () { # argumentos: caminho_arquivo nome_template

    test -n "$1" || return 1

    local template_name="$1"
    local template_file="$install_dir/template/$template_name.template"
    local line=''
    local key=''
    local keygroup=''

    if [ ! -f "$template_file" ]; then
        message "ERRO" "O template especificado não foi encontrado: $template_name."
        return 1

    else

        while read line; do

            keygroup="$(echo "$line" | sed -rn "s/^.+\[@(.+)\]=$/\1/p")"

            if [ -n "$keygroup" ]; then
                mklist "${regex[$keygroup]}" | while read key; do
                    echo "$line" | sed -r "s/\[@.+\]=$/\[$key\]=/"
                done
            else
                echo "$line"
            fi

        done < "$template_file"
                                                            
    fi

    return 0

}

function chk_template () { # argumentos: caminho_arquivo nome_template

    test -f "$1" || return 1
    test -n "$2" || return 1

    local file="$1"
    local template_name="$2"
    local template_file="$install_dir/template/$template_name.template"
    local inconsistency=''

    if [ ! -f "$template_file" ]; then
        message "ERRO" "O template especificado não foi encontrado: $template_name."
        return 1

    else
        inconsistency="$(sed -r 's/=.*$/=/;/^$|^#/d' $file | grep -Evx --file <( sed -r "s/\[.*\]=$/\\\[${regex[key]}\\\]=/;s/^\.\.\.$/${regex[var]}=/" "$template_file"))"
        if [ -n "$inconsistency" ]; then
            message "ERRO" "Há parâmetros incorretos no arquivo $file:"
            echo -e "$inconsistency"
            return 1
        fi
                                                            
    fi

    return 0
}

function valid () {    #argumentos obrigatórios: valor id_regra mensagem_erro ; retorna 0 para string válida e 1 para inválida ou argumentos incorretos

    test "$#" -eq "3" || return 1
    
    local value="$1"     
    local rule_id="$2"
    local error_msg="$3"

    local valid_regex="${regex[$rule_id]}"
    local forbidden_regex="${not_regex[$rule_id]}"
    local alt_valid_regex='.*'
    local alt_forbidden_regex='.*[;&`<>].*'
    local compound_rule="$([[ $rule_id =~ : ]] && echo true || echo false)"
    local rule_name="$rule_id"
    local missing_rule_msg="Não há uma regra correspondente à chave '$rule_name'"
    
    if $compound_rule; then
        rule_name="${rule_id//:*}"
        valid_regex="${regex[$rule_name]}"
        forbidden_regex="${not_regex[$rule_name]}"
        alt_valid_regex="${regex[$rule_id]:-$alt_valid_regex}"
        alt_forbidden_regex="${not_regex[$rule_id]:-$alt_forbidden_regex}"
    fi

    if [ -z "$valid_regex" ]; then
        message "ERRO" "$missing_rule_msg"
        return 1
    elif [[ $value =~ ^$valid_regex$ ]] && [[ $value =~ ^$alt_valid_regex$ ]] && [[ ! $value =~ ^$forbidden_regex$ ]] && [[ ! $value =~ ^$alt_forbidden_regex$ ]]; then
        return 0
    else
        message "ERRO" "$error_msg"
        return 1
    fi

}

function write_history () {

    valid "$1" "csv_value" "'$1': mensagem inválida." || return 1
    valid "$2" "flag" "'$2': flag de deploy inválida." || return 1

    local day_log=$(echo "$(date +%d)")
    local month_log=$(echo "$(date +%m)")
    local year_log=$(echo "$(date +%Y)")
    local time_log=$(echo "$(date +%Hh%Mm%Ss)")
    local user_log="$(echo "$user_name" | tr '[:upper:]' '[:lower:]')"
    local app_log="$(echo "$app" | tr '[:upper:]' '[:lower:]')"
    local rev_log="$(echo "$rev" | sed -r "s|$delim|_|g")"
    local ambiente_log="$(echo "${ambiente}" | tr '[:upper:]' '[:lower:]')"
    local host_log="$(echo "$host" | grep -Eiv '[a-z]' || echo "$host" | cut -f1 -d '.' | tr '[:upper:]' '[:lower:]')"
    local obs_log="<a href=\"$web_context_path/deploy_logs.cgi?app=$app&env=${ambiente}&deploy_id=$deploy_id\">$1</a>"
    local flag_log="$2"

    local header="$(echo "${col[day]}${col[month]}${col[year]}${col[time]}${col[user]}${col[app]}${col[rev]}${col[env]}${col[host]}${col[obs]}${col[flag]}" | sed -r 's/\[//g' | sed -r "s/\]/$delim/g")"
    local msg_log="$day_log$delim$month_log$delim$year_log$delim$time_log$delim$user_log$delim$app_log$delim$rev_log$delim${ambiente_log}$delim$host_log$delim$obs_log$delim$flag_log$delim"

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

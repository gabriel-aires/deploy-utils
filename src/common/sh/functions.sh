#!/bin/bash

# Define funções comuns.

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

function lock () {                                            #argumentos: nome_trava, mensagem_erro, (instrução)

    local exit_cmd="return 1"

    if [ -d $lock_dir ] && [ -n "$1" ] && [ -n "$2" ]; then

        local lockfile="$(echo "$1" | sed -r "s|[;, \:\.]+|_|g")"
        local miliseconds=$(date +%s%3N)
        local timeout=$(($lock_timeout+$miliseconds))

        case $verbosity in
            'quiet') exit_cmd="log 'INFO' '$2'; $exit_cmd";;
            'verbose') exit_cmd="echo -e '\n$2'; $exit_cmd";;
        esac

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

function chk_template () { # argumentos: caminho_arquivo nome_template

    if [ -f "$1" ] && [ -n "$2" ]; then

        local file="$1"
        local template_name="$2"
        local template_file="$install_dir/template/$template_name.template"
        local key

        if [ ! -f "$template_file" ]; then
            case $verbosity in
                'quiet') log "ERRO" "O template espeficicado não foi encontrado: $template_name.";;
                'verbose') echo -e "\nErro. O template espeficicado não foi encontrado: $template_name.";;
            esac
            return 1

        else
        
            key=$(cat "$template_file" | sed -rn "s/^.*@([^@]+)@.*$/\1/gp" | sort | uniq)

            if [ -n "$key" ]; then

                if [ "$(cat $file | grep -Ev "^$|^#" | sed -r 's|(=).*$|\1|' | grep -Evx --file <( sed -r "s/@[^@]+@$/${regex[$key]}/g" "$template_file") | wc -l)" -ne "0" ]; then
                    case $verbosity in
                        'quiet') log "ERRO" "Há parâmetros incorretos no arquivo $file:";;
                        'verbose') echo -e "\nErro. Há parâmetros incorretos no arquivo $file:";;
                    esac
                    cat $file | grep -Ev "^$|^#" | sed -r 's|(=).*$|\1|' | grep -Evx --file <( sed -r "s/@[^@]+@$/${regex[$key]}/g" "$template_file")
                    return 1
                fi            

            else

                if [ "$(cat $file | grep -Ev "^$|^#" | sed -r 's|(=).*$|\1|' | grep -vx --file "$template_file" | wc -l)" -ne "0" ]; then
                    case $verbosity in
                        'quiet') log "ERRO" "Há parâmetros incorretos no arquivo $file:";;
                        'verbose') echo -e "\nErro. Há parâmetros incorretos no arquivo $file:";;
                    esac
                    cat $file | grep -Ev "^$|^#" | sed -r 's|(=).*$|\1|' | grep -vx --file "$template_file"
                    return 1
                fi
            fi
        
        fi
    else
        return 1
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
    local alt_forbidden_regex=''
    local compound_rule="$([[ $rule_id =~ : ]] && echo true || echo false)"
    local rule_name="$rule_id"
    local missing_rule_msg="Não há uma regra correspondente à chave '$rule_name'"
    
    if $compound_rule; then
        rule_name="${rule_id//:*}"
        valid_regex="${regex[$rule_name]}"
        forbidden_regex="${not_regex[$rule_name]}"
        alt_valid_regex="${regex[$rule_id]}"
        alt_forbidden_regex="${not_regex[$rule_id]}"
    fi

    if [ -z "$valid_regex" ]; then
        case "$verbosity" in
            'quiet') log "ERRO" "$missing_rule_msg";;
            'verbose') echo "Erro. $missing_rule_msg";;
        esac
        return 1
    
    elif [[ $value =~ ^$valid_regex$ ]] && [[ $value =~ ^$alt_valid_regex$ ]] && [[ ! $value =~ ^$forbidden_regex$ ]] && [[ ! $value =~ ^$alt_forbidden_regex$ ]]; then
        return 0

    else
        case "$verbosity" in
            'quiet') log "ERRO" "$error_msg";;
            'verbose') echo -e "$error_msg";;
        esac
        return 1
    fi

}

function write_history () {

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

    valid "$obs_log" "csv_value" "'$obs_log': mensagem inválida." || return 1
    valid "$flag_log" "flag" "'$flag_log': flag de deploy inválida." || return 1

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

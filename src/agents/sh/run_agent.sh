#!/bin/bash
#
# Script para automatização dos deploys e disponibilização de logs do ambiente JBOSS / Linux.
#
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1

# Utilização
if [ "$#" -ne '3' ] || [ -z "$1" ] || [ -z "$2" ] || [ ! -f "$3" ]; then
    echo "Utilização: $(readlink -f $0) <nome_agente> <nome_tarefa> <arquivo_de_configuração>" && exit 1
fi

agent_name_input="$1"
agent_task="$2"
agent_conf="$3"
pid="$$"
execution_mode="agent"
verbosity="quiet"
interactive=false
host=$(echo $HOSTNAME | cut -f1 -d '.')

###### FUNÇÕES ######

function end () {

    test -d "$tmp_dir" && rm -f ${tmp_dir}/* && rmdir ${tmp_dir}
    test -d "$remote_lock_dir" && rm -f "$remote_lock_dir/run_agent_${host}_${pid}"
    clean_locks

    exit "$1"
}

function set_dir () {

    # Encontra os diretórios de origem/destino com base na hierarquia definida em global.conf. IMPORTANTE: TODOS os parâmetros de configuração devem ser validados previamente.

    local raiz="$1"
    local dir_acima="$raiz"
    local set_var="$2"

    unset "$2"

    local fim=0
    local n=1
    local var_n="dir_$n"

    if [ "$(eval "echo \$$var_n")" == '' ];then
        fim=1
    else
        local dir_n="$(eval "echo \$$var_n")"
        dir_n="$(eval "echo \$$dir_n")"
        local nivel=1
    fi

    while [ "$fim" -eq '0' ]; do

        dir_acima=$dir_acima/$dir_n

        ((n++))
        var_n="dir_$n"

        if [ "$(eval "echo \$$var_n")" == '' ];then
            fim=1
        else
            dir_n="$(eval "echo \$$var_n")"
            dir_n="$(eval "echo \$$dir_n")"
            ((nivel++))
        fi

    done

    if [ "$nivel" == "$qtd_dir" ]; then
        set_var="$set_var=$(find "$raiz" -wholename "$dir_acima" 2> /dev/null)"
        eval $set_var
    else
        log "ERRO" "Parâmetros incorretos no arquivo '$agent_conf'."
        return 1
    fi

    return 0
}

chk_dir () {

    if [ -d "$1" ] && [ -n "$2" ] && [ -n "$3" ]; then

        local root_dir="$1"
        local last_dir="$2"
        local ext_list="$3"
        local file_path_regex=''

        log "INFO" "Verificando a consistência dos diretórios de '$last_dir' em '$root_dir'..."

        # eliminar da estrutura de diretórios subjacente os arquivos e subpastas cujos nomes contenham espaços.
        find $root_dir/* | sed -r "s| |\\ |g" | grep ' ' | xargs -r -d "\n" rm -Rfv

        # garantir integridade da estrutura de diretórios, eliminando subpastas inseridas incorretamente.
        find $root_dir/* -type d | grep -Eix "^$root_dir/[^/]+/$last_dir(/[^/]+)+$" | xargs -r -d "\n" rm -Rfv

        # eliminar arquivos em local incorreto ou com extensão diferente das especificadas.
        file_path_regex="^$root_dir/[^/]+/$last_dir/[^/]*\."
        file_path_regex="$(echo "$file_path_regex" | sed -r "s|^(.*)$|\1$ext_list\$|ig" | sed -r "s: :\$\|$file_path_regex:g")"
        find "$root_dir" -type f | grep -Eix "^$root_dir/[^/]+/$last_dir/[^/]+$" | grep -Eixv "$file_path_regex" | xargs -r -d "\n" rm -fv

    else
        log "ERRO" "chk_dir: falha na validação dos parâmetros: $@"
        end 1
    fi

    return 0

}

function deploy_agent () {

    local file_path_regex=''

    if [ $(ls "${origem}/" -l | grep -E "^d" | wc -l) -ne 0 ]; then

        chk_dir ${origem} "deploy" "$filetypes"

        # Verificar se há arquivos para deploy.

        log "INFO" "Procurando novos pacotes..."

        file_path_regex="^.*\."
        file_path_regex="$(echo "$file_path_regex" | sed -r "s|^(.*)$|\1$filetypes\$|ig" | sed -r "s: :\$\|$file_path_regex:g")"

        find "$origem" -type f -regextype posix-extended -iregex "$file_path_regex" > $tmp_dir/arq.list

        if [ $(cat $tmp_dir/arq.list | wc -l) -lt 1 ]; then
            log "INFO" "Não foram encontrados novos pacotes para deploy."
        else
            # Caso haja arquivos, verificar se o nome do pacote corresponde ao diretório da aplicação.

            rm -f "$tmp_dir/remove_incorretos.list"
            touch "$tmp_dir/remove_incorretos.list"

            while read l; do

                pkg_name=$( echo $l | sed -r "s|^${origem}/[^/]+/deploy/([^/]+)\.[a-z0-9]+$|\1|i" )
                app=$( echo $l | sed -r "s|^${origem}/([^/]+)/deploy/[^/]+\.[a-z0-9]+$|\1|i" )

                if [ $(echo $pkg_name | grep -Ei "^$app" | wc -l) -ne 1 ]; then
                    echo $l >> "$tmp_dir/remove_incorretos.list"
                fi

            done < "$tmp_dir/arq.list"

            if [ $(cat $tmp_dir/remove_incorretos.list | wc -l) -gt 0 ]; then
                log "WARN" "Removendo pacotes em diretórios incorretos..."
                cat "$tmp_dir/remove_incorretos.list" | xargs -r -d "\n" rm -fv
            fi

            # Caso haja pacotes, deve haver no máximo um pacote por diretório

            find "$origem" -type f -regextype posix-extended -iregex "$file_path_regex" > $tmp_dir/arq.list

            rm -f "$tmp_dir/remove_versoes.list"
            touch "$tmp_dir/remove_versoes.list"

            while read l; do

                pkg_name=$( echo $l | sed -r "s|^${origem}/[^/]+/deploy/([^/]+)\.[a-z0-9]+$|\1|i" )
                dir=$( echo $l | sed -r "s|^(${origem}/[^/]+/deploy)/[^/]+\.[a-z0-9]+$|\1|i" )

                if [ $( find $dir -type f | wc -l ) -ne 1 ]; then
                    echo $l >> $tmp_dir/remove_versoes.list
                fi

            done < "$tmp_dir/arq.list"

            if [ $(cat $tmp_dir/remove_versoes.list | wc -l) -gt 0 ]; then
                log "WARN" "Removendo pacotes com mais de uma versão..."
                cat $tmp_dir/remove_versoes.list | xargs -r -d "\n" rm -fv
            fi

            # O arquivo pkg.list será utilizado para realizar a contagem de pacotes existentes
            find "$origem" -type f -regextype posix-extended -iregex "$file_path_regex" > $tmp_dir/pkg.list

            if [ $(cat $tmp_dir/pkg.list | wc -l) -lt 1 ]; then
                log "INFO" "Não há novos pacotes para deploy."
            else
                log "INFO" "Verificação do diretório ${remote_pkg_dir_tree} concluída. Iniciando processo de deploy dos pacotes abaixo."
                cat $tmp_dir/pkg.list

                # A variável pkg_list foi criada para permitir a iteração entre a lista de pacotes, uma vez que o diretório temporário precisa ser limpo.
                pkg_list="$(find "$origem" -type f -regextype posix-extended -iregex "$file_path_regex")"
                pkg_list="$(echo "$pkg_list" | sed -r "s%(.)$%\1|%g")"

                echo $pkg_list | while read -d '|' pkg; do

                    #define variáveis a sereem utilizadas pelo agente durante o processo de deploy.
                    export pkg
                    export ext=$(echo $(basename $pkg) | sed -r "s|^.*\.([^\.]+)$|\1|" | tr '[:upper:]' '[:lower:]')

                    pkg_chk=$(echo $(basename $pkg) | sed -rn "s|^.*%user_[^%]+%md5_([^%]+)%\.$ext$|\1|pi" | tr '[:upper:]' '[:lower:]')

                    if [ -n "$pkg_chk" ]; then
                        log "INFO" "Verificando checksum md5 do pacote..."
                        seconds=0
                        pkg_verified=false

                        while ! $pkg_verified && [ "$seconds" -le "$((agent_timeout/2))" ]; do
                            pkg_sum="$(md5sum "$pkg" | cut -d ' ' -f1)"
                            if [ "$pkg_chk" == "$pkg_sum" ]; then
                                pkg_verified=true
                            else
                                ((seconds++))
                                sleep 1
                            fi
                        done

                        ! $pkg_verified && log "ERRO" "Falha na verificação do checksum md5 do pacote: $pkg_sum/$pkg_chk" && continue
                        log "INFO" "Checksum md5 do pacote verificado com sucesso: $pkg_sum"
                    fi

                    export user_name=$(echo $(basename $pkg) | sed -rn "s|^.*%user_([^%]+)%md5_[^%]+%\.$ext$|\1|pi" | tr '[:upper:]' '[:lower:]')
                    export app=$(echo $pkg | sed -r "s|^${origem}/([^/]+)/deploy/[^/]+$|\1|i" | tr '[:upper:]' '[:lower:]')

                    case $ext in
                        war|ear|sar)
                            rev=$(unzip -p -a $pkg META-INF/MANIFEST.MF | grep -i implementation-version | sed -r "s|^.+ (([[:graph:]])+).*$|\1|")
                            ;;
                        *)
                            rev=$(echo $(basename $pkg) | sed -r "s|^$app||i" | sed -r "s|$ext$||i" | sed -r "s|%user_$user_name%md5_$pkg_chk%||i" | sed -r "s|^[\.\-_]||")
                            ;;
                    esac

                    export rev

                    test -n "$rev" || rev="N/A"
                    test -n "$user_name" || user_name="$(id --user --name)"

                    #### Diretórios onde serão armazenados os logs de deploy (define e cria os diretórios remote_app_history_dir e deploy_log_dir)
                    set_app_history_dirs

                    export remote_app_history_dir
                    export deploy_log_dir
                    export deploy_id

                    #valida variáveis antes da chamada do agente.
                    valid "$app" 'app' "'$app': Nome de aplicação inválido" || continue
                    valid "$host" "hosts:${ambiente}" "'$host': Host inválido para o ambiente ${ambiente}" || continue

                    #inicio deploy
                    deploy_log_file=$deploy_log_dir/deploy_${host}.log
                    qtd_log_inicio=$(cat $log | wc -l)
                    find $tmp_dir/ -type f | grep -vxF "$log" | xargs -d '\n' -r rm -f
                    find $tmp_dir/ -type p | xargs -d '\n' -r rm -f
                    $agent_script 'deploy'
                    qtd_log_fim=$(cat $log | wc -l)
                    qtd_info_deploy=$(( $qtd_log_fim - $qtd_log_inicio ))
                    tail -n ${qtd_info_deploy} $log > $deploy_log_file

                done

            fi

        fi

    else
        log "ERRO" "Não foram encontrados os diretórios das aplicações em $origem"
    fi

}

function log_agent () {

    if [ $(ls "${destino}/" -l | grep -E "^d" | wc -l) -ne 0 ]; then

        chk_dir "$destino" "log" "$filetypes refresh"

        app_list="$(find $destino/* -type d -name 'log' -print | sed -r "s|^${destino}/([^/]+)/log|\1|ig")"
        app_list=$(echo "$app_list" | sed -r "s%(.)$%\1|%g" | tr '[:upper:]' '[:lower:]')

        echo $app_list | while read -d '|' app; do

            shared_log_dir=$(find "$destino/" -type d -wholename "$destino/$app/log" 2> /dev/null)

            if [ -d "$shared_log_dir" ]; then

                test -f "$shared_log_dir/.refresh" || continue
                valid "$app" 'app' "'$app': Nome de aplicação inválido." || continue

                export shared_log_dir
                export app

                find $tmp_dir/ -type f | grep -vxF "$log" | xargs -d '\n' -r rm -f
                find $tmp_dir/ -type p | xargs -d '\n' -r rm -f
                $agent_script 'log'
                echo -e "Log de execução do agente:\n\n" > "$shared_log_dir/agent_$host.log"
                test -f "$log_dir/service.log" && cat "$log_dir/service.log" >> "$shared_log_dir/agent_$host.log"
                cat "$log" >> "$shared_log_dir/agent_$host.log"
                unix2dos "$shared_log_dir/agent_$host.log" &> /dev/null
                rm -f "$shared_log_dir/.refresh" &> /dev/null

            else
                log "ERRO" "O diretório para cópia de logs da aplicação $app não foi encontrado".
            fi

        done

    else
        log "ERRO" "Não foram encontrados os diretórios das aplicações em $destino"
    fi

}

###### INICIALIZAÇÃO ######
trap "end 1; exit" SIGQUIT SIGINT SIGHUP SIGTERM

# Valida o arquivo global.conf e carrega configurações
global_conf="${install_dir}/conf/global.conf"
chk_template "$global_conf" "global" && source "$global_conf" || exit 1

# cria diretório temporário
tmp_dir="$work_dir/$pid"
valid "$tmp_dir" 'tmp_dir' "'$tmp_dir': Caminho inválido para armazenamento de diretórios temporários" && mkdir -p $tmp_dir || end 1

# cria log do agente
log="$tmp_dir/agent.log"
touch $log

# cria diretório de locks
valid "$lock_dir" 'lock_dir' "'$lock_dir': Caminho inválido para o diretório de lockfiles do agente." && mkdir -p $lock_dir || end 1

#valida caminho para diretórios do servidor e argumentos do script
erro=false
valid "$agent_name_input" 'agent_name' "'$agent_name_input': Nome inválido para o agente." || erro=true
valid "$agent_task" 'agent_task' "'$agent_task': Nome inválido para a tarefa." || erro=true
valid "$remote_pkg_dir_tree" 'remote_dir' "'$remote_pkg_dir_tree': Caminho inválido para o repositório de pacotes." || erro=true
valid "$remote_log_dir_tree" 'remote_dir' "'$remote_log_dir_tree': Caminho inválido para o diretório raiz de cópia dos logs." || erro=true
valid "$remote_lock_dir" 'remote_dir' "'$remote_lock_dir': Caminho inválido para o diretório de lockfiles do servidor" || erro=true
valid "$remote_history_dir" 'remote_dir' "'$remote_history_dir': Caminho inválido para o diretório de gravação do histórico" || erro=true
valid "$remote_app_history_dir_tree" 'remote_dir' "'$remote_app_history_dir_tree': Caminho inválido para o histórico de deploy das aplicações" || erro=true
test ! -f "$agent_conf" && log 'ERRO' "'$agent_conf': Arquivo de configuração inexistente."  && erro=true
test ! -d "$remote_pkg_dir_tree" && log 'ERRO' 'Caminho para o repositório de pacotes inexistente.' && erro=true
test ! -d "$remote_log_dir_tree" && log 'ERRO' 'Caminho para o diretório raiz de cópia dos logs inexistente.' && erro=true
test ! -d "$remote_lock_dir" && log 'ERRO' 'Caminho para o diretório de lockfiles do servidor não encontrado' && erro=true
test ! -d "$remote_history_dir" && log 'ERRO' 'Caminho para o diretório de gravação do histórico não encontrado' && erro=true
test ! -d "$remote_app_history_dir_tree" && log 'ERRO' 'Caminho para o histórico de deploy das aplicações não encontrado' && erro=true
$erro && end 1 || unset erro

#criar lockfile
lock "$agent_name_input $agent_task $(basename $agent_conf | cut -d '.' -f1)" "Uma tarefa concorrente já está em andamento. Aguarde..." || end 1
test ! -f "$remote_lock_dir/edit_agent_${host}" && touch "$remote_lock_dir/run_agent_${host}_${pid}" || end 1

# Valida o arquivo de configurações $agent_conf, que deve atender aos templates agent.template e $agent_name.template
chk_template "$agent_conf" 'agent' && chk_template "$agent_conf" "$agent_name_input" && source "$agent_conf" || end 1

# validar parâmetros do arquivo $agent_conf:
erro=false
valid "$ambiente" 'ambiente' "'${ambiente}': Nome inválido para o ambiente." || erro=true
valid "$run_deploy_agent" 'bool' "Valor inválido para o parâmetro 'run_deploy_agent' (booleano)." || erro=true
valid "$run_log_agent" 'bool' "Valor inválido para o parâmetro 'run_log_agent' (booleano)." || erro=true
valid "$deploy_filetypes" 'filetypes' "Lista de extensões inválida para o agente de 'deploy'." || erro=true
valid "$log_filetypes" 'filetypes' "Lista de extensões inválida para o agente de 'log'." || erro=true
test "$agent_name_input" != "$agent_name" && log 'ERRO' "O nome de agente informado não corresponde àquele no arquivo '$agent_conf'"  && erro=true
$erro && end 1 || unset erro

filetypes=$(grep -Ex "${agent_task}_filetypes=.*" "$agent_conf" | cut -d '=' -f2 | sed -r "s/'//g" | sed -r 's/"//g')

# verificar se o caminho para obtenção dos pacotes / gravação de logs está disponível.
set_dir "$remote_pkg_dir_tree" 'origem' || end 1
set_dir "$remote_log_dir_tree" 'destino' || end 1

if [ $( echo "$origem" | wc -w ) -ne 1 ] || [ ! -d "$origem" ] || [ $( echo "$destino" | wc -w ) -ne 1 ] || [ ! -d "$destino" ]; then
    log "ERRO" "O caminho para o diretório de pacotes / logs não foi encontrado ou possui espaços."
    end 1
fi

# Identifica script do agente.
agent_script="${install_dir}/sh/$agent_name.sh"
if [ ! -x $agent_script ]; then
    log "ERRO" "O arquivo executável correspondente ao agente $agent_name não foi identificado."
    end 1
fi

# "exportar" arrays associativos
export BASH_ENV="$tmp_dir/load_arrays"
declare -p regex not_regex > "$BASH_ENV"

# exportar funções e variáveis necessárias ao agente. Outras variáveis serão exportadas diretamente a partir das funções log_agent e deploy_agent
export -f 'valid'
export -f 'log'
export -f 'write_history'
export 'delim'
export 'execution_mode'
export 'verbosity'
export 'interactive'
export 'host'
export 'lock_history'
export 'agent_timeout'
export 'remote_lock_dir'
export 'history_lock_file'
export 'web_context_path'
export 'remote_history_dir'
export 'history_csv_file'
export 'tmp_dir'

while read l ; do
    if [ $(echo $l | grep -Ex "[a-zA-Z0-9_]+=.*" | wc -l) -eq 1 ]; then
        conf_var=$(echo "$l" | sed -r "s|=.*$||")
        export $conf_var
    fi
done < $agent_conf

# executar agente.
case $agent_task in
    'log')
        if [ "$(cat $agent_script | sed -r 's|"||g' | sed -r "s|'||g" | grep -E '^[^[:graph:]]*log\)' | wc -l)" -eq 1 ]; then
            $run_log_agent && log_agent | tee -a $log || log "INFO" "Agente de log desabilitado pelo arquivo $agent_conf"
        else
            log "ERRO" "O script $agent_script não aceita o argumento 'log'." && end 1
        fi
        ;;
    'deploy')
        if [ "$(cat $agent_script | sed -r 's|"||g' | sed -r "s|'||g" | grep -E '^[^[:graph:]]*deploy\)' | wc -l)" -eq 1 ]; then
            $run_deploy_agent && deploy_agent | tee -a $log || log "INFO" "Agente de deploy desabilitado pelo arquivo $agent_conf"
        else
            log "ERRO" "O script $agent_script não aceita o argumento 'deploy'." && end 1
        fi
        ;;
esac

end 0

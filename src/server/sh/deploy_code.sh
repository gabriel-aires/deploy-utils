#!/bin/bash
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

estado="validacao"
pid=$$
user_name="$(id --user --name)"
auto="false"
simulation="false"
redeploy="false"
execution_mode="server"
message_format="simple"

##### Execução somente como usuário root ######

if [ "$(id -u)" -ne "0" ]; then
    echo "Requer usuário root."
    exit 1
fi

#### UTILIZAÇÃO: deploy_pages.sh -opções <aplicação> <revisão> <ambiente> ############

while getopts ":dnru:h" opcao; do
    case $opcao in
        d)
            modo='d'
            ;;
        n)
            simulation="true"
            ;;
        r)
            redeploy="true"
            ;;
        u)
            user_name="$OPTARG"
            ;;
        h)
            echo -e "O script requer os seguintes parâmetros: (opções) <aplicação> <revisão> <ambiente>."
            echo -e "Opções:"
            echo -e "\t-d\thabilitar o modo de deleção de arquivos obsoletos."
            echo -e "\t-n\tsimular deploy."
            echo -e "\t-r\tpermitir redeploy."
            exit 0
            ;;
        \?)
            echo "-$OPTARG não é uma opção válida ( -d -n -r -h )." && exit 1
            ;;
    esac
done

shift $(($OPTIND-1))

if [ "$#" -lt 3 ]; then
    echo "O script requer no mínimo 3 parâmetros: <aplicação> <revisão> <ambiente>" && exit 1
fi

app=$1
rev=$2
ambiente=$3

#### Funções ##########

function checkout () {                                                   #o comando cd precisa estar encapsulado para funcionar adequadamente num script, por isso foi criada a função.

    if [ ! -d "$repo_dir/$nomerepo/.git" ]; then
        echo " "
        git clone --progress "$repo" "$repo_dir/$nomerepo" || end 1      #clona o repositório, caso ainda não tenha sido feito.
    fi

    cd "$repo_dir/$nomerepo"
    git fetch origin --force --quiet || end 1                            #atualiza commits (nesse caso, o fetch é realizado com o refspec default do repositório, normalmente é +refs/heads/*:refs/remotes/origin/*)
    git fetch origin --force --quiet +refs/tags/*:refs/tags/* || end 1   #atualiza tags (a opção --tags não foi utilizada, pq seu comportamento foi alterado a partir do git 1.9)

    if $auto; then

        valid "${revisao[$ambiente]}" "rev:$ambiente" "\nInforme um valor válido para o parâmetro revisao[${ambiente}]: [commit/tag]." || end 1
        revisao_auto="${revisao[$ambiente]}"

        valid "${branch[$ambiente]}" "branch:$ambiente" "\nInforme um valor válido para o parâmetro branch_${ambiente} (Ex: 'master')." || end 1
        branch_auto="${branch[$ambiente]}"

        git branch -a | grep -v remotes/origin/HEAD | cut -b 3- > $tmp_dir/branches

        if [ $(grep -Ei "^remotes/origin/${branch_auto}$" $tmp_dir/branches | wc -l) -ne 1 ]; then
            end 1
        fi

        last_commit=''

        case $revisao_auto in
            tag)
                git log "origin/$branch_auto" --oneline | cut -f1 -d ' ' > $tmp_dir/commits
                git tag -l | sort -V > $tmp_dir/tags

                while read tag; do

                    commit_tag=$(git log "$tag" --oneline | head -1 | cut -f1 -d ' ')
                    if [ $(grep -Ex "^${commit_tag}$" $tmp_dir/commits | wc -l) -eq 1 ]; then
                        last_commit=$commit_tag
                        last_tag=$tag
                    fi

                done < $tmp_dir/tags

                if [ ! -z $last_commit ] && [ ! -z $last_tag ]; then
                    echo -e "\nObtendo a revisão $last_commit a partir da tag $last_tag."
                    rev=$last_tag
                else
                    echo "Erro ao obter a revisão especificada. Deploy abortado"
                    end 1
                fi
                ;;
            commit)
                last_commit=$(git log "origin/$branch_auto" --oneline | head -1 | cut -f1 -d ' ')

                if [ ! -z $last_commit ]; then
                    echo -e "\nObtendo a revisão $last_commit a partir da branch $branch_auto."
                    rev=$last_commit
                else
                    echo "Erro ao obter a revisão especificada. Deploy abortado"
                    end 1
                fi
                ;;
        esac
    else
        echo -e "\nObtendo a revisão ${rev}..."
    fi

    git checkout --force --quiet $rev || end 1

    if [ -z "$(git branch | grep -x '* (no branch)' )" ]; then
        echo -e "\nDeploys a partir do nome de uma branch são proibidos, pois prejudicam a rastreabilidade do processo. Deploy abortado"
        end 1
    fi

    cd - &> /dev/null
}

function deploy () {

    local extra_opts="$1"

    rsync_cmd="rsync --itemize-changes $extra_opts $rsync_opts $origem/ $destino/ > $deploy_log_dir/modificacoes_$host.txt"
    eval $rsync_cmd || end 1

    if [ "$rev" != "rollback" ] && [ "$extra_opts" != "--dry-run" ] && [ "$extra_opts" != "-n" ]; then
        test -z $force_uid || chown -R $force_uid $destino/* || end 1
        test -z $force_gid || chgrp -R $force_gid $destino/* || end 1
    fi

    ##### RESUMO DAS MUDANÇAS ######

    adicionados="$(grep -E "^>f\+" $deploy_log_dir/modificacoes_$host.txt | wc -l)"
    excluidos="$(grep -E "^\*deleting .*[^/]$" $deploy_log_dir/modificacoes_$host.txt | wc -l)"
    modificados="$(grep -E "^>f[^\+]" $deploy_log_dir/modificacoes_$host.txt | wc -l)"
    dir_criado="$(grep -E "^cd\+" $deploy_log_dir/modificacoes_$host.txt | wc -l)"
    dir_removido="$(grep -E "^\*deleting .*/$" $deploy_log_dir/modificacoes_$host.txt | wc -l)"

    total_arq=$(( $adicionados + $excluidos + $modificados ))
    total_dir=$(( $dir_criado + $dir_removido ))
    total_del=$(( $excluidos + dir_removido ))

    echo -e "\nLog das modificacoes gravado no arquivo modificacoes_$host.txt\n" > $deploy_log_dir/resumo_$host.txt
    echo -e "Arquivos adicionados ............... $adicionados " >> $deploy_log_dir/resumo_$host.txt
    echo -e "Arquivos excluidos ................. $excluidos" >> $deploy_log_dir/resumo_$host.txt
    echo -e "Arquivos modificados ............... $modificados" >> $deploy_log_dir/resumo_$host.txt
    echo -e "Diretórios criados ................. $dir_criado" >> $deploy_log_dir/resumo_$host.txt
    echo -e "Diretórios removidos ............... $dir_removido\n" >> $deploy_log_dir/resumo_$host.txt
    echo -e "Total de operações de arquivos ..... $total_arq" >> $deploy_log_dir/resumo_$host.txt
    echo -e "Total de operações de diretórios ... $total_dir" >> $deploy_log_dir/resumo_$host.txt
    echo -e "Total de operações de exclusão ..... $total_del\n" >> $deploy_log_dir/resumo_$host.txt

    cat $deploy_log_dir/resumo_$host.txt

}

function check_last_deploy () {

    cd $origem

    if [ -f "${history_dir}/$history_csv_file" ]; then
        local top=1
        last_rev=''
        while [ -z "$last_rev" ]; do
            last_rev=$(query_file.sh --delim "$delim" --replace-delim '' --header 1 \
                '--select' ${col[rev]} \
                --top $top \
                --from "${history_dir}/$history_csv_file" \
                --where ${col[app]}==$app ${col[flag]}==1 ${col[env]}==${ambiente} \
                --order-by ${col[year]} ${col[month]} ${col[day]} ${col[time]} desc \
                | tail -n 1 2> /dev/null \
            )
            if [ "$last_rev" == 'rollback' ]; then
                last_rev=''
                top=$(($top+2))
            elif [ -z "$last_rev" ]; then
                break
            fi
        done
    else
        last_rev=''
    fi

    if [ -n "$last_rev" ]; then

        ### aborta a execução caso a revisão solicitada já tenha sido implantada no deploy anterior
        if [ "$rev" == "$last_rev" ] && [ "$redeploy" == "false" ]; then
            echo -e "\nA revisão $rev foi implantada no deploy anterior. Encerrando..."
            end 1
        fi

        ### em caso de deploy manual, alerta possível downgrade ###
        if ! $auto; then

            downgrade=false

            git tag > $tmp_dir/git_tag_app
            git log --decorate=full | grep -E "^commit" | sed -r "s|^commit ||" | sed -r "s| .*refs/tags/|\.\.|" | sed -r "s| .*$||" | sed -r "s|([a-f0-9]+\.\..*).$|\1|" > $tmp_dir/git_log_app

            local rev_check=$(echo $last_rev | sed -r "s|\.|\\\.|g")

            if [ $(grep -Ex "^$rev_check$" $tmp_dir/git_tag_app | wc -l) -eq 1 ]; then # a revisão é uma tag
                test $(grep -Ex "^[a-f0-9]+\.\.$rev_check$" $tmp_dir/git_log_app | wc -l) -eq 0 && downgrade=true    # a tag é posterior à revisão para a qual foi solicitado o deploy
            else # a revisão é um hash
                test $(grep -Ex "^$rev_check.*" $tmp_dir/git_log_app | wc -l) -eq 0 && downgrade=true  # o hash é posterior à revisão para a qual foi solicitado o deploy
            fi

            if $downgrade; then
                echo -e "\nAVISO! Foi detectado um deploy anterior de uma revisão mais recente: $last_rev"
            fi
        fi
    fi

    cd - &> /dev/null

}

function clean_temp () {                                        #cria pasta temporária, remove arquivos e pontos de montagem temporários

    if [ -d $tmp_dir ]; then

        if [ -f "$tmp_dir/destino_mnt" ]; then
            cat $tmp_dir/destino_mnt | xargs --no-run-if-empty umount 2> /dev/null
            wait
            cat $tmp_dir/destino_mnt | xargs --no-run-if-empty rmdir 2> /dev/null            #já desmontados, os pontos de montagem temporários podem ser apagados.i
        fi

        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi
}

function end () {

    trap "" SIGQUIT SIGTERM SIGINT SIGHUP

    local erro=$1
    local qtd_rollback=0

    if [ -z "$erro" ]; then
        erro=0
    elif [ $(echo "$erro" | grep -Ex "^[01]$" | wc -l) -ne 1 ]; then
        erro=1
    fi

    wait

    if [ "$erro" -eq 1 ] && [ -f "$deploy_log_dir/progresso_$host.txt" ]; then

        echo -e "\nDeploy abortado."

        if [ "$rev" == "rollback" ]; then
            echo -e "\nErro: rollback interrompido. Favor reexecutar o script."
            write_history "Rollback não efetuado. O script deve ser reexecutado." "0"
        else
            host_erro="$host"

            if [ "$estado" == 'backup' ] || [ "$estado" == 'fim_backup' ]; then

                bak="$bak_dir/${app}_${host}"                            # necessário garantir que a variável bak esteja setada, pois o script pode ter sido interrompido antes dessa etapa.
                rm -Rf $bak
                write_history "Deploy abortado." "0"

            elif [ "$estado" == 'escrita' ]; then

                if [ -n $(grep -REil '^rsync: open \"[^\"]+\" failed: Permission denied' $deploy_log_dir/rsync_$host.log) ]; then
                    grep -REi '^rsync: open \"[^\"]+\" failed: Permission denied' $deploy_log_dir/rsync_$host.log > $deploy_log_dir/permission_denied_$host.txt
                    sed -i -r 's|^[^\"]+\"([^\"]+)\"[^\"]+$|\1:|' $deploy_log_dir/permission_denied_$host.txt
                    sed -i -r "s|^$destino|$dir_destino|" $deploy_log_dir/permission_denied_$host.txt
                    sed -i -r 's|/|\\|g' $deploy_log_dir/permission_denied_$host.txt
                fi

                echo -e "\nO script foi interrompido durante a escrita. Revertendo alterações no host $host..."
                echo $host >> $tmp_dir/hosts_rollback

                echo "rollback" >> $deploy_log_dir/progresso_$host.txt

                rsync_cmd="rsync $rsync_bak_opts --group $rsync_opts $bak/ $destino/"
                eval $rsync_cmd && ((qtd_rollback++)) && rm -Rf $bak

                echo "fim_rollback" >> $deploy_log_dir/progresso_$host.txt
                write_history "Deploy interrompido. Backup restaurado." "0"

            else
                write_history "Deploy abortado." "0"
            fi

            echo "deploy_abortado" >> $deploy_log_dir/progresso_$host.txt

            cp $tmp_dir/dir_destino $tmp_dir/destino                        #foi necessário utilizar uma cópia do arquivo, uma vez que este foi utilizado como entrada padrão para o loop de deploy.

            while read destino_deploy; do

                case $mount_type in
                    'nfs') host=$(echo $dir_destino | sed -r "s|^([^/]+):.+$|\1|") ;;
                    'cifs') host=$(echo $dir_destino | sed -r "s|^//([^/]+)/.+$|\1|") ;;
                esac

                if [ ! "$host" == "$host_erro" ]; then

                    if [ -f "$deploy_log_dir/progresso_$host.txt" ]; then            # Indica que o processo de deploy já foi iniciado no host

                        estado_host=$(tail -1 "$deploy_log_dir/progresso_$host.txt")

                        if [ "$estado_host" == "fim_escrita" ]; then            # Deploy já concluído no host. Rollback necessário.

                            bak="$bak_dir/${app}_${host}"
                            destino="/mnt/deploy_${app}_${host}"

                            echo -e "\nRevertendo alterações no host $host..."
                            echo $host >> $tmp_dir/hosts_rollback

                            echo "rollback" >> $deploy_log_dir/progresso_$host.txt

                            rsync_cmd="rsync $rsync_bak_opts $rsync_opts $bak/ $destino/"
                            eval $rsync_cmd && ((qtd_rollback++)) && rm -Rf $bak

                            echo "fim_rollback" >> $deploy_log_dir/progresso_$host.txt
                            write_history "Rollback realizado devido a erro ou deploy cancelado em $host_erro." "0"

                        fi
                    else
                        write_history "Deploy abortado." "0"
                    fi
                fi

            done < $tmp_dir/destino

            if [ -f $tmp_dir/hosts_rollback ]; then
                if [ "$qtd_rollback" -eq $(cat $tmp_dir/hosts_rollback | wc -l) ]; then
                    echo -e "\nRollback finalizado."
                else
                    echo -e "\nErro. O rollback não foi concluído em todos os servidores do pool da aplicação $app."
                fi
            fi
        fi
    fi

    wait
    clean_locks
    clean_temp
    wait
    echo -e "\n$end_msg"
    exit $erro
}

#### Inicialização #####

if [ "$rev" == "rollback" ]; then
    trap "" SIGQUIT SIGTERM SIGINT SIGHUP                        # um rollback não deve ser interrompido pelo usuário.
else
    trap "end 1; exit" SIGQUIT SIGTERM SIGINT SIGHUP                #a função será chamada quando o script for finalizado ou interrompido.
fi

if [ -z "$modo_padrao" ] || [ -z "$rsync_opts" ] || [ -z "$ambientes" ]; then
    echo 'Favor preencher corretamente o arquivo global.conf / user.conf e tentar novamente.'
    exit 1
fi

mkdir -p $tmp_dir        # os outros diretórios são criados pelo include.sh

# Validação dos argumentos do script

echo "Iniciando processo de deploy..."

valid "$app" "app" "\nInforme o nome do sistema corretamente (somente letras minúsculas)." || end 1
valid "$rev" "rev" "\nInforme a revisão corretamente." || end 1
valid "$ambiente" "ambiente" "\nInforme o ambiente corretamente." || end 1

lock $app "Deploy abortado: há outro deploy da aplicação $app em curso." || end 1

# Validação dos parãmetros de deploy da aplicação $app

echo -e "\nObtendo parâmetros da aplicação $app..."
chk_template "${app_conf_dir}/${app}.conf" "app" && source "${app_conf_dir}/${app}.conf" || end 1

valid "$repo" "repo" "\nInforme um caminho válido para o repositório GIT." || end 1
valid "$raiz" "raiz" "\nInforme um caminho válido para a raiz da aplicação." || end 1
valid "${hosts[$ambiente]}" "hosts:$ambiente" "\nInforme uma lista válida de hosts para deploy, separando-os por espaço ou vírgula." || end 1
valid "${modo[$ambiente]}" "modo:$ambiente" "\nInforme um modo válido para deploy no ambiente ${ambiente} [p/d]." || end 1
valid "${auto[$ambiente]}" "auto:$ambiente" "\nInforme um valor válido para a flag de deploy automático no ambiente ${ambiente} [0/1]." || end 1
valid "${share[$ambiente]}" "share:$ambiente" "\nInforme um compartilhamento válido para deploy no ambiente ${ambiente}, suprimindo o nome do host (Ex: //host/a\$/b/c ]=> a\$/b/c, hostname:/a/b/c => /a/b/c)." || end 1
valid "$mount_type" "mount_type" "\nInforme um protocolo de compartilhamento válido [cifs/nfs]." || end 1
valid "$force_gid" "force_gid" "\nInforme um group id válido para a aplicação $app." || end 1
valid "$force_uid" "force_uid" "\nInforme um user id válido para a aplicação $app." || end 1

hosts_deploy="${hosts[$ambiente]}"
modo_deploy="${modo[$ambiente]}"
auto_deploy="${auto[$ambiente]}"
share_deploy="${share[$ambiente]}"

if [ "$rev" == "auto" ]; then
    if [ "$auto_deploy" == "1" ]; then
        auto="true"
    else
        echo "Erro. Deploy automático desabilitado para a aplicação $app no ambiente ${ambiente}." && end 1
    fi
fi

nomerepo=$(echo $repo | sed -r "s|^.*/([^/]+)\.git$|\1|")
lock "${nomerepo}_git" "Deploy abortado: há outro deploy utilizando o repositório $repo." || end 1

error=false
while read host; do
    case $mount_type in
        'cifs') dir_destino=$(echo "//$host/$share_deploy" | sed -r "s|^(//.+)//(.*$)|\1/\2|g" | sed -r "s|/$||") ;;
        'nfs') dir_destino=$(echo "$host:$share_deploy" | sed -r "s|(:)([^/])|\1/\2|" | sed -r "s|/$||") ;;
    esac
    nomedestino=$(echo $dir_destino | sed -r "s|[/:]|_|g")
    lock $nomedestino "Deploy abortado: há outro deploy utilizando o diretório $dir_destino." || error=true
    echo "$dir_destino" >> $tmp_dir/dir_destino
done < <(mklist "$hosts_deploy")
$error && end 1

#### Diretórios onde serão armazenados os logs de deploy (define e cria os diretórios app_history_dir e deploy_log_dir)
set_app_history_dirs

echo -e "\nSistema:\t$app"
echo -e "Revisão:\t$rev"
echo -e "Ambiente:\t${ambiente}"
echo -e "Deploy ID:\t<a href=\"$web_context_path/deploy_logs.cgi?app=$app&env=${ambiente}&deploy_id=$deploy_id\">$deploy_id</a>\n"

##### MODO DE DEPLOY #####

if [ -z "$modo" ]; then
    if [ -z "$modo_deploy" ]; then
        modo=$modo_padrao
    else
        modo=$modo_deploy
    fi
fi

if [ "$modo" == "d" ]; then
    rsync_opts="$rsync_opts --delete"
    obs_log="Deploy concluído com sucesso. Arquivos obsoletos deletados."
else
    obs_log="Deploy concluído com sucesso. Arquivos obsoletos preservados."
fi

##### GIT #########

if [ ! "$rev" == "rollback" ]; then
    echo -e "Repositório:\t$repo"
    echo -e "Caminho:\t$raiz"

    checkout                                                #ver checkout(): (git clone), cd <repositorio> , git fetch, git checkout...

    origem="$repo_dir/$nomerepo/$raiz"
    origem=$(echo "$origem" | sed -r "s|^(/.+)//(.*$)|\1/\2|g" | sed -r "s|/$||")

    if [ ! -d "$origem" ]; then
        echo -e "\nErro: não foi possível encontrar o caminho $origem.\nVerifique a revisão informada ou corrija o arquivo $app_conf_dir/$app.conf."
        end 1
    else
        check_last_deploy
    fi
else
    rsync_opts="$rsync_bak_opts $rsync_opts"
fi

###### REGRAS DE DEPLOY: IGNORE / INCLUDE #######

echo '' > $tmp_dir/regras_deploy.txt

if [ "$rev" == "rollback" ] && [ -f "${bak_dir}/regras_deploy_${app}_${ambiente}.txt" ]; then
    cat "${bak_dir}/regras_deploy_${app}_${ambiente}.txt" >> $tmp_dir/regras_deploy.txt

elif [ -f "$repo_dir/$nomerepo/.gitignore" ]; then
    dos2unix -n $repo_dir/$nomerepo/.gitignore $tmp_dir/gitignore_unix > /dev/null 2>&1                # garante que o arquivo .gitignore seja interpretado corretamente. (converte CRLF em LF)
    grep -Ev "^$|^ |^#" $tmp_dir/gitignore_unix >> $tmp_dir/regras_deploy.txt

    if [ ! "$raiz" == "/" ]; then
        raiz_git=$(echo "$raiz" | sed -r "s|^/||" | sed -r "s|/$||")
        sed -i -r "s|^(! +)?/$raiz_git(/.+)|\1\2|" $tmp_dir/regras_deploy.txt                    #padrões de caminho iniciados com / são substituídos.
        sed -i -r "s|^(! +)?($raiz_git)(/.+)|\1\2\3\n\1\3|" $tmp_dir/regras_deploy.txt                #entradas iniciados sem / são preservadas. Uma linha com a substituição correspondente é acrescentada logo abaixo.

    fi

    sed -i -r "s|^(! +)|+ |" $tmp_dir/regras_deploy.txt                                #um sinal de + (include) é acrescentado ao início das entradas precedidas de "!"
    sed -i -r "s|^([^+])|- \1|" $tmp_dir/regras_deploy.txt                                #um sinal de - (exclude) é acrescentado ao início das demais entradas.
fi

cp $tmp_dir/regras_deploy.txt $deploy_log_dir/                                        #a fim de proporcionar transparência ao processo de deploy, as regras de ignore/include são copiadas para o log.

bkp_regras=0                                                        #a flag será alterada tão logo as regras de deploy sejam copiadas para a pasta de backup.
rsync_opts="$rsync_opts --filter='. $tmp_dir/regras_deploy.txt'"

echo $estado > $tmp_dir/progresso.txt
estado="fim_$estado" && echo $estado >> $tmp_dir/progresso.txt

### início da leitura ###

while read dir_destino; do

    case $mount_type in
        'nfs') host=$(echo $dir_destino | sed -r "s|^([^/]+):.+$|\1|") ;;
        'cifs') host=$(echo $dir_destino | sed -r "s|^//([^/]+)/.+$|\1|") ;;
    esac

    cat $tmp_dir/progresso.txt > $deploy_log_dir/progresso_$host.txt
    estado="leitura" && echo $estado >> $deploy_log_dir/progresso_$host.txt

    echo -e "\nIniciando deploy no host $host..."
    echo -e "Diretório de deploy:\t$dir_destino"

    if [ "$rev" == "rollback" ]; then

        origem=${bak_dir}/${app}_${host}
        echo -e "Diretório de backup:\t$origem"

        if [ ! -d "$origem" ]; then
            echo -e "\nErro: não foi encontrado um backup da aplicação $app em $origem."
            end 1
        fi

    fi

    ##### CRIA PONTO DE MONTAGEM TEMPORÁRIO #####

    destino="/mnt/deploy_${app}_${host}"
    echo $destino >> $tmp_dir/destino_mnt

    mkdir $destino || end 1
    test -z "$mount_options" && mount_options=$(eval "echo \$${mount_type}_opts")
    mount -t $mount_type $dir_destino $destino -o $mount_options || end 1    #montagem do compartilhamento de destino (requer módulo anatel_ad, provisionado pelo puppet)
    estado="fim_$estado" && echo $estado >> $deploy_log_dir/progresso_$host.txt

    if $simulation; then

        estado="simulacao" && echo $estado >> $deploy_log_dir/progresso_$host.txt
        echo -e "\nSimulando alterações no diretório de destino..."
        deploy "--dry-run" || end 1
        obs_log="Simulação concluída com sucesso."
        estado="fim_$estado" && echo $estado >> $deploy_log_dir/progresso_$host.txt

    else

        if [ "$rev" != "rollback" ]; then

            #### preparação do backup ####
            estado="backup" && echo $estado >> $deploy_log_dir/progresso_$host.txt
            echo -e "\nCriando backup"
            bak="$bak_dir/${app}_${host}"
            rm -Rf $bak
            mkdir -p $bak
            rsync_cmd="rsync $rsync_bak_opts $rsync_opts $destino/ $bak/"
            eval $rsync_cmd || end 1

            #### backup regras de deploy ###
            if [ $bkp_regras -eq 0 ]; then
                cat $tmp_dir/regras_deploy.txt > "${bak_dir}/regras_deploy_${app}_${ambiente}.txt"
                bkp_regras=1
            fi
            estado="fim_$estado" && echo $estado >> $deploy_log_dir/progresso_$host.txt
        fi

        #### gravação das alterações em disco ####
        estado="escrita" && echo $estado >> $deploy_log_dir/progresso_$host.txt
        echo -e "\nEscrevendo alterações no diretório de destino..."
        deploy 2> $deploy_log_dir/rsync_$host.log || end 1
        write_history "$obs_log" "1"
        estado="fim_$estado" && echo $estado >> $deploy_log_dir/progresso_$host.txt
    fi

done < $tmp_dir/dir_destino

echo "$obs_log"
end 0

#!/bin/bash
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1

estado="validacao"
pid=$$
interactive="true"
automatico="false"

##### Execução somente como usuário root ######

if [ ! "$USER" == 'root' ]; then
	echo "Requer usuário root."
	exit 1
fi

#### UTILIZAÇÃO: deloy_paginas.sh <aplicação> <revisão> <ambiente> -opções ############

while getopts ":dfh" opcao; do
	case $opcao in
        d)
            modo='d'
			;;
		f)
			interactive="false"
			;;
		h)
			echo -e "O script requer os seguintes parâmetros: (opções) <aplicação> <revisão> <ambiente>."
			echo -e "Opções:"
			echo -e "\t-d\thabilitar o modo de deleção de arquivos obsoletos."
			echo -e "\t-f\tforçar a execução do script de forma não interativa."
			exit 0
			;;
		\?)
			echo "-$OPTARG não é uma opção válida ( -d -f -h )." && exit 1
			;;
	esac
done

shift $(($OPTIND-1))

if [ "$#" -lt 3 ]; then
	echo "O script requer no mínimo 3 parâmetros: <aplicação> <revisão> <ambiente>"
	exit 1
fi

app=$1
rev=$2
ambiente=$3


#### Funções ##########

function checkout () {											# o comando cd precisa estar encapsulado para funcionar adequadamente num script, por isso foi criada a função.

	if [ ! -d "$repo_dir/$nomerepo/.git" ]; then
		echo " "
		git clone --progress "$repo" "$repo_dir/$nomerepo" || end 1				#clona o repositório, caso ainda não tenha sido feito.
	fi

	cd "$repo_dir/$nomerepo"
	git fetch --all --force --quiet || end 1

	if $automatico; then

		valid "revisao_$ambiente" "\nErro. O valor obtido para o parâmetro revisao_$ambiente não é válido. Favor corrigir o arquivo '$app_conf_dir/$app.conf'."
		revisao_auto="echo \$revisao_${ambiente}"
		revisao_auto=$(eval "$revisao_auto")

		valid "branch_$ambiente" "\nErro. O valor obtido para o parâmetro branch_$ambiente não é válido. Favor corrigir o arquivo '$app_conf_dir/$app.conf'."
		branch_auto="echo \$branch_${ambiente}"
		branch_auto=$(eval "$branch_auto")

		git branch -a | grep -v remotes/origin/HEAD | cut -b 3- > $tmp_dir/branches

		if [ $(grep -Ei "^remotes/origin/${branch_auto}$" $tmp_dir/branches | wc -l) -ne 1 ]; then
			end 1
		fi

		ultimo_commit=''

		case $revisao_auto in
			tag)
				git log "origin/$branch_auto" --oneline | cut -f1 -d ' ' > $tmp_dir/commits
				git tag -l | sort -V > $tmp_dir/tags

				while read tag; do

					commit_tag=$(git log "$tag" --oneline | head -1 | cut -f1 -d ' ')
					if [ $(grep -Ex "^${commit_tag}$" $tmp_dir/commits | wc -l) -eq 1 ]; then
						ultimo_commit=$commit_tag
						ultima_tag=$tag
					fi

				done < $tmp_dir/tags

				if [ ! -z $ultimo_commit ] && [ ! -z $ultima_tag ]; then
					echo -e "\nObtendo a revisão $ultimo_commit a partir da tag $ultima_tag."
					rev=$ultima_tag
					git checkout --force --quiet $ultima_tag || end 1
				else
					echo "Erro ao obter a revisão especificada. Deploy abortado"
					end 1
				fi
				;;
			commit)
				ultimo_commit=$(git log "origin/$branch_auto" --oneline | head -1 | cut -f1 -d ' ')

				if [ ! -z $ultimo_commit ]; then
					echo -e "\nObtendo a revisão $ultimo_commit a partir da branch $branch_auto."
					rev=$ultimo_commit
					git checkout --force --quiet $ultimo_commit || end 1
				else
					echo "Erro ao obter a revisão especificada. Deploy abortado"
					end 1
				fi
				;;
		esac
	else
		echo -e "\nObtendo a revisão ${rev}..."
		git checkout --force --quiet $rev || end 1
	fi

	if [ -z "$(git branch | grep -x '* (no branch)' )" ]; then
		echo -e "\nDeploys a partir do nome de uma branch são proibidos, pois prejudicam a rastreabilidade do processo. Deploy abortado"
		end 1
	fi

	cd - &> /dev/null
}


function check_downgrade () {

	### alerta downgrade ###

	cd $origem

	downgrade=false

	git tag > $tmp_dir/git_tag_app
	git log --decorate=full | grep -E "^commit" | sed -r "s|^commit ||" | sed -r "s| .*refs/tags/|\.\.|" | sed -r "s| .*$||" | sed -r "s|([a-f0-9]+\.\..*).$|\1|" > $tmp_dir/git_log_app

	ultimo_deploy_app=$(grep -Eix "^([^;]+;){6}$mensagem_sucesso.*$" ${app_history_dir}/$history_csv_file | grep -Eix "^([^;]+;){4}$ambiente.*$" | tail -1 | cut -d ';' -f4 2> /dev/null)

	if [ -n "$ultimo_deploy_app" ]; then

		local rev_check=$(echo $ultimo_deploy_app | sed -r "s|\.|\\\.|g")

		if [ $(grep -Ex "^$rev_check$" $tmp_dir/git_tag_app | wc -l) -eq 1 ]; then 				# a revisão é uma tag
			if [ $(grep -Ex "^[a-f0-9]+\.\.$rev_check$" $tmp_dir/git_log_app | wc -l) -eq 0 ]; then	# a tag é posterior à revisão para a qual foi solicitado o deploy
				downgrade=true
			fi
		else 													# a revisão é um hash
			if [ $(grep -Ex "^$rev_check.*" $tmp_dir/git_log_app | wc -l) -eq 0 ]; then			# o hash é posterior à revisão para a qual foi solicitado o deploy
				downgrade=true
			fi
		fi

		if $downgrade; then
			paint 'bg' 'red' && paint 'fg' 'black'
			echo -e "\nAVISO! Foi detectado um deploy anterior de uma revisão mais recente: $ultimo_deploy_app"
			paint 'default'
		fi
	fi

	cd - &> /dev/null

}

function clean_temp () {										#cria pasta temporária, remove arquivos e pontos de montagem temporários

	if [ -d $tmp_dir ]; then

		if [ -f "$tmp_dir/destino_mnt" ]; then
			cat $tmp_dir/destino_mnt | xargs --no-run-if-empty umount 2> /dev/null
			wait
			cat $tmp_dir/destino_mnt | xargs --no-run-if-empty rmdir 2> /dev/null			#já desmontados, os pontos de montagem temporários podem ser apagados.i
		fi

		rm -f $tmp_dir/*
		rmdir $tmp_dir
	fi
}

function lock () {											#argumentos: nome_trava, mensagem_erro, (instrução)

	if [ ! -z "$1" ] && [ ! -z "$2" ]; then
		if [ -d $tmp_dir ] && [ -d $lock_dir ]; then
			if [ ! -f $tmp_dir/locks ]; then
				touch $tmp_dir/locks
			fi
			if [ -f $lock_dir/$1 ]; then
				echo -e "\n$2" && end 0
			else
				touch $lock_dir/$1 && echo "$lock_dir/$1" >> $tmp_dir/locks
			fi
		else
			end 1
		fi
	else
		end 1
	fi

}

function clean_locks () {

	if [ -d $lock_dir ] && [ -f "$tmp_dir/locks" ]; then
		cat $tmp_dir/locks | xargs --no-run-if-empty rm -f					#remove locks
	fi

	if [ "$edit_log" == "1" ]; then
		rm -f ${lock_dir}/$history_lock_file
	fi

}

function editconf () {

	if [ ! -z "$1" ] && [ ! -z "$2" ] && [ ! -z "$3" ] && [ ! -z "$edit_var" ]; then
        	campo="$1"
        	valor_campo="$2"
        	arquivo_conf="$3"

        	touch $arquivo_conf

        	if [ $(grep -Ex "^$campo\=.*$" $arquivo_conf | wc -l) -ne 1 ]; then
				sed -i -r "/^$campo\=.*$/d" "$arquivo_conf"
				echo "$campo='$valor_campo'" >> "$arquivo_conf"
        	else
				test "$edit_var" -eq 1 && sed -i -r "s|^($campo\=).*$|\1\'$valor_campo\'|" "$arquivo_conf"
        	fi
	else
		echo "Erro. Não foi possível editar o arquivo de configuração." && end 1
	fi

}

function mklist () {

	if [ ! -z "$1" ] && [ ! -z "$2" ]; then
		lista=$(echo "$1" | sed -r 's/,/ /g' | sed -r 's/;/ /g' | sed -r 's/ +/ /g' | sed -r 's/ $//g' | sed -r 's/^ //g' | sed -r 's/ /\n/g')
		echo "$lista" > $2
	else
		end 1
	fi

}

function end () {

	trap "" SIGQUIT SIGTERM SIGINT SIGHUP
	paint 'default'

	erro=$1
	qtd_rollback=0

	if [ -z "$erro" ]; then
		erro=0
	elif [ $(echo "$erro" | grep -Ex "^[01]$" | wc -l) -ne 1 ]; then
		erro=1
	fi

	wait

	if [ "$erro" -eq 1 ] && [ -f "$deploy_log_dir/progresso_$host.txt" ]; then

		paint 'fg' 'yellow'

		echo -e "\nDeploy abortado."

		if [ "$rev" == "rollback" ]; then
			echo -e "\nErro: rollback interrompido. Favor reexecutar o script."
			write_history "Rollback não efetuado. O script deve ser reexecutado."
		else
			host_erro="$host"

			if [ "$estado" == 'backup' ] || [ "$estado" == 'fim_backup' ]; then

				bak="$bak_dir/${app}_${host}"							# necessário garantir que a variável bak esteja setada, pois o script pode ter sido interrompido antes dessa etapa.
				rm -Rf $bak
				write_history "Deploy abortado."

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

				rsync_cmd="rsync $rsync_opts $bak/ $destino/"
				eval $rsync_cmd && ((qtd_rollback++)) && rm -Rf $bak

				echo "fim_rollback" >> $deploy_log_dir/progresso_$host.txt
				write_history "Deploy interrompido. Backup restaurado."

			else
				write_history "Deploy abortado."
			fi

			echo "deploy_abortado" >> $deploy_log_dir/progresso_$host.txt

			cp $tmp_dir/dir_destino $tmp_dir/destino						#foi necessário utilizar uma cópia do arquivo, uma vez que este foi utilizado como entrada padrão para o loop de deploy.

			while read destino_deploy; do

				host=$(echo $destino_deploy | sed -r "s|^//([^/]+)/.+$|\1|")

				if [ ! "$host" == "$host_erro" ]; then

					if [ -f "$deploy_log_dir/progresso_$host.txt" ]; then			# Indica que o processo de deploy já foi iniciado no host

						estado_host=$(tail -1 "$deploy_log_dir/progresso_$host.txt")

						if [ "$estado_host" == "fim_escrita" ]; then			# Deploy já concluído no host. Rollback necessário.

							bak="$bak_dir/${app}_${host}"
							destino="/mnt/deploy_${app}_${host}"

							echo -e "\nRevertendo alterações no host $host..."
							echo $host >> $tmp_dir/hosts_rollback

							echo "rollback" >> $deploy_log_dir/progresso_$host.txt

							rsync_cmd="rsync $rsync_opts $bak/ $destino/"
							eval $rsync_cmd && ((qtd_rollback++)) && rm -Rf $bak

							echo "fim_rollback" >> $deploy_log_dir/progresso_$host.txt
							write_history "Rollback realizado devido a erro ou deploy cancelado em $host_erro."

						fi
					else
						write_history "Deploy abortado."
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

		mv "$deploy_log_dir" "${deploy_log_dir}_PENDENTE"

	fi

	wait
	sleep 1

	clean_locks
	clean_temp

	paint 'default'

	exit $erro
}

#### Inicialização #####

if [ "$rev" == "rollback" ]; then
	trap "" SIGQUIT SIGTERM SIGINT SIGHUP						# um rollback não deve ser interrompido pelo usuário.
else
	trap "end 1; exit" SIGQUIT SIGTERM SIGINT SIGHUP				#a função será chamada quando o script for finalizado ou interrompido.
fi

edit_var=0

if $interactive; then
	clear
fi

find_install_dir

if [ ! -f "$install_dir/conf/global.conf" ]; then
	echo 'Arquivo global.conf não encontrado.'
	exit 1
fi

chk_template $install_dir/conf/global.conf
source "$install_dir/conf/global.conf" || exit 1						#carrega o arquivo de constantes.

if [ -f "$install_dir/conf/user.conf" ]; then
	chk_template $install_dir/conf/user.conf
	source "$install_dir/conf/user.conf" || exit 1
fi

tmp_dir="$work_dir/$pid"

if [ -z "$regex_tmp_dir" ] \
	|| [ -z "$regex_tmp_dir" ] \
	|| [ -z "$regex_history_dir" ] \
	|| [ -z "$regex_repo_dir" ] \
	|| [ -z "$regex_lock_dir" ] \
	|| [ -z "$regex_bak_dir" ] \
	|| [ -z "$regex_html_dir" ] \
	|| [ -z "$regex_app" ] \
	|| [ -z "$regex_rev" ] \
	|| [ -z "$regex_chamado" ] \
	|| [ -z "$regex_modo" ] \
	|| [ -z "$regex_repo" ] \
	|| [ -z "$regex_raiz" ] \
	|| [ -z "$regex_dir_destino" ] \
	|| [ -z "$regex_auth" ] \
	|| [ -z "$regex_qtd" ] \
	|| [ -z "$mensagem_sucesso" ] \
	|| [ -z "$modo_padrao" ] \
	|| [ -z "$rsync_opts" ] \
	|| [ -z "$ambientes" ] \
	|| [ -z "$interactive" ];
then
	echo 'Favor preencher corretamente o arquivo global.conf / user.conf e tentar novamente.'
	exit 1
fi

aux=$interactive
valid "bak_dir" "\nErro. Diretório de backup informado incorretamente."
valid "html_dir" "\nErro. Diretório de html informado incorretamente."
valid "tmp_dir" "\nErro. Diretório temporário informado incorretamente."
valid "history_dir" "\nErro. Diretório de histórico informado incorretamente."
valid "repo_dir" "\nErro. Diretório de repositórios git informado incorretamente."
valid "lock_dir" "\nErro. Diretório de lockfiles informado incorretamente."
valid "app_history_size" "regex_qtd" "\nErro. Tamanho inválido para o histórico de aplicações."
valid "global_history_size" "regex_qtd" "\nErro. Tamanho inválido para o histórico global."
valid "history_html_size" "regex_qtd" "\nErro. Tamanho inválido para o histórico em HTML."
interactive=$aux

mkdir -p $install_dir $work_dir $history_dir ${app_history_dir_tree} $repo_dir $lock_dir $app_conf_dir $bak_dir	$tmp_dir		#cria os diretórios necessários, caso não existam.

mklist "$ambientes" "$tmp_dir/ambientes"

#### Validação do input do usuário ######

echo "Iniciando processo de deploy..."

if $interactive; then
	valid "app" "\nInforme o nome do sistema corretamente (somente letras minúsculas)."
	valid "rev" "\nInforme a revisão corretamente."

	if [ "$rev" == "auto" ]; then
		echo "Erro. Não é permitido o deploy automático em modo interativo."
		exit 1
	fi

	valid "ambiente" "\nInforme o ambiente corretamente."
else
	valid "app" "\nErro. Nome do sistema informado incorratemente."
	valid "rev" "\nErro. Revisão/tag/branch informada incorretamente."

	if [ "$rev" == "rollback" ]; then
		echo "Erro. A realição do rollback deve ser feita no modo interativo."
		exit 1
	fi

	valid "ambiente" "\n.Erro. Ambiente informado incorretamente."
fi

#### Verifica deploys simultâneos e cria lockfiles, conforme necessário ########

lock $app "Deploy abortado: há outro deploy da aplicação $app em curso."

if $interactive; then

	if [ ! -f "${app_conf_dir}/${app}.conf" ]; then					#caso não haja registro referente ao sistema ou haja entradas duplicadas.

		echo -e "\nFavor informar abaixo os parâmetros da aplicação $app."

		echo -e "\nInforme o repositorio a ser utilizado."
		read -p "repo: " -e -r repo
		valid "repo" "\nErro. Informe um caminho válido para o repositório GIT."

		echo -e "\nInforme o caminho para a raiz da aplicação."
		read -p "raiz: " -e -r raiz											#utilizar a opção -r para permitir a leitura de contrabarras.
		valid "raiz" "\nErro. Informe um caminho válido para a raiz da aplicação (substituir '\\' por '/', quando necessário)."

		echo -e "\nInforme os hosts para deploy da aplicação $app no ambiente de $ambiente (separados por espaço ou vírgula)."
		read -p "hosts_$ambiente: " -e -r hosts_$ambiente
		valid "hosts_$ambiente" "\nErro. Informe uma lista válida de hosts para deploy, separando-os por espaço ou vírgula."

		echo -e "\nInforme o diretório compartilhado para deploy (deve ser o mesmo em todos os hosts)."
		read -p "share: " -e -r share
		valid "share" "\nErro. Informe um diretório válido, suprimindo o nome do host (Ex: //host/a\$/b/c => a\$/b/c )."

		echo -e "\nInforme o protocolo de segurança do compartilhamento."
		read -p "auth: " -e -r auth
		valid "auth" "\nErro. Informe um protocolo válido: krb5(i), ntlm(i), ntlmv2(i), ntlmssp(i)."

		if [ -z $modo ]; then
			echo -e "\nInforme um modo de deploy para o ambiente $ambiente ('d': deletar arquivos obsoletos / 'p': preservar arquivos obsoletos):"
			read -p "modo_$ambiente: " -e -r modo_$ambiente
			valid "modo_$ambiente" "\nErro. Informe um modo de deploy válido para o ambiente $ambiente: p/d"
		else
			modo_$ambiente=$modo
		fi

		editconf "app" "$app" "$app_conf_dir/${app}.conf"
		editconf "repo" "$repo" "$app_conf_dir/${app}.conf"
		editconf "raiz" "$raiz" "$app_conf_dir/${app}.conf"

		while read env; do
			if [ "$env" == "$ambiente"  ]; then
				lista_hosts="echo \$hosts_${env}"
				lista_hosts=$(eval "$lista_hosts")

				modo="echo \$modo_${env}"
				modo=$(eval "$modo")

				editconf "hosts_$env" "$lista_hosts" "$app_conf_dir/${app}.conf"
				editconf "modo_$env" "$modo" "$app_conf_dir/${app}.conf"

				echo "revisao_$env=''" >> "$app_conf_dir/${app}.conf"
				echo "branch_$env=''" >> "$app_conf_dir/${app}.conf"
				echo "modo_$env=''" >> "$app_conf_dir/${app}.conf"
				echo "auto_$env='0'" >> "$app_conf_dir/${app}.conf"

			else
				echo "hosts_$env=''" >> "$app_conf_dir/${app}.conf"
				echo "revisao_$env=''" >> "$app_conf_dir/${app}.conf"
				echo "branch_$env=''" >> "$app_conf_dir/${app}.conf"
				echo "modo_$env=''" >> "$app_conf_dir/${app}.conf"
				echo "auto_$env='0'" >> "$app_conf_dir/${app}.conf"
			fi
		done < $tmp_dir/ambientes

		editconf "share" "$share" "$app_conf_dir/${app}.conf"
		editconf "auth" "$auth" "$app_conf_dir/${app}.conf"

		sort "$app_conf_dir/${app}.conf" -o "$app_conf_dir/${app}.conf"

	else

		echo -e "\nObtendo parâmetros da aplicação $app..."
		chk_template "${app_conf_dir}/${app}.conf" "app" "continue"

		if [ "$?" -eq "0" ]; then
	        source "${app_conf_dir}/${app}.conf"
		else
			echo ""
			read -p "Remover as entradas inválidas acima? (s/n): " -e -r ans

			if [ "$ans" == "s" ] || [ "$ans" == "S" ]; then
				grep --file="$install_dir/template/app.template" "${app_conf_dir}/${app}.conf" > "$tmp_dir/app_conf_new"
				cp -f "$tmp_dir/app_conf_new" "${app_conf_dir}/${app}.conf"
				echo -e "\nArquivo ${app}.conf alterado."
				source "${app_conf_dir}/${app}.conf"
			else
				end 1
			fi
		fi

		valid "repo" "\nErro. Informe um caminho válido para o repositório GIT:"
		editconf "repo" "$repo" "$app_conf_dir/${app}.conf"

		valid "raiz" "\nErro. Informe um caminho válido para a raiz da aplicação:"
		editconf "raiz" "$raiz" "$app_conf_dir/${app}.conf"

		valid "hosts_$ambiente" "\nErro. Informe uma lista válida de hosts para deploy, separando-os por espaço ou vírgula:"
		lista_hosts="echo \$hosts_${ambiente}"
		lista_hosts=$(eval "$lista_hosts")
		editconf "hosts_$ambiente" "$lista_hosts" "$app_conf_dir/${app}.conf"

		valid "modo_$ambiente" "\nErro. Informe um modo válido para deploy no ambiente $ambiente [p/d]:"
	        modo_app="echo \$modo_${ambiente}"
	        modo_app=$(eval "$modo_app")
		editconf "modo_$ambiente" "$modo_app" "$app_conf_dir/${app}.conf"

		valid "share" "\nErro. Informe um diretório válido, suprimindo o nome do host (Ex: //host/a\$/b/c => a\$/b/c ):"
		editconf "share" "$share" "$app_conf_dir/${app}.conf"

		valid "auth" "\nErro. Informe um protocolo válido: krb5(i), ntlm(i), ntlmv2(i), ntlmssp(i):"
		editconf "auth" "$auth" "$app_conf_dir/${app}.conf"

		sort "$app_conf_dir/${app}.conf" -o "$app_conf_dir/${app}.conf"
	fi
else
	if [ ! -f "${app_conf_dir}/${app}.conf" ]; then
		echo "Erro. Não foram encontrados os parâmetros para deploy da aplicação $app. O script deverá ser reexecutado no modo interativo."
	else

		chk_template "${app_conf_dir}/${app}.conf" "app"
    	source "${app_conf_dir}/${app}.conf"

	    valid "repo" "\nErro. \'$repo\' não é um repositório git válido."
	    valid "raiz" "\nErro. \'$repo\' não é um caminho válido para a raiz da aplicação $app."
	    valid "hosts_$ambiente" "\nErro. A lista de hosts para o ambiente $ambiente não é válida."
		valid "auto_$ambiente" "\nErro. Não foi possível ler a flag de deploy automático."
		valid "modo_$ambiente" "\nErro. Foi informado um modo inválido para deploy no ambiente $ambiente."
	    valid "share" "\nErro. \'$share\' não é um diretório compartilhado válido."
		valid "auth" "\nErro. \'$auth\' não é protocolo de segurança válido: krb5(i), ntlm(i), ntlmv2(i), ntlmssp(i):"

	    lista_hosts="echo \$hosts_${ambiente}"
	    lista_hosts=$(eval "$lista_hosts")

	    auto="echo \$auto_${ambiente}"
	    auto=$(eval "$auto")

	    modo_app="echo \$modo_${ambiente}"
	    modo_app=$(eval "$modo_app")

		if [ "$rev" == "auto" ]; then
			if [ "$auto" == "1" ]; then
				automatico="true"
			else
				echo "Erro. O deploy automático está desabilitado para a aplicação $app."
				end 1
			fi
		else
			automatico="false"
		fi
	fi
fi

nomerepo=$(echo $repo | sed -r "s|^.*/([^/]+)\.git$|\1|")
lock "${nomerepo}_git" "Deploy abortado: há outro deploy utilizando o repositório $repo."

mklist "$lista_hosts" $tmp_dir/hosts_$ambiente

while read host; do
	dir_destino="//$host/$share"
	dir_destino=$(echo "$dir_destino" | sed -r "s|^(//.+)//(.*$)|\1/\2|g" | sed -r "s|/$||")
	nomedestino=$(echo $dir_destino | sed -r "s|/|_|g")
	lock $nomedestino "Deploy abortado: há outro deploy utilizando o diretório $dir_destino."
	echo "$dir_destino" >> $tmp_dir/dir_destino
done < $tmp_dir/hosts_$ambiente

##### EXPURGO DE LOGS #######

app_history_dir="${app_history_dir_tree}/${app}"

mkdir -p "${app_history_dir}/"
find "${app_history_dir}/" -maxdepth 1 -type d | grep -vx "${app_history_dir}/" | sort > $tmp_dir/logs_total
tail $tmp_dir/logs_total --lines=${history_html_size} > $tmp_dir/logs_ultimos
grep -vxF --file=$tmp_dir/logs_ultimos $tmp_dir/logs_total > $tmp_dir/logs_expurgo
cat $tmp_dir/logs_expurgo | xargs --no-run-if-empty rm -Rf

##### CRIAÇÃO DO DIRETÓRIO DE LOG #####

data_deploy=$(date +%F_%Hh%Mm%Ss)
id_deploy=$(echo ${data_deploy}_${rev}_${ambiente} | sed -r "s|/|_|g")
deploy_log_dir="${app_history_dir}/${id_deploy}"								#Diretório onde serão armazenados os logs do atendimento.

if [ -d "${deploy_log_dir}_PENDENTE" ]; then
	rm -f ${deploy_log_dir}_PENDENTE/*
	rmdir ${deploy_log_dir}_PENDENTE
fi

mkdir -p $deploy_log_dir

echo -e "\nSistema:\t$app"
echo -e "Revisão:\t$rev"

##### MODO DE DEPLOY #####

if [ -z "$modo" ]; then
	if [ -z "$modo_app" ]; then
		modo=$modo_padrao
	else
		modo=$modo_app
	fi
fi

if [ "$modo" == "d" ]; then
	rsync_opts="$rsync_opts --delete"
	obs_log="$mensagem_sucesso. arquivos obsoletos deletados."
else
	obs_log="$mensagem_sucesso. arquivos obsoletos preservados."
fi

##### GIT #########

if [ ! "$rev" == "rollback" ]; then

	echo -e "Repositório:\t$repo"
	echo -e "Caminho:\t$raiz"

	checkout												#ver checkout(): (git clone), cd <repositorio> , git fetch, git checkout...

	origem="$repo_dir/$nomerepo/$raiz"
	origem=$(echo "$origem" | sed -r "s|^(/.+)//(.*$)|\1/\2|g" | sed -r "s|/$||")

	if [ ! -d "$origem" ]; then
		echo -e "\nErro: não foi possível encontrar o caminho $origem.\nVerifique a revisão informada ou corrija o arquivo $app_conf_dir/$app.conf."
		end 1
	elif [ ! "$rev" == "auto" ]; then
		check_downgrade
	fi
fi

###### REGRAS DE DEPLOY: IGNORE / INCLUDE #######

echo '' > $tmp_dir/regras_deploy.txt

if [ "$rev" == "rollback" ] && [ -f "${bak_dir}/regras_deploy_${app}_${ambiente}.txt" ]; then

	cat "${bak_dir}/regras_deploy_${app}_${ambiente}.txt" >> $tmp_dir/regras_deploy.txt

elif [ -f "$repo_dir/$nomerepo/.gitignore" ]; then

	dos2unix -n $repo_dir/$nomerepo/.gitignore $tmp_dir/gitignore_unix > /dev/null 2>&1				# garante que o arquivo .gitignore seja interpretado corretamente. (converte CRLF em LF)

	grep -Ev "^$|^ |^#" $tmp_dir/gitignore_unix >> $tmp_dir/regras_deploy.txt

	if [ ! "$raiz" == "/" ]; then

		raiz_git=$(echo "$raiz" | sed -r "s|^/||" | sed -r "s|/$||")

		sed -i -r "s|^(! +)?/$raiz_git(/.+)|\1\2|" $tmp_dir/regras_deploy.txt					#padrões de caminho iniciados com / são substituídos.
		sed -i -r "s|^(! +)?($raiz_git)(/.+)|\1\2\3\n\1\3|" $tmp_dir/regras_deploy.txt				#entradas iniciados sem / são preservadas. Uma linha com a substituição correspondente é acrescentada logo abaixo.

	fi

	sed -i -r "s|^(! +)|+ |" $tmp_dir/regras_deploy.txt								#um sinal de + (include) é acrescentado ao início das entradas precedidas de "!"
	sed -i -r "s|^([^+])|- \1|" $tmp_dir/regras_deploy.txt								#um sinal de - (exclude) é acrescentado ao início das demais entradas.

fi

cp $tmp_dir/regras_deploy.txt $deploy_log_dir/										#a fim de proporcionar transparência ao processo de deploy, as regras de ignore/include são copiadas para o log.

bkp_regras=0														#a flag será alterada tão logo as regras de deploy sejam copiadas para a pasta de backup.
rsync_opts="$rsync_opts --filter='. $tmp_dir/regras_deploy.txt'"

echo $estado > $tmp_dir/progresso.txt
estado="fim_$estado" && echo $estado >> $tmp_dir/progresso.txt

### início da leitura ###

while read dir_destino; do

	host=$(echo $dir_destino | sed -r "s|^//([^/]+)/.+$|\1|")

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

	##### CRIA PONTO DE MONTAGEM TEMPORÁRIO E DIRETÓRIO DO CHAMADO #####

	destino="/mnt/deploy_${app}_${host}"
	echo $destino >> $tmp_dir/destino_mnt

	mkdir $destino || end 1

	mount -t cifs $dir_destino $destino -o credentials=$credenciais,sec=$auth || end 1 		#montagem do compartilhamento de destino (requer módulo anatel_ad, provisionado pelo puppet)

	##### DIFF ARQUIVOS #####

	rsync_cmd="rsync --dry-run --itemize-changes $rsync_opts $origem/ $destino/ > $deploy_log_dir/modificacoes_$host.txt"
	eval $rsync_cmd || end 1

	##### RESUMO DAS MUDANÇAS ######

	adicionados="$(grep -E "^>f\+" $deploy_log_dir/modificacoes_$host.txt | wc -l)"
	excluidos="$(grep -E "^\*deleting .*[^/]$" $deploy_log_dir/modificacoes_$host.txt | wc -l)"
	modificados="$(grep -E "^>f[^\+]" $deploy_log_dir/modificacoes_$host.txt | wc -l)"
	dir_criado="$(grep -E "^cd\+" $deploy_log_dir/modificacoes_$host.txt | wc -l)"
	dir_removido="$(grep -E "^\*deleting .*/$" $deploy_log_dir/modificacoes_$host.txt | wc -l)"

	total_arq=$(( $adicionados + $excluidos + $modificados ))
	total_dir=$(( $dir_criado + $dir_removido ))
	total_del=$(( $excluidos + dir_removido ))

	echo -e "Log das modificacoes gravado no arquivo modificacoes_$host.txt\n" > $deploy_log_dir/resumo_$host.txt
	echo -e "Arquivos adicionados ............... $adicionados " >> $deploy_log_dir/resumo_$host.txt
	echo -e "Arquivos excluidos ................. $excluidos" >> $deploy_log_dir/resumo_$host.txt
	echo -e "Arquivos modificados ............... $modificados" >> $deploy_log_dir/resumo_$host.txt
	echo -e "Diretórios criados ................. $dir_criado" >> $deploy_log_dir/resumo_$host.txt
	echo -e "Diretórios removidos ............... $dir_removido" >> $deploy_log_dir/resumo_$host.txt
	echo -e "" >> $deploy_log_dir/resumo_$host.txt
	echo -e "Total de operações de arquivos ..... $total_arq" >> $deploy_log_dir/resumo_$host.txt
	echo -e "Total de operações de diretórios ... $total_dir" >> $deploy_log_dir/resumo_$host.txt
	echo -e "Total de operações de exclusão ..... $total_del" >> $deploy_log_dir/resumo_$host.txt

	echo ""
	cat $deploy_log_dir/resumo_$host.txt

	estado="fim_$estado" && echo $estado >> $deploy_log_dir/progresso_$host.txt

	if [ $(( $adicionados + $excluidos + $modificados + $dir_criado + $dir_removido )) -ne 0 ]; then			# O deploy somente será realizado quando a quantidade de modificações for maior que 0.

		###### ESCRITA DAS MUDANÇAS EM DISCO ######

		if $interactive; then
			echo ""
			read -p "Gravar mudanças em disco? (s/n): " -e -r ans </dev/tty
		fi

		if [ "$ans" == 's' ] || [ "$ans" == 'S' ] || [ "$interactive" == "false" ]; then

			if [ ! "$rev" == "rollback" ]; then

				#### preparação do backup ####

				estado="backup" && echo $estado >> $deploy_log_dir/progresso_$host.txt
				echo -e "\nCriando backup"

				bak="$bak_dir/${app}_${host}"
		       		rm -Rf $bak
				mkdir -p $bak

				rsync_cmd="rsync $rsync_opts $destino/ $bak/"
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

			rsync_cmd="rsync $rsync_opts $origem/ $destino/"
			eval $rsync_cmd 2> $deploy_log_dir/rsync_$host.log || end 1

			write_history "$obs_log"

			estado="fim_$estado" && echo $estado >> $deploy_log_dir/progresso_$host.txt
   		else
			end 1
		fi
	else
		echo -e "\nNão há arquivos a serem modificados no host $host."
	fi

done < $tmp_dir/dir_destino

paint 'fg' 'green'
echo "$mensagem_sucesso"

end 0
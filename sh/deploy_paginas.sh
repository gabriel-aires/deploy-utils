#!/bin/bash

estado="validacao"
pid=$$
interativo="true"
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
			interativo="false"
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

function paint () {

	local color

	case $2 in
		black)		color=0;;
		red)		color=1;;
		green)		color=2;;
		yellow)		color=3;;
		blue)		color=4;;
		magenta)	color=5;;
		cyan)		color=6;;
		white)		color=7;;
	esac
	
	case $1 in
		fg)		tput setaf $color;;
		bg)		tput setab $color;;
		default)	tput sgr0;;
	esac	

}

function install_dir () {										##### Determina o diretório de instalação do script ####

	if [ -L $0 ]; then
		caminho_script=$(dirname $(readlink $0))
	else
		caminho_script=$(dirname $BASH_SOURCE)
	fi
	
	if [ -z $(echo $caminho_script | grep -Ex "^/.*$") ]; then 					#caminho é relativo
		
		if [ "$caminho_script" == "." ]; then
			caminho_script="$(pwd)"
		else
			caminho_script="$(pwd)/$caminho_script"
	
			while [ $(echo "$caminho_script" | grep -E "/\./" | wc -l) -ne 0 ]; do   	#substitui /./ por /
				caminho_script=$(echo "$caminho_script" | sed -r "s|/\./|/|")
			done
	
			while [ $(echo "$caminho_script" | grep -E "/\.\./" | wc -l) -ne 0 ]; do   	#corrige a string caso o script tenha sido chamado a partir de um subdiretório
				caminho_script=$(echo "$caminho_script" | sed -r "s|[^/]+/\.\./||")
			done
		fi
	fi
	
	diretorio_instalacao=$(dirname $caminho_script)

}

function checkout () {											# o comando cd precisa estar encapsulado para funcionar adequadamente num script, por isso foi criada a função.

	if [ ! -d "$repo_dir/$nomerepo/.git" ]; then
		echo " "
		git clone --progress "$repo" "$repo_dir/$nomerepo" || end 1				#clona o repositório, caso ainda não tenha sido feito.
	fi

	cd "$repo_dir/$nomerepo"
	git fetch --all --force --quiet || end 1

	if $automatico; then
		
		valid "revisao_$ambiente" "\nErro. O valor obtido para o parâmetro revisao_$ambiente não é válido. Favor corrigir o arquivo '$parametros_app/$app.conf'."
		revisao_auto="echo \$revisao_${ambiente}"
		revisao_auto=$(eval "$revisao_auto")

		valid "branch_$ambiente" "\nErro. O valor obtido para o parâmetro branch_$ambiente não é válido. Favor corrigir o arquivo '$parametros_app/$app.conf'."
		branch_auto="echo \$branch_${ambiente}"
		branch_auto=$(eval "$branch_auto")

		git branch -a | grep -v remotes/origin/HEAD | cut -b 3- > $temp_dir/branches

		if [ $(grep -Ei "^remotes/origin/${branch_auto}$" $temp_dir/branches | wc -l) -ne 1 ]; then
			end 1
		fi

		ultimo_commit=''

		case $revisao_auto in
			tag)
				git log "origin/$branch_auto" --oneline | cut -f1 -d ' ' > $temp_dir/commits
				git tag -l | sort -V > $temp_dir/tags

				while read tag; do
					
					commit_tag=$(git log "$tag" --oneline | head -1 | cut -f1 -d ' ')
					if [ $(grep -Ex "^${commit_tag}$" $temp_dir/commits | wc -l) -eq 1 ]; then
						ultimo_commit=$commit_tag
						ultima_tag=$tag
					fi

				done < $temp_dir/tags
				
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
	
	git tag > $temp_dir/git_tag_app
	git log --decorate=full | grep -E "^commit" | sed -r "s|^commit ||" | sed -r "s| .*refs/tags/|\.\.|" | sed -r "s| .*$||" | sed -r "s|([a-f0-9]+\.\..*).$|\1|" > $temp_dir/git_log_app

	ultimo_deploy_app=$(grep -Eix "^([^;]+;){6}$mensagem_sucesso.*$" ${historico_app}/deploy_log.csv | grep -Eix "^([^;]+;){4}$ambiente.*$" | tail -1 | cut -d ';' -f4 2> /dev/null)
	
	if [ -n "$ultimo_deploy_app" ]; then

		local rev_check=$(echo $ultimo_deploy_app | sed -r "s|\.|\\\.|g")
	
		if [ $(grep -Ex "^$rev_check$" $temp_dir/git_tag_app | wc -l) -eq 1 ]; then 				# a revisão é uma tag
			if [ $(grep -Ex "^[a-f0-9]+\.\.$rev_check$" $temp_dir/git_log_app | wc -l) -eq 0 ]; then	# a tag é posterior à revisão para a qual foi solicitado o deploy
				downgrade=true
			fi
		else 													# a revisão é um hash
			if [ $(grep -Ex "^$rev_check.*" $temp_dir/git_log_app | wc -l) -eq 0 ]; then			# o hash é posterior à revisão para a qual foi solicitado o deploy
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
	
	if [ ! -z $temp_dir ]; then

		mkdir -p $temp_dir
	
		if [ -f "$temp_dir/destino_mnt" ]; then
			cat $temp_dir/destino_mnt | xargs --no-run-if-empty umount 2> /dev/null
			wait
			cat $temp_dir/destino_mnt | xargs --no-run-if-empty rmdir 2> /dev/null			#já desmontados, os pontos de montagem temporários podem ser apagados.i
		fi

		rm -f $temp_dir/*
		rmdir $temp_dir
	else
		end 1
	fi
}

function lock () {											#argumentos: nome_trava, mensagem_erro, (instrução)

	if [ ! -z "$1" ] && [ ! -z "$2" ]; then
		if [ -d $temp_dir ] && [ -d $lock_dir ]; then
			if [ ! -f $temp_dir/locks ]; then
				touch $temp_dir/locks
			fi
			if [ -f $lock_dir/$1 ]; then
				echo -e "\n$2" && end 0
			else
				touch $lock_dir/$1 && echo "$lock_dir/$1" >> $temp_dir/locks
			fi
		else
			end 1
		fi
	else
		end 1
	fi

}

function clean_locks () {

	if [ -d $lock_dir ] && [ -f "$temp_dir/locks" ]; then
		cat $temp_dir/locks | xargs --no-run-if-empty rm -f					#remove locks
	fi

}


function valid () {	#requer os argumentos nome_variável e mensagem, nessa ordem.

	if [ ! -z "$1" ] && [ ! -z "$2" ] && [ ! -z $edit ]; then

		paint 'fg' 'yellow'

		var="$1"
		msg="$2"
		edit=0

		valor="echo \$${var}"
		valor="$(eval $valor)"

		regra="echo \$regex_${var}"	
		regra="$(eval $regra)"

		regra_inversa="echo \$not_regex_${var}"
		regra_inversa="$(eval ${regra_inversa})"

		if [ -z "$regra" ]; then
			echo "Erro. Não há uma regra para validação da variável $var" && end 1
		elif "$interativo"; then
			while [ $(echo "$valor" | grep -Ex "$regra" | grep -Exv "${regra_inversa}" | wc -l) -eq 0 ]; do
				echo -e "$msg"
				read -p "$var: " -e -r $var
				edit=1
                		valor="echo \$${var}"
		                valor="$(eval $valor)"
			done
		elif [ $(echo "$valor" | grep -Ex "$regra" | grep -Exv "${regra_inversa}" | wc -l) -eq 0 ]; then
			echo -e "$msg" && end 1
		fi

		paint 'default'		

	else
		end 1
	fi

}

function editconf () {

	if [ ! -z "$1" ] && [ ! -z "$2" ] && [ ! -z "$3" ] && [ ! -z "$edit" ]; then
        	campo="$1"
        	valor_campo="$2"
        	arquivo_conf="$3"
            
        	touch $arquivo_conf

        	if [ $(grep -Ex "^$campo\=.*$" $arquivo_conf | wc -l) -ne 1 ]; then
			sed -i -r "/^$campo\=.*$/d" "$arquivo_conf"
			echo "$campo='$valor_campo'" >> "$arquivo_conf"
        	else
			test $edit -eq 1 && sed -i -r "s|^($campo\=).*$|\1\'$valor_campo\'|" "$arquivo_conf"
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

function html () {

	arquivo_entrada=$1
	arquivo_saida=$2

	tail --lines=$qtd_log_html $arquivo_entrada > $temp_dir/html_tr

	sed -i -r 's|^(.)|-\1|' $temp_dir/html_tr
	sed -i -r "s|^-(([^;]+;){6}$mensagem_sucesso.*)$|+\1|" $temp_dir/hmtl_tr
	sed -i -r 's|;$|</td></tr>|' $temp_dir/html_tr
	sed -i -r 's|;|</td><td>|g' $temp_dir/html_tr
	sed -i -r 's|^-|\t\t\t<tr style="@@html_tr_style_warning@@"><td>|' $temp_dir/html_tr
	sed -i -r 's|^+|\t\t\t<tr style="@@html_tr_style_default@@"><td>|' $temp_dir/html_tr
	
	cat $html_dir/begin.html > $temp_dir/html
	cat $temp_dir/html_tr >> $temp_dir/html
	cat $html_dir/end.html >> $temp_dir/html

	sed -i -r "s|@@html_title@@|$html_title|" $temp_dir/html
	sed -i -r "s|@@html_header@@|$html_header|" $temp_dir/html
	sed -i -r "s|@@html_table_style@@|$html_table_style|" $temp_dir/html
	sed -i -r "s|@@html_th_style@@|$html_th_style|" $temp_dir/html
	sed -i -r "s|@@html_tr_style_default@@|$html_tr_style_default|" $temp_dir/html
	sed -i -r "s|@@html_tr_style_warning@@|$html_tr_style_warning|" $temp_dir/html

	cp -f $temp_dir/html $arquivo_saida
}

function log () {
		
	##### LOG DE DEPLOY #####

	obs_log="$1"
	
	horario_log=$(echo $data_deploy | sed -r "s|^(....)-(..)-(..)_(.........)$|\3/\2/\1;\4|")
		
	if [ -z "$obs_log" ]; then
		
		if [ "$modo" == 'p' ]; then
			obs_log="$mensagem_sucesso. Arquivos obsoletos preservados."
		else
			obs_log="$mensagem_sucesso. arquivos obsoletos deletados."
		fi
	fi

	mensagem_log="$horario_log;$app;$rev;$ambiente;$host;$obs_log;"

	##### ABRE O ARQUIVO DE LOG PARA EDIÇÃO ######

	while [ -f "$lock_dir/deploy_log_edit" ]; do						#nesse caso, o processo de deploy não é interrompido. O script é liberado para escrever no log após a remoção do arquivo de trava.
		sleep 1	
	done

	touch $lock_dir/deploy_log_edit && echo "$lock_dir/deploy_log_edit" >> $temp_dir/locks

	touch $historico
	touch ${historico_app}/deploy_log.csv

	tail --lines=$qtd_log_deploy $historico > $temp_dir/deploy_log_novo
	tail --lines=$qtd_log_app ${historico_app}/deploy_log.csv > $temp_dir/app_log_novo

	echo -e "$mensagem_log" >> $temp_dir/deploy_log_novo
	echo -e "$mensagem_log" >> $temp_dir/app_log_novo	
	
	cp -f $temp_dir/app_log_novo $atividade_dir/deploy_log.csv
	cp -f $temp_dir/app_log_novo ${historico_app}/deploy_log.csv
	cp -f $temp_dir/deploy_log_novo $historico	

	html "$atividade_dir/deploy_log.csv" "$atividade_dir/deploy_log.html"
	html "$historico_app/deploy_log.csv" "$historico_app/deploy_log.html"
	html "$historico" "$historico_dir/deploy_log.html"

	rm -f $lock_dir/deploy_log_edit 							#remove a trava sobre o arquivo de log tão logo seja possível.

}

function end () {

	paint 'default'

	erro=$1
	qtd_rollback=0

	if [ -z "$erro" ]; then
		erro=0
	elif [ $(echo "$erro" | grep -Ex "^[01]$" | wc -l) -ne 1 ]; then
		erro=1
	fi
	
	wait

	if [ "$erro" -eq 1 ] && [ -f "$atividade_dir/progresso_$host.txt" ]; then

		paint 'fg' 'yellow'

		echo -e "\nDeploy abortado."

		if [ "$rev" == "rollback" ]; then
			echo -e "\nErro: rollback interrompido. Favor reexecutar o script."
			log "Rollback não efetuado. O script deve ser reexecutado."
		else
			host_erro="$host"

			if [ "$estado" == 'backup' ] || [ "$estado" == 'fim_backup' ]; then

				bak="$bak_dir/${app}_${host}"							# necessário garantir que a variável bak esteja setada, pois o script pode ter sido interrompido antes dessa etapa.
				rm -Rf $bak
				log "Deploy abortado."

			elif [ "$estado" == 'escrita' ]; then

				if [ -n $(grep -REil '^rsync: open \"[^\"]+\" failed: Permission denied' $atividade_dir/rsync_$host.log) ]; then
					grep -REi '^rsync: open \"[^\"]+\" failed: Permission denied' $atividade_dir/rsync_$host.log > $atividade_dir/permission_denied_$host.txt
					sed -i -r 's|^[^\"]+\"([^\"]+)\"[^\"]+$|\1:|' $atividade_dir/permission_denied_$host.txt
					sed -i -r "s|^$destino|$dir_destino|" $atividade_dir/permission_denied_$host.txt
					sed -i -r 's|/|\\|g' $atividade_dir/permission_denied_$host.txt                    
				fi

				echo -e "\nO script foi interrompido durante a escrita. Revertendo alterações no host $host..."
				echo $host >> $temp_dir/hosts_rollback
				
				echo "rollback" >> $atividade_dir/progresso_$host.txt
				
				rsync_cmd="rsync $rsync_opts $bak/ $destino/"
				eval $rsync_cmd && ((qtd_rollback++)) && rm -Rf $bak

				echo "fim_rollback" >> $atividade_dir/progresso_$host.txt
				log "Deploy interrompido. Backup restaurado."

			else
				log "Deploy abortado."		
			fi

			echo "deploy_abortado" >> $atividade_dir/progresso_$host.txt
			
			cp $temp_dir/dir_destino $temp_dir/destino						#foi necessário utilizar uma cópia do arquivo, uma vez que este foi utilizado como entrada padrão para o loop de deploy.

			while read destino_deploy; do

				host=$(echo $destino_deploy | sed -r "s|^//([^/]+)/.+$|\1|")

				if [ ! "$host" == "$host_erro" ]; then

					if [ -f "$atividade_dir/progresso_$host.txt" ]; then			# Indica que o processo de deploy já foi iniciado no host

						estado_host=$(tail -1 "$atividade_dir/progresso_$host.txt")
	
						if [ "$estado_host" == "fim_escrita" ]; then			# Deploy já concluído no host. Rollback necessário.
		
							bak="$bak_dir/${app}_${host}"
							destino="/mnt/deploy_${app}_${host}"

							echo -e "\nRevertendo alterações no host $host..."
							echo $host >> $temp_dir/hosts_rollback							

							echo "rollback" >> $atividade_dir/progresso_$host.txt
				
							rsync_cmd="rsync $rsync_opts $bak/ $destino/"
							eval $rsync_cmd && ((qtd_rollback++)) && rm -Rf $bak

							echo "fim_rollback" >> $atividade_dir/progresso_$host.txt
							log "Rollback realizado devido a erro ou deploy cancelado em $host_erro."		
	
						fi
					else
						log "Deploy abortado."
					fi
				fi		
			
			done < $temp_dir/destino

			if [ -f $temp_dir/hosts_rollback ]; then
				if [ "$qtd_rollback" -eq $(cat $temp_dir/hosts_rollback | wc -l) ]; then
					echo -e "\nRollback finalizado."
				else
					echo -e "\nErro. O rollback não foi concluído em todos os servidores do pool da aplicação $app."
				fi
			fi
		fi
		
		mv "$atividade_dir" "${atividade_dir}_PENDENTE"

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

edit=0

if $interativo; then
	clear
fi

install_dir

if [ -d "$diretorio_instalacao" ] && [ -f "$diretorio_instalacao/conf/global.conf" ]; then
	deploy_dir="$diretorio_instalacao"
elif [ -f '/opt/autodeploy-paginas/conf/global.conf' ]; then
	deploy_dir='/opt/autodeploy-paginas'						#local de instalação padrão
else
	echo 'Arquivo global.conf não encontrado.'
	exit 1
fi

if [ "$(grep -v --file=$deploy_dir/template/global.template $deploy_dir/conf/global.conf | wc -l)" -ne "0" ]; then
	echo 'O arquivo global.conf não atende ao template correspondente.'
	exit 1
fi

source "$deploy_dir/conf/global.conf" || exit 1						#carrega o arquivo de constantes.

if [ -f "$deploy_dir/conf/user.conf" ] && [ -f "$deploy_dir/conf/user.template" ]; then
	if [ "$(grep -v --file=$deploy_dir/template/user.template $deploy_dir/conf/user.conf | wc -l)" -ne "0" ]; then
		echo 'O arquivo user.conf não atende ao template correspondente.'
		exit 1
	else
		source "$deploy_dir/conf/user.conf" || exit 1
	fi
fi

temp_dir="$temp/$pid"

if [ -z "$regex_temp_dir" ] \
	|| [ -z "$regex_temp_dir" ] \
	|| [ -z "$regex_historico_dir" ] \
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
	|| [ -z $(echo $bak_dir | grep -E "$regex_bak_dir") ] \
	|| [ -z $(echo $html_dir | grep -E "$regex_html_dir") ] \
	|| [ -z $(echo $temp_dir | grep -E "$regex_temp_dir") ] \
	|| [ -z $(echo $historico_dir | grep -E "$regex_historico_dir") ] \
	|| [ -z $(echo $repo_dir | grep -E "$regex_repo_dir")  ] \
	|| [ -z $(echo $lock_dir | grep -E "$regex_lock_dir") ] \
	|| [ -z $(echo $qtd_log_app | grep -E "$regex_qtd") ] \
	|| [ -z $(echo $qtd_log_html | grep -E "$regex_qtd") ] \
	|| [ -z $(echo $qtd_log_deploy | grep -E "$regex_qtd") ] \
	|| [ -z "$mensagem_sucesso" ] \
	|| [ -z "$modo_padrao" ] \
	|| [ -z "$rsync_opts" ] \
	|| [ -z "$ambientes" ] \
	|| [ -z "$interativo" ];
then
	echo 'Favor preencher corretamente o arquivo global.conf / user.conf e tentar novamente.'
	exit 1
fi

mkdir -p $deploy_dir $temp $historico_dir $repo_dir $lock_dir $parametros_app $bak_dir			#cria os diretórios necessários, caso não existam.

if [ ! -e "$historico" ]; then										#cria arquivo de histórico, caso não exista.
	touch $historico	
fi

clean_temp && mkdir -p $temp_dir
mklist "$ambientes" "$temp_dir/ambientes"

#### Validação do input do usuário ###### 

echo "Iniciando processo de deploy..."

if $interativo; then
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

if $interativo; then

	if [ ! -f "${parametros_app}/${app}.conf" ]; then					#caso não haja registro referente ao sistema ou haja entradas duplicadas.
	
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

		editconf "app" "$app" "$parametros_app/${app}.conf"
		editconf "repo" "$repo" "$parametros_app/${app}.conf"
		editconf "raiz" "$raiz" "$parametros_app/${app}.conf"
		
		while read env; do
			if [ "$env" == "$ambiente"  ]; then
				lista_hosts="echo \$hosts_${env}"
				lista_hosts=$(eval "$lista_hosts")

				modo="echo \$modo_${env}"
				modo=$(eval "$modo")

				editconf "hosts_$env" "$lista_hosts" "$parametros_app/${app}.conf"
				editconf "modo_$env" "$modo" "$parametros_app/${app}.conf"

				echo "revisao_$env=''" >> "$parametros_app/${app}.conf"
				echo "branch_$env=''" >> "$parametros_app/${app}.conf"
				echo "modo_$env=''" >> "$parametros_app/${app}.conf"
				echo "auto_$env='0'" >> "$parametros_app/${app}.conf"

			else
				echo "hosts_$env=''" >> "$parametros_app/${app}.conf"
				echo "revisao_$env=''" >> "$parametros_app/${app}.conf"
				echo "branch_$env=''" >> "$parametros_app/${app}.conf"
				echo "modo_$env=''" >> "$parametros_app/${app}.conf"
				echo "auto_$env='0'" >> "$parametros_app/${app}.conf"
			fi
		done < $temp_dir/ambientes 

		editconf "share" "$share" "$parametros_app/${app}.conf"
		editconf "auth" "$auth" "$parametros_app/${app}.conf"		

		sort "$parametros_app/${app}.conf" -o "$parametros_app/${app}.conf"

	else
	
		echo -e "\nObtendo parâmetros da aplicação $app..."

		if [ "$(grep -v --file=$deploy_dir/template/app.template ${parametros_app}/${app}.conf | wc -l)" -eq "0" ]; then		
	        	source "${parametros_app}/${app}.conf"
		else
			echo -e "\nErro. Há parâmetros incorretos no arquivo ${parametros_app}/${app}.conf:"
			grep -v --file="$deploy_dir/template/app.template" "${parametros_app}/${app}.conf"

			echo ""
			read -p "Remover as entradas acima? (s/n): " -e -r ans

			if [ "$ans" == "s" ] || [ "$ans" == "S" ]; then
				grep --file="$deploy_dir/template/app.template" "${parametros_app}/${app}.conf" > "$temp_dir/app_conf_novo"
				cp -f "$temp_dir/app_conf_novo" "${parametros_app}/${app}.conf"
				echo -e "\nArquivo ${app}.conf alterado."
				source "${parametros_app}/${app}.conf"
			else
				end 1
			fi
		fi

		valid "repo" "\nErro. Informe um caminho válido para o repositório GIT:"
		editconf "repo" "$repo" "$parametros_app/${app}.conf"
        
		valid "raiz" "\nErro. Informe um caminho válido para a raiz da aplicação:"
		editconf "raiz" "$raiz" "$parametros_app/${app}.conf"

		valid "hosts_$ambiente" "\nErro. Informe uma lista válida de hosts para deploy, separando-os por espaço ou vírgula:"
		lista_hosts="echo \$hosts_${ambiente}"
		lista_hosts=$(eval "$lista_hosts")
		editconf "hosts_$ambiente" "$lista_hosts" "$parametros_app/${app}.conf"
		
		valid "modo_$ambiente" "\nErro. Informe um modo válido para deploy no ambiente $ambiente [p/d]:"		
	        modo_app="echo \$modo_${ambiente}"
	        modo_app=$(eval "$modo_app")
		editconf "modo_$ambiente" "$modo_app" "$parametros_app/${app}.conf"

		valid "share" "\nErro. Informe um diretório válido, suprimindo o nome do host (Ex: //host/a\$/b/c => a\$/b/c ):"
		editconf "share" "$share" "$parametros_app/${app}.conf"

		valid "auth" "\nErro. Informe um protocolo válido: krb5(i), ntlm(i), ntlmv2(i), ntlmssp(i):" 
		editconf "auth" "$auth" "$parametros_app/${app}.conf" 

		sort "$parametros_app/${app}.conf" -o "$parametros_app/${app}.conf"
	fi
else
	if [ ! -f "${parametros_app}/${app}.conf" ]; then 
		echo "Erro. Não foram encontrados os parâmetros para deploy da aplicação $app. O script deverá ser reexecutado no modo interativo."	
	else

		if [ "$(grep -v --file=$deploy_dir/template/app.template ${parametros_app}/${app}.conf | wc -l)" -eq "0" ]; then		
	        	source "${parametros_app}/${app}.conf"
		else
			echo -e "\nErro. Há parâmetros incorretos no arquivo ${parametros_app}/${app}.conf:"
			grep -v --file="$deploy_dir/template/app.template" "${parametros_app}/${app}.conf"
			end 1
		fi

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

mklist "$lista_hosts" $temp_dir/hosts_$ambiente

while read host; do
	dir_destino="//$host/$share"
	dir_destino=$(echo "$dir_destino" | sed -r "s|^(//.+)//(.*$)|\1/\2|g" | sed -r "s|/$||")
	nomedestino=$(echo $dir_destino | sed -r "s|/|_|g")
	lock $nomedestino "Deploy abortado: há outro deploy utilizando o diretório $dir_destino."    
	echo "$dir_destino" >> $temp_dir/dir_destino
done < $temp_dir/hosts_$ambiente

##### EXPURGO DE LOGS #######

historico_app="${historico_dir}/sistemas/${app}"

mkdir -p "${historico_app}/"
find "${historico_app}/" -maxdepth 1 -type d | grep -vx "${historico_app}/" | sort > $temp_dir/logs_total
tail $temp_dir/logs_total --lines=${qtd_log_html} > $temp_dir/logs_ultimos
grep -vxF --file=$temp_dir/logs_ultimos $temp_dir/logs_total > $temp_dir/logs_expurgo
cat $temp_dir/logs_expurgo | xargs --no-run-if-empty rm -Rf

##### CRIAÇÃO DO DIRETÓRIO DE LOG #####

data_deploy=$(date +%F_%Hh%Mm%Ss)								
info_deploy=$(echo ${data_deploy}_${rev}_${ambiente} | sed -r "s|/|_|g")				
atividade_dir="${historico_app}/${info_deploy}"								#Diretório onde serão armazenados os logs do atendimento.

if [ -d "${atividade_dir}_PENDENTE" ]; then
	rm -f ${atividade_dir}_PENDENTE/*
	rmdir ${atividade_dir}_PENDENTE
fi

mkdir -p $atividade_dir

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
fi

##### GIT #########	

if [ ! "$rev" == "rollback" ]; then
	
	echo -e "Repositório:\t$repo"
	echo -e "Caminho:\t$raiz"
	
	checkout												#ver checkout(): (git clone), cd <repositorio> , git fetch, git checkout...

	origem="$repo_dir/$nomerepo/$raiz"
	origem=$(echo "$origem" | sed -r "s|^(/.+)//(.*$)|\1/\2|g" | sed -r "s|/$||")

	if [ ! -d "$origem" ]; then										
		echo -e "\nErro: não foi possível encontrar o caminho $origem.\nVerifique a revisão informada ou corrija o arquivo $parametros_app/$app.conf."
		end 1
	else
		check_downgrade
	fi
fi

###### REGRAS DE DEPLOY: IGNORE / INCLUDE #######

echo '' > $temp_dir/regras_deploy.txt

if [ "$rev" == "rollback" ] && [ -f "${bak_dir}/regras_deploy_${app}_${ambiente}.txt" ]; then

	cat "${bak_dir}/regras_deploy_${app}_${ambiente}.txt" >> $temp_dir/regras_deploy.txt

elif [ -f "$repo_dir/$nomerepo/.gitignore" ]; then

	dos2unix -n $repo_dir/$nomerepo/.gitignore $temp_dir/gitignore_unix > /dev/null 2>&1				# garante que o arquivo .gitignore seja interpretado corretamente. (converte CRLF em LF)

	grep -Ev "^$|^ |^#" $temp_dir/gitignore_unix >> $temp_dir/regras_deploy.txt

	if [ ! "$raiz" == "/" ]; then

		raiz_git=$(echo "$raiz" | sed -r "s|^/||" | sed -r "s|/$||")

		sed -i -r "s|^(! +)?/$raiz_git(/.+)|\1\2|" $temp_dir/regras_deploy.txt					#padrões de caminho iniciados com / são substituídos.
		sed -i -r "s|^(! +)?($raiz_git)(/.+)|\1\2\3\n\1\3|" $temp_dir/regras_deploy.txt				#entradas iniciados sem / são preservadas. Uma linha com a substituição correspondente é acrescentada logo abaixo.

	fi

	sed -i -r "s|^(! +)|+ |" $temp_dir/regras_deploy.txt								#um sinal de + (include) é acrescentado ao início das entradas precedidas de "!"
	sed -i -r "s|^([^+])|- \1|" $temp_dir/regras_deploy.txt								#um sinal de - (exclude) é acrescentado ao início das demais entradas.	

fi

cp $temp_dir/regras_deploy.txt $atividade_dir/										#a fim de proporcionar transparência ao processo de deploy, as regras de ignore/include são copiadas para o log.

bkp_regras=0														#a flag será alterada tão logo as regras de deploy sejam copiadas para a pasta de backup.
rsync_opts="$rsync_opts --filter='. $temp_dir/regras_deploy.txt'"

echo $estado > $temp_dir/progresso.txt							
estado="fim_$estado" && echo $estado >> $temp_dir/progresso.txt
    
### início da leitura ###

while read dir_destino; do

	host=$(echo $dir_destino | sed -r "s|^//([^/]+)/.+$|\1|")

	cat $temp_dir/progresso.txt > $atividade_dir/progresso_$host.txt
	estado="leitura" && echo $estado >> $atividade_dir/progresso_$host.txt
    
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
	echo $destino >> $temp_dir/destino_mnt
    
	mkdir $destino || end 1
    
	mount -t cifs $dir_destino $destino -o credentials=$credenciais,sec=$auth || end 1 		#montagem do compartilhamento de destino (requer módulo anatel_ad, provisionado pelo puppet) 
 
	##### DIFF ARQUIVOS #####
    
	rsync_cmd="rsync --dry-run --itemize-changes $rsync_opts $origem/ $destino/ > $atividade_dir/modificacoes_$host.txt"
	eval $rsync_cmd || end 1
    
	##### RESUMO DAS MUDANÇAS ######
    
	adicionados="$(grep -E "^>f\+" $atividade_dir/modificacoes_$host.txt | wc -l)"
	excluidos="$(grep -E "^\*deleting .*[^/]$" $atividade_dir/modificacoes_$host.txt | wc -l)"
	modificados="$(grep -E "^>f[^\+]" $atividade_dir/modificacoes_$host.txt | wc -l)"
	dir_criado="$(grep -E "^cd\+" $atividade_dir/modificacoes_$host.txt | wc -l)"
	dir_removido="$(grep -E "^\*deleting .*/$" $atividade_dir/modificacoes_$host.txt | wc -l)"

	total_arq=$(( $adicionados + $excluidos + $modificados ))
	total_dir=$(( $dir_criado + $dir_removido ))
	total_del=$(( $excluidos + dir_removido ))
 
	echo -e "Log das modificacoes gravado no arquivo modificacoes_$host.txt\n" > $atividade_dir/resumo_$host.txt
	echo -e "Arquivos adicionados ............... $adicionados " >> $atividade_dir/resumo_$host.txt
	echo -e "Arquivos excluidos ................. $excluidos" >> $atividade_dir/resumo_$host.txt
	echo -e "Arquivos modificados ............... $modificados" >> $atividade_dir/resumo_$host.txt
	echo -e "Diretórios criados ................. $dir_criado" >> $atividade_dir/resumo_$host.txt
	echo -e "Diretórios removidos ............... $dir_removido" >> $atividade_dir/resumo_$host.txt
	echo -e "" >> $atividade_dir/resumo_$host.txt
	echo -e "Total de operações de arquivos ..... $total_arq" >> $atividade_dir/resumo_$host.txt
	echo -e "Total de operações de diretórios ... $total_dir" >> $atividade_dir/resumo_$host.txt
	echo -e "Total de operações de exclusão ..... $total_del" >> $atividade_dir/resumo_$host.txt
	
	echo ""
	cat $atividade_dir/resumo_$host.txt
    
	estado="fim_$estado" && echo $estado >> $atividade_dir/progresso_$host.txt
	
	if [ $(( $adicionados + $excluidos + $modificados + $dir_criado + $dir_removido )) -ne 0 ]; then			# O deploy somente será realizado quando a quantidade de modificações for maior que 0.
    
		###### ESCRITA DAS MUDANÇAS EM DISCO ######
	
		if $interativo; then
			echo ""
			read -p "Gravar mudanças em disco? (s/n): " -e -r ans </dev/tty
		fi
	    
		if [ "$ans" == 's' ] || [ "$ans" == 'S' ] || [ "$interativo" == "false" ]; then
	    
			if [ ! "$rev" == "rollback" ]; then
	
				#### preparação do backup ####
		        
				estado="backup" && echo $estado >> $atividade_dir/progresso_$host.txt
				echo -e "\nCriando backup"
		        
				bak="$bak_dir/${app}_${host}"
		       		rm -Rf $bak
				mkdir -p $bak
				
				rsync_cmd="rsync $rsync_opts $destino/ $bak/"
				eval $rsync_cmd || end 1
	
				#### backup regras de deploy ###				

				if [ $bkp_regras -eq 0 ]; then
					cat $temp_dir/regras_deploy.txt > "${bak_dir}/regras_deploy_${app}_${ambiente}.txt" 
					bkp_regras=1
				fi
	        
				estado="fim_$estado" && echo $estado >> $atividade_dir/progresso_$host.txt
	        	fi
	
			#### gravação das alterações em disco ####
	        	
			estado="escrita" && echo $estado >> $atividade_dir/progresso_$host.txt
			echo -e "\nEscrevendo alterações no diretório de destino..."	
	        
			rsync_cmd="rsync $rsync_opts $origem/ $destino/"
			eval $rsync_cmd 2> $atividade_dir/rsync_$host.log || end 1

			log
			
			estado="fim_$estado" && echo $estado >> $atividade_dir/progresso_$host.txt
   		else
			end 1
		fi
	else
		echo -e "\nNão há arquivos a serem modificados no host $host."
	fi

done < $temp_dir/dir_destino 

paint 'fg' 'green'
echo "$mensagem_sucesso"

end 0

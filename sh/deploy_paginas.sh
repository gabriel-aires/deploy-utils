#!/bin/bash

estado="validacao"
pid=$$
data="$(date +%Y%m%d%H%M%S)"
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

function checkout () {											# o comando cd precisa estar encapsulado para funcionar adequadamente num script, por isso foi criada a função.

	if [ ! -d "$repo_dir/$nomerepo/.git" ]; then
		echo " "
		git clone --progress "$repo" "$repo_dir/$nomerepo" || end				#clona o repositório, caso ainda não tenha sido feito.
	fi

	cd "$repo_dir/$nomerepo"
	git fetch --all --force --quiet || end

	if $automatico; then
		
		valid "revisao_$ambiente" "\nErro. O valor obtido para o parâmetro revisao_$ambiente não é válido. Favor corrigir o arquivo '$parametros_app/$app.conf'."
		revisao_auto="echo \$revisao_${ambiente}"
		revisao_auto=$(eval "$revisao_auto")

		valid "branch_$ambiente" "\nErro. O valor obtido para o parâmetro branch_$ambiente não é válido. Favor corrigir o arquivo '$parametros_app/$app.conf'."
		branch_auto="echo \$branch_${ambiente}"
		branch_auto=$(eval "$branch_auto")

		git branch -a | grep -v remotes/origin/HEAD | cut -b 3- > $temp_dir/branches

		if [ $(grep -Ei "^remotes/origin/${branch_auto}$" $temp_dir/branches | wc -l) -ne 1 ]; then
			end
		fi

		ultimo_commit=''

		case $revisao_auto in
			tag)
				git log $branch_auto --oneline | cut -f1 -d ' ' > $temp_dir/commits
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
					git checkout --force --quiet $ultima_tag || end
				else
					echo "Erro ao obter a revisão especificada. Deploy abortado"
					end
				fi
				;;	
			branch)
				ultimo_commit=$(git log "$branch_auto" --oneline | head -1 | cut -f1 -d ' ')
				
				if [ ! -z $ultimo_commit ]; then
					echo -e "\nObtendo a revisão $ultimo_commit a partir da branch $branch_auto."
					git checkout --force --quiet $branch_auto || end
				else
					echo "Erro ao obter a revisão especificada. Deploy abortado"
					end
				fi
				;;
		esac	
	else
		echo -e "\nObtendo a revisão ${rev}..."
		git checkout --force --quiet $rev || end
	fi

	if [ -f ".gitignore" ]; then
		cat .gitignore >> $temp_dir/ignore
	fi

	cd - &> /dev/null 
}

function clean_temp () {										#cria pasta temporária, remove arquivos, pontos de montagem e links simbólicos temporários
	
	if [ ! -z $temp_dir ]; then

		mkdir -p $temp_dir
	
		if [ ! -z "$destino" ]; then
			grep -E "$destino" /proc/mounts > $temp_dir/pontos_de_montagem.txt		#os pontos de montagem são obtidos do arquivo /proc/mounts
			sed -i -r 's|^.*(/mnt/[^ ]+).*$|\1|' $temp_dir/pontos_de_montagem.txt
			cat $temp_dir/pontos_de_montagem.txt | xargs --no-run-if-empty umount		#desmonta cada um dos pontos de montagem identificados em $temp_dir/pontos_de_montagem.txt.
			cat $temp_dir/pontos_de_montagem.txt | xargs --no-run-if-empty rmdir		#já desmontados, os pontos de montagem temporários podem ser apagados.
		fi

		rm -f $temp_dir/*									
		rmdir $temp_dir
	else
		end
	fi
}

function lock () {											#argumentos: nome_trava, mensagem_erro

	if [ ! -z "$1" ] && [ ! -z "$2" ]; then
		if [ -d $temp_dir ] && [ -d $lock_dir ]; then
			if [ ! -f $temp_dir/locks ]; then
				touch $temp_dir/locks
			fi
			if [ -f $lock_dir/$1 ]; then
				echo -e "\n$2" && end
			else
				touch $lock_dir/$1 && echo "$lock_dir/$1" >> $temp_dir/locks
			fi
		else
			end
		fi
	else
		end
	fi

}

function clean_locks () {

	if [ -d $lock_dir ] && [ -f "$temp_dir/locks" ]; then
		cat $temp_dir/locks | xargs --no-run-if-empty rm -f					#remove locks
	fi

}


function valid () {	#requer os argumentos nome_variável e mensagem, nessa ordem.

	if [ ! -z "$1" ] && [ ! -z "$2" ] && [ ! -z $edit ]; then
		var="$1"
		msg="$2"
		edit=0

		valor="echo \$${var}"
		valor="$(eval $valor)"

		regra="echo \$regex_${var}"	
		regra="$(eval $regra)"

		if [ -z "$regra" ]; then
			echo "Erro. Não há uma regra para validação da variável $var" && end
		elif "$interativo"; then
			while [ $(echo "$valor" | grep -Ex "$regra" | wc -l) -eq 0 ]; do
				echo -e "$msg"
				read -r $var
				edit=1
                		valor="echo \$${var}"
		                valor="$(eval $valor)"
			done
		elif [ $(echo "$valor" | grep -Ex "$regra" | wc -l) -eq 0 ]; then
			echo -e "$msg" && end
		fi			
	else
		end
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
		echo "Erro. Não foi possível editar o arquivo de configuração." && end
	fi
    
}

function mklist () {

	if [ ! -z "$1" ] && [ ! -z "$2" ]; then
		lista=$(echo "$1" | sed -r 's/,/ /g' | sed -r 's/;/ /g' | sed -r 's/ +/ /g' | sed -r 's/ $//g' | sed -r 's/^ //g' | sed -r 's/ /\n/g')
		echo "$lista" > $2
	else
		end 
	fi

}

function end () {
	
	wait
	
	if [ "$estado" == 'fim_validacao' ] || [ "$estado" == 'leitura' ] || [ "$estado" == 'fim_leitura' ]; then
	
		echo "deploy_abortado" >> $atividade_dir/progresso_$host.txt
		echo -e "\nDeploy abortado."
		mv "$atividade_dir" "${atividade_dir}_PENDENTE"

	elif [ "$estado" == 'backup' ] || [ "$estado" == 'fim_backup' ]; then

		rm -Rf $bak
		
		echo "deploy_abortado" >> $atividade_dir/progresso_$host.txt
		echo -e "\nDeploy abortado."
		mv "$atividade_dir" "${atividade_dir}_PENDENTE"

	elif [ "$estado" == 'escrita' ]; then

		echo -e "\nDeploy interrompido durante a etapa de escrita. Revertendo alterações..."
		echo "rollback" >> $atividade_dir/progresso_$host.txt
		
		rsync -rc --inplace $bak/ $destino/ 
		
		rm -Rf $bak
		
		echo "fim_rollback" >> $atividade_dir/progresso_$host.txt
		echo "deploy_abortado" >> $atividade_dir/progresso_$host.txt
		echo -e "Rollback finalizado."	
		mv "$atividade_dir" "${atividade_dir}_PENDENTE"

	elif [ "$estado" == 'fim_escrita' ]; then
		
		##### LOG DE DEPLOY #####
	
		horario_log=$(echo $data | sed -r "s|^(....)(..)(..)(..)(..)(..)$|\3/\2/\1      \4h\5m\6s       |")
		
		tamanho_app=$(echo -n $app | wc -m)
		app_log=$(echo '                ' | sed -r "s|^ {$tamanho_app}|$app|")

		rev_log=$(echo $rev | sed -r "s|^(.........).*$|\1|")
		tamanho_rev=$(echo -n $rev_log | wc -m)
	 	rev_log=$(echo '                ' | sed -r "s|^ {$tamanho_rev}|$rev_log|")

		tamanho_ambiente=$(echo -n $ambiente | wc -m) 
		ambiente_log=$(echo '                ' | sed -r "s|^ {$tamanho_ambiente}|$ambiente|")
		
		if [ "$modo" == 'p' ]; then
			obs_log='Arquivos e diretórios obsoletos preservados.'
		else
			obs_log='Arquivos e diretórios obsoletos deletados.'
		fi
		
		echo -e "$horario_log$app_log$rev_log$ambiente_log$obs_log" >> $historico

		cp -f $historico $atividade_dir

		tamanho_horario=$(echo -n "$horario_log" | wc -m) 
		grep -Ei "^(.){$tamanho_horario}$app" $historico > $historico_dir/$app/deploy.log
		
		echo "deploy_concluido" >> $atividade_dir/progresso_$host.txt
		echo -e "\nDeploy concluído."
	fi

	clean_locks
	clean_temp

	wait &&	exit 0
}

#### Inicialização #####

trap "end; exit" SIGQUIT SIGTERM SIGINT SIGHUP						#a função será chamada quando o script for finalizado ou interrompido.

edit=0

if $interativo; then
	clear
fi

deploy_dir="/opt/autodeploy-paginas"										#diretório de instalação.
source $deploy_dir/conf/global.conf || exit								#carrega o arquivo de constantes.

temp_dir="$temp/$pid"

if [ -z "$regex_temp_dir" ] \
	|| [ -z "$regex_temp_dir" ] \
	|| [ -z "$regex_historico_dir" ] \
	|| [ -z "$regex_repo_dir" ] \
	|| [ -z "$regex_lock_dir" ] \
	|| [ -z "$regex_bak_dir" ] \
	|| [ -z "$regex_app" ] \
	|| [ -z "$regex_rev" ] \
	|| [ -z "$regex_chamado" ] \
	|| [ -z "$regex_modo" ] \
	|| [ -z "$regex_repo" ] \
	|| [ -z "$regex_raiz" ] \
	|| [ -z "$regex_dir_destino" ] \
	|| [ -z "$regex_os" ] \
	|| [ -z $(echo $bak_dir | grep -E "$regex_bak_dir") ] \
	|| [ -z $(echo $temp_dir | grep -E "$regex_temp_dir") ] \
	|| [ -z $(echo $historico_dir | grep -E "$regex_historico_dir") ] \
	|| [ -z $(echo $repo_dir | grep -E "$regex_repo_dir")  ] \
	|| [ -z $(echo $lock_dir | grep -E "$regex_lock_dir") ] \
	|| [ -z "$modo_padrao" ] \
	|| [ -z "$ambientes" ] \
	|| [ -z "$interativo" ];
then
    echo 'Favor preencher corretamente o arquivo global.conf e tentar novamente.'
    exit
fi

mkdir -p $deploy_dir $temp $historico_dir $repo_dir $lock_dir $parametros_app $bak_dir			#cria os diretórios necessários, caso não existam.

if [ ! -e "$historico" ]; then										#cria arquivo de histórico, caso não exista.
	touch $historico	
fi

clean_temp && mkdir -p $temp_dir
mklist "$ambientes" "$temp_dir/ambientes"

#### Validação do input do usuário ###### 

echo "Iniciando processo de deploy..."

if [ -z "$modo" ]; then
	modo=$modo_padrao
fi

if $interativo; then
	valid "app" "\nInforme o nome do sistema corretamente (somente letras minúsculas):"
	valid "rev" "\nInforme a revisão corretamente:"
	
	if [ "$rev" == "auto" ]; then
		echo "Erro. Não é permitido o deploy automático em modo interativo."
		exit 1
	fi

	valid "ambiente" "\nInforme o ambiente corretamente:"
else
	valid "app" "\nErro. Nome do sistema informado incorratemente."
	valid "rev" "\nErro. Revisão/tag/branch informada incorretamente."
	valid "ambiente" "\n.Erro. Ambiente informado incorretamente."					
fi

#### Verifica deploys simultâneos e cria lockfiles, conforme necessário ########

lock $app "Deploy abortado: há outro deploy da aplicação $app em curso." 

if $interativo; then

	if [ ! -f "${parametros_app}/${app}.conf" ]; then					#caso não haja registro referente ao sistema ou haja entradas duplicadas.
	
		echo -e "\nFavor informar abaixo os parâmetros da aplicação $app."

		echo -e "\nInforme o repositorio a ser utilizado:"
		read -r repo
		valid "repo" "\nErro. Informe um caminho válido para o repositório GIT:"
	
		echo -e "\nInforme o caminho para a raiz da aplicação:"
		read -r raiz											#utilizar a opção -r para permitir a leitura de contrabarras.
		valid "raiz" "\nErro. Informe um caminho válido para a raiz da aplicação (substituir '\\' por '/', quando necessário):"

		echo -e "\nInforme os hosts para deploy da aplicação $app no ambiente de $ambiente (separados por espaço ou vírgula):"
		read -r hosts_$ambiente
		valid "hosts_$ambiente" "\nErro. Informe uma lista válida de hosts para deploy, separando-os por espaço ou vírgula:"

		echo -e "\nInforme o diretório compartilhado para deploy (deve ser o mesmo em todos os hosts)"
		read -r share
		valid "share" "\nErro. Informe um diretório válido, suprimindo o nome do host (Ex: //host/a\$/b/c => a\$/b/c )"
		
		echo -e "\nInforme o sistema operacional:"
		read -r os                          										
		valid "os" "\nErro. Informe um nome válido para o sistema operacional (windows/linux):"
	
		raiz="$(echo $raiz | sed -r 's|^/||' | sed -r 's|/$||')"					#remove / no início ou fim do caminho.
		share="$(echo $share | sed -r 's|/$||')"						#remove / no fim do caminho.

		editconf "app" "$app" "$parametros_app/${app}.conf"
		editconf "repo" "$repo" "$parametros_app/${app}.conf"
		editconf "raiz" "$raiz" "$parametros_app/${app}.conf"
		
		while read env; do
			if [ "$env" == "$ambiente"  ]; then
				lista_hosts="echo \$hosts_${env}"
				lista_hosts=$(eval "$lista_hosts")
				editconf "hosts_$env" "$lista_hosts" "$parametros_app/${app}.conf"        	

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
		editconf "os" "$os" "$parametros_app/${app}.conf"
		
		sort "$parametros_app/${app}.conf" -o "$parametros_app/${app}.conf"

	else
	
		echo -e "\nObtendo parâmetros da aplicação $app..."
		source "${parametros_app}/${app}.conf" 
                
		valid "repo" "\nErro. Informe um caminho válido para o repositório GIT:"
		editconf "repo" "$repo" "$parametros_app/${app}.conf"
        
		valid "raiz" "\nErro. Informe um caminho válido para a raiz da aplicação:"
		editconf "raiz" "$raiz" "$parametros_app/${app}.conf"

		valid "hosts_$ambiente" "\nErro. Informe uma lista válida de hosts para deploy, separando-os por espaço ou vírgula:"
		lista_hosts="echo \$hosts_${ambiente}"
		lista_hosts=$(eval "$lista_hosts")
		editconf "hosts_$ambiente" "$lista_hosts" "$parametros_app/${app}.conf"

		valid "share" "\nErro. Informe um diretório válido, suprimindo o nome do host (Ex: //host/a\$/b/c => a\$/b/c ):"
		editconf "share" "$share" "$parametros_app/${app}.conf"

		valid "os" "\nErro. Informe um nome válido para o sistema operacional (windows/linux):"
		editconf "os" "$os" "$parametros_app/${app}.conf"
		
		sort "$parametros_app/${app}.conf" -o "$parametros_app/${app}.conf"
	fi
else
	if [ ! -f "${parametros_app}/${app}.conf" ]; then 
		echo "Erro. Não foram encontrados os parâmetros para deploy da aplicação $app. O script deverá ser reexecutado no modo interativo."	
	else
        	source "${parametros_app}/${app}.conf"

	        valid "repo" "\nErro. \'$repo\' não é um repositório git válido."
	        valid "raiz" "\nErro. \'$repo\' não é um caminho válido para a raiz da aplicação $app."
	        valid "hosts_$ambiente" "\nErro. A lista de hosts para o ambiente $ambiente não é válida."
		valid "auto_$ambiente" "\nErro. Não foi possível ler a flag de deploy automático."
	        valid "share" "\nErro. \'$share\' não é um diretório compartilhado válido."
	        valid "os" "\nErro. \'$os\' não é um sistema operacional válido (windows/linux)."
        
	        lista_hosts="echo \$hosts_${ambiente}"
	        lista_hosts=$(eval "$lista_hosts")  

	        auto="echo \$auto_${ambiente}"
	        auto=$(eval "$auto")  

		if [ "$rev" == "auto" ]; then
			if [ "$auto" == "1" ]; then
				automatico="true"
			else
				echo "Erro. O deploy automático está desabilitado para a aplicação $app."
				end
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

atividade_dir="$historico_dir/$app/$(date +%F)/$rev_$ambiente"								#Diretório onde serão armazenados os logs do atendimento.
if [ -d "${atividade_dir}_PENDENTE" ]; then
	rm -f ${atividade_dir}_PENDENTE/*
	rmdir ${atividade_dir}_PENDENTE
fi

mkdir -p $atividade_dir

##### GIT #########	

echo '' > $temp_dir/ignore

checkout												#ver checkout(): (git clone), cd <repositorio> , git fetch, git checkout...

origem="$repo_dir/$nomerepo/$raiz"
origem=$(echo "$origem" | sed -r "s|^(/.+)//(.*$)|\1/\2|g" | sed -r "s|/$||")

if [ ! -d "$origem" ]; then										
	origem="$repo_dir/$raiz"									#é comum que o usuário informe a pasta do sistema (nomerepo) como parte da raiz.
	origem=$(echo "$origem" | sed -r "s|^(/.+)//(.*$)|\1/\2|g" | sed -r "s|/$||")	
fi

if [ ! -d "$origem" ]; then										
	echo -e "\nErro: não foi possível encontrar o caminho $origem.\nVerifique a revisão informada ou corrija o arquivo $parametros_app."
	end
fi

echo -e "\nSistema:\t$app"
echo -e "Revisão:\t$rev"
echo -e "Repositório:\t$repo"
echo -e "Caminho:\t$raiz"

echo $estado > $atividade_dir/progresso.txt							
estado="fim_$estado" && echo $estado >> $atividade_dir/progresso.txt
    
### início da leitura ###

while read dir_destino; do

	host=$(echo $dir_destino | sed -r "s|^//([^/]+)/.+$|\1|")
	estado="leitura" && echo $estado >> $atividade_dir/progresso_$host.txt
    
	echo -e "\nIniciando deploy no host $host..."
	echo -e "Diretório de deploy:\t$dir_destino"
    
	##### CRIA PONTO DE MONTAGEM TEMPORÁRIO E DIRETÓRIO DO CHAMADO #####
    
	destino="/mnt/${app}_${data}"
    
	mkdir $destino || end 
    
	if [ $os == 'windows' ]; then
        	mount.cifs $dir_destino $destino -o credentials=$credenciais || end				#montagem do compartilhamento de destino (requer pacote cifs-utils)
	else
        	mount.cifs $dir_destino $destino -o credentials=$credenciais,sec=krb5 || end 		#montagem do compartilhamento de destino (requer módulo anatel_ad, provisionado pelo puppet)
	fi
    
	##### DIFF ARQUIVOS #####
    
	if [ "$modo" == "p" ]; then
		rsync -rnic --inplace --exclude-from=$temp_dir/ignore $origem/ $destino/ > $atividade_dir/modificacoes_$host.txt || end
	else
		rsync -rnic --delete --inplace $origem/ $destino/ --exclude-from=$temp_dir/ignore > $atividade_dir/modificacoes_$host.txt || end
	fi
    
	##### RESUMO DAS MUDANÇAS ######
    
	adicionados="$(grep -E "^>f\+" $atividade_dir/modificacoes_$host.txt | wc -l)"
	excluidos="$(grep -E "^\*deleting .*[^/]$" $atividade_dir/modificacoes_$host.txt | wc -l)"
	modificados="$(grep -E "^>f[^\+]" $atividade_dir/modificacoes_$host.txt | wc -l)"
	dir_criado="$(grep -E "^cd\+" $atividade_dir/modificacoes_$host.txt | wc -l)"
	dir_removido="$(grep -E "^\*deleting .*/$" $atividade_dir/modificacoes_$host.txt | wc -l)"
    
	echo -e "\nLog das modificacoes gravado no arquivo modificacoes.txt\n" > $atividade_dir/resumo_$host.txt
	echo -e "Arquivos adicionados:\t$adicionados " >> $atividade_dir/resumo_$host.txt
	echo -e "Arquivos excluidos:\t$excluidos" >> $atividade_dir/resumo_$host.txt
	echo -e "Arquivos modificados:\t$modificados" >> $atividade_dir/resumo_$host.txt
	echo -e "Diretórios criados:\t$dir_criado" >> $atividade_dir/resumo_$host.txt
	echo -e "Diretórios removidos:\t$dir_removido" >> $atividade_dir/resumo_$host.txt
    
	cat $atividade_dir/resumo_$host.txt
    
	estado="fim_$estado" && echo $estado >> $atividade_dir/progresso_$host.txt
    
	###### ESCRITA DAS MUDANÇAS EM DISCO ######

	if $interativo; then
		echo -e "\nGravar mudanças em disco? (s/n)"
		read ans </dev/tty
	fi
    
	if [ "$ans" == 's' ] || [ "$ans" == 'S' ] || [ "$interativo" == "false" ]; then
    
		#### preparação do script de rollback ####
        
		estado="backup" && echo $estado >> $atividade_dir/progresso_$host.txt
		echo -e "\nCriando backup"
        	
		rm -Rf "$bak_dir/${app}_${host}"
        
		bak="$bak_dir/${app}_${host}"
        
		mkdir -p $bak
        
		rsync -rc --inplace $destino/ $bak/ || end
        
		estado="fim_$estado" && echo $estado >> $atividade_dir/progresso_$host.txt
        
		#### gravação das alterações em disco ####
        	
		estado="escrita" && echo $estado >> $atividade_dir/progresso_$host.txt
		echo -e "\nEscrevendo alterações no diretório de destino..."	
        
		if [ "$modo" == "p" ]; then
        		rsync -rc --inplace --exclude-from=$temp_dir/ignore $origem/ $destino/ || end
		else
			rsync -rc --delete --inplace --exclude-from=$temp_dir/ignore $origem/ $destino/ || end
		fi
        
		estado="fim_$estado" && echo $estado >> $atividade_dir/progresso_$host.txt
    	
	fi

done < $temp_dir/dir_destino 

end

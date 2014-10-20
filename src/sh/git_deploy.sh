#!/bin/bash

estado="inicializacao"

##### Execução somente como usuário root ######

if [ ! "$(echo $USER)" == 'root' ]; then
	echo "Requer usuário root."
	exit
fi

##### Bloqueio de execuções simultâneas #######

if [ "$(ps aux | grep -E 'git_deploy.sh' | grep -Ev 'grep|sudo' | wc -l)" -gt "2" ]; then		#TODO: bloquear execuções simultâneas apenas nos casos abaixo:
	echo "Há outro deploy em andamento. Favor tentar novamente mais tarde."				# - usuário root
	exit												# - execuções simultâneas pelo mesmo usuário
fi													# - mesmo repositório GIT (mover repositórios para /opt/repo/)
													# - mesmo diretório de destino
#### UTILIZAÇÃO: git_deploy.sh <aplicação> <revisão> <chamado> (modo) ############

if [ "$#" -lt 3 ]; then											#o script requer exatamente 3 parâmetros.
	echo "O script requer no mínimo 3 parâmetros: <aplicação> <revisão> <chamado>"
	exit
fi

app=$1
rev=$2
chamado=$3
modo=$4													# p - preservar arquivos no destino | d - deletar arquivos no destino.

#### Inicialização #####

deploy_dir="/opt/git_deploy"										#diretório de instalação.
source $deploy_dir/constantes.txt || exit									#carrega o arquivo de constantes.

echo $temp_dir $chamados_dir $repo_dir

if [ -z $(echo $temp_dir | grep -E "^/opt/[^/]+") ] || [ -z $(echo $chamados_dir | grep -E "^/opt/[^/]+|^/mnt/[^/]+") ] || [ -z $(echo $repo_dir | grep -E "^/opt/[^/]+|^/mnt/[^/]+")  ]; then
    echo 'Favor preencher corretamente o arquivo $deploy_dir/constantes.txt e tentar novamente.'
    exit
fi

mkdir -p $deploy_dir $chamados_dir $repo_dir 								#cria os diretórios necessários, caso não existam.

if [ ! -e "$parametros_git" ]; then									#cria arquivo de parâmetros, caso não exista.
	touch $parametros_git
fi

if [ ! -e "$historico" ]; then										#cria arquivo de histórico, caso não exista.
	touch $historico	
fi

#### Funções ##########

function checkout () {											# o comando cd precisa estar encapsulado para funcionar adequadamente num script, por isso foi criada a função.

	if [ ! -d "$repo_dir/$app/.git" ]; then
		echo " "
		git clone --progress "$repo" "$repo_dir/$app"						#clona o repositório, caso ainda não tenha sido feito.
	fi

	echo " "

	cd "$repo_dir/$app"

	( git fetch --all --force --quiet && git checkout --force --quiet $rev ) || exit

	cd - 

}

function clean_temp () {										#cria pasta temporária, remove arquivos, pontos de montagem e links simbólicos temporários

	mkdir -p $temp_dir;

	grep -E "/mnt/destino_.*" /proc/mounts > $temp_dir/pontos_de_montagem.txt			#os pontos de montagem são obtidos do arquivo /proc/mounts
	sed -i -r 's|^.*(/mnt/[^ ]+).*$|\1|' $temp_dir/pontos_de_montagem.txt

	cat $temp_dir/pontos_de_montagem.txt | xargs --no-run-if-empty umount				#desmonta cada um dos pontos de montagem identificados em $temp_dir/pontos_de_montagem.txt.
	cat $temp_dir/pontos_de_montagem.txt | xargs --no-run-if-empty rmdir				#já desmontados, os pontos de montagem temporários podem ser apagados.

	rm -f $temp_dir/*										#remoção de link simbólico (a opção -R não foi utilizada para que o link simbólico não seja seguido).

}

trap "clean_temp" EXIT SIGQUIT SIGKILL SIGTERM SIGINT							#a função será chamada quando o script for finalizado ou interrompido.

clean_temp	

echo $estado > $temp_dir/progresso.txt							

estado="fim_$estado" && echo $estado >> $temp_dir/progresso.txt

#### Validação do input do usuário ###### 

estado="validacao" && echo $estado >> $temp_dir/progresso.txt

clear

while [ -z $(echo $app | grep -Ex "[A-Za-z]+") ]; do
	echo -e "\nErro. Informe o nome do sistema corretamente:"
	read app
done

app=$(echo $app | sed -r 's/(^.*$)/\L\1/')								#apenas letras minúsculas.

while [ -z $(echo $rev | grep -Ex "^([0-9a-f]){9}[0-9a-f]*$") ]; do					#a revisão é uma string hexadecimal de 9 ou mais caracteres.
	echo -e "\nErro. Informe a revisão corretamente:"
	read rev
done

while [ -z $(echo $chamado | grep -Ex "[0-9]+/[0-9]{4}") ]; do						#chamado: n(nnn ...)/aaaa
	echo -e "\nErro. Informe o chamado corretamente:"
	read chamado
done

while [ -z $(echo $modo | grep -Ex "[pd]") ]; do
	if [ -z "$modo" ]; then
		modo=$modo_padrao
	else
		echo -e "\nErro. Escolha o modo de execução: [p, d]"
		read modo
	fi
done

if [ $(grep -Ei "^$app " $parametros_git | wc -l) -ne "1" ]; then					#caso não haja registro referente ao sistema ou haja entradas duplicadas.
	sed -i "/^$app .*$/d" $parametros_git									 

	echo -e "\nInforme o repositorio a ser utilizado:"
	read repo
	
	while [ -z $(echo $repo | grep -Ex "^git@git.anatel.gov.br:.+/.+\.git$|^http://(.+@)?git.anatel.gov.br.*/.+\.git$") ]; do	#Expressão regular para validação do caminho para o repositóio (SSH ou HTTP).
		echo -e "\nErro. Informe um caminho válido para o repositório GIT:"
		read -r repo
	done	

	echo -e "\nInforme o caminho para a raiz da aplicação:"
	read -r raiz											#utilizar a opção -r para permitir a leitura de contrabarras.
	raiz="$(echo $raiz | sed -r 's|\\|/|g')"							#troca \ por /, se necessário.
	
	while [ -z $(echo $raiz | grep -Ex "^/?[^/ \\]*(/[^/ \\]+)*/?$") ]; do				#Expressão regular para validação do caminho para a raiz da aplicação. ex: (/)aaa/bbbb/*(/)
		echo -e "\nErro. Informe um caminho válido para a raiz da aplicação:"
		read -r raiz
		raiz="$(echo $raiz | sed -r 's|\\|/|g')"
	done												

	echo -e "\nInforme o diretório de destino:"
	read -r dir_destino										#utilizar a opção -r para permitir a leitura de contrabarras.
	dir_destino="$(echo $dir_destino | sed -r 's|\\|/|g')"						#troca \ por /, se necessário.
	
	while [ -z $(echo $dir_destino | grep -Ex "^/(/[^/ \\]+)+/?$") ]; do				#Expressão regular para validação de string de compartilhamento CIFS. ex: \\aaa\bb\*(\)
		echo -e "\nErro. Informe um caminho válido para o diretório de destino:"
		read -r dir_destino
		dir_destino="$(echo $dir_destino | sed -r 's|\\|/|g')"
	done

	raiz="$(echo $raiz | sed -r 's|^/||' | sed -r 's|/$||')"					#remove / no início ou fim do caminho.
	dir_destino="$(echo $dir_destino | sed -r 's|/$||')"						#remove / no fim do caminho.

	echo "$app $repo $raiz $dir_destino" >> $parametros_git
else													#caso a entrada correspondente ao sistema já esteja preenchida, os parâmetros são obtidos do arquivo $deploy_dir/parametros.txt
	repo=$(grep -Ei "^$app " $parametros_git | cut -d ' ' -f2)
	raiz=$(grep -Ei "^$app " $parametros_git | cut -d ' ' -f3)
	dir_destino=$(grep -Ei "^$app " $parametros_git | cut -d ' ' -f4)
fi

atividade_dir="$(echo $chamado | sed -r 's|/|\.|')"													
atividade_dir="$chamados_dir/$app/$atividade_dir"							#Diretório onde serão armazenados os logs do atendimento.

if [ -d "${atividade_dir}_PENDENTE" ]; then
	rm -f "${atividade_dir}_PENDENTE/*"
	rmdir "${atividade_dir}_PENDENTE"
fi

mkdir -p $atividade_dir

echo -e "\nSistema:\t$app"
echo -e "Repositório:\t$repo"
echo -e "Caminho:\t$raiz"
echo -e "Destino:\t$dir_destino"

estado="fim_$estado" && echo $estado >> $temp_dir/progresso.txt

### início da leitura ###

estado="leitura" && echo $estado >> $temp_dir/progresso.txt

##### GIT #########	

checkout												#ver checkout(): (git clone), cd <repositorio> , git fetch, git checkout...

origem="$repo_dir/$app/$raiz"

if [ ! -d "$origem" ]; then										
	origem="$repo_dir/$raiz"									#é comum que o usuário informe a pasta do sistema como parte da raiz.
fi

##### CRIA PONTO DE MONTAGEM TEMPORÁRIO E DIRETÓRIO DO CHAMADO #####

data="$(date +%Y%m%d%H%M%S)"
destino="$temp_dir/destino_$data"
mnt_destino="/mnt/destino_$data"

mkdir -p $mnt_destino

echo -e "\nAcesso ao diretório de deploy."

mount.cifs $dir_destino $mnt_destino -o credentials=$credenciais || exit 				#montagem do compartilhamento de destino (requer pacote cifs-utils)

ln -s $mnt_destino $destino										#cria link simbólico para o ponto de montagem.	

##### DIFF ARQUIVOS #####


find "$origem/" -type f | sort > $temp_dir/origem.txt;							#lista arquivos em "origem" e "destino"
find "$destino/" -follow -type f | sort > $temp_dir/destino.txt;

sed -i -r 's|(^.*$)|\"\1\"|' $temp_dir/origem.txt;							#as aspas são necessárias quando há espaços nos nomes de arquivos
sed -i -r 's|(^.*$)|\"\1\"|' $temp_dir/destino.txt;

sed -i -r "s|^\"$origem/|\"|" $temp_dir/origem.txt;							#removendo-se o nome dos diretórios pai, é possível a comparação entre os caminhos em cada lista
sed -i -r "s|^\"$destino/|\"|" $temp_dir/destino.txt;

grep -vxF --file=$temp_dir/origem.txt $temp_dir/destino.txt > $temp_dir/arq.excluido;			#verifica quais arquivos existem somente no destino (excluídos) ou somente na origem (adicionados)
grep -vxF --file=$temp_dir/destino.txt $temp_dir/origem.txt > $temp_dir/arq.adicionado;

cat $temp_dir/arq.excluido > $temp_dir/aux.txt;
cat $temp_dir/arq.adicionado >> $temp_dir/aux.txt;							#arquivos que foram adicionados ou excluídos

grep -vxF --file=$temp_dir/aux.txt $temp_dir/destino.txt > $temp_dir/aux2.txt;				#arquivos que existem em ambos, mas não necessariamente foram modificados.

sed -r "s|^\"|\"$origem/|" $temp_dir/aux2.txt > $temp_dir/origem.list;					#para os arquivos comuns a ambos, foi restaurado seu caminho completo visando à comparação de suas propriedades (abaixo).
sed -r "s|^\"|\"$destino/|" $temp_dir/aux2.txt > $temp_dir/destino.list;

cat $temp_dir/origem.list | xargs sha512sum > $temp_dir/detalhe_origem.list;				#Verificação por hash (para verificação dos arquivos modificados por tamanho e data, trocar "sha512" por "ls -l --full-time").
cat $temp_dir/destino.list | xargs sha512sum > $temp_dir/detalhe_destino.list;

sed -i -r "s|(^.{130})$origem/|\1|" $temp_dir/detalhe_origem.list;					#130 é a quantidade de caracteres do hash mais 2 espaços.					
sed -i -r "s|(^.{130})$destino/|\1|" $temp_dir/detalhe_destino.list;

grep -vxF --file=$temp_dir/detalhe_destino.list $temp_dir/detalhe_origem.list > $temp_dir/arq.alterado;	#este arquivo contém a lista dos arquivos alterados.
sed -i -r 's/^.{130}//' $temp_dir/arq.alterado								#remoção do hash na lista de arquivos modificados.

##### CRIAÇÃO / REMOÇÃO DE DIRETÓRIOS #####

find "$origem/" -type d | sort -r > $temp_dir/d_origem.txt;						#lista diretórios em "origem" e "destino". A ordenação inversa (sort -r) é necessária para uma eventual exclusão dos diretórios.
find "$destino/" -follow -type d | sort -r > $temp_dir/d_destino.txt;

sed -i -r 's|(^.*$)|\"\1\"|' $temp_dir/d_origem.txt;							#as aspas são necessárias quando há espaços nos nomes de diretórios
sed -i -r 's|(^.*$)|\"\1\"|' $temp_dir/d_destino.txt;

sed -i -r "s|^\"$origem/|\"|" $temp_dir/d_origem.txt;							#removendo-se o nome dos diretórios pai, é possível a comparação entre os caminhos em cada lista
sed -i -r "s|^\"$destino/|\"|" $temp_dir/d_destino.txt;

grep -vxF --file=$temp_dir/d_origem.txt $temp_dir/d_destino.txt > $temp_dir/dir.excluido;		#verifica quais diretórios existem somente no destino (excluídos) ou somente na origem (adicionados)
grep -vxF --file=$temp_dir/d_destino.txt $temp_dir/d_origem.txt > $temp_dir/dir.adicionado;

##### LOG E RESUMO DAS MUDANÇAS ######

if [ "$modo" == 'd' ]; then
	grep -EH "*" $temp_dir/arq.* > $atividade_dir/modificacoes.txt;								
	grep -EH "*" $temp_dir/dir.* >> $atividade_dir/modificacoes.txt;								
else
	grep -EH "*" $temp_dir/arq.adicionado > $atividade_dir/modificacoes.txt;
	grep -EH "*" $temp_dir/arq.alterado >> $atividade_dir/modificacoes.txt;								
	grep -EH "*" $temp_dir/dir.adicionado >> $atividade_dir/modificacoes.txt;								
fi

sed -i -r "s|^$temp_dir/||" $atividade_dir/modificacoes.txt
sed -i "s/:/:\t/" $atividade_dir/modificacoes.txt							#formatação para leitura

adicionados="$(grep -E "^arq\.adicionado" $atividade_dir/modificacoes.txt | wc -l)"
excluidos="$(grep -E "^arq\.excluido" $atividade_dir/modificacoes.txt | wc -l)"
modificados="$(grep -E "^arq\.alterado" $atividade_dir/modificacoes.txt | wc -l)"
dir_criado="$(grep -E "^dir\.adicionado" $atividade_dir/modificacoes.txt | wc -l)"
dir_removido="$(grep -E "^dir\.excluido" $atividade_dir/modificacoes.txt | wc -l)"

echo -e "\nLog das modificacoes gravado no arquivo $atividade_dir/modificacoes.txt!\n"
echo -e "Arquivos adicionados:\t$adicionados "
echo -e "Arquivos excluidos:\t$excluidos"
echo -e "Arquivos modificados:\t$modificados"
echo -e "Diretórios criados:\t$dir_criado"
echo -e "Diretórios removidos:\t$dir_removido"

estado="fim_$estado" && echo $estado >> $temp_dir/progresso.txt

###### ESCRITA DAS MUDANÇAS EM DISCO ######

echo -e "\nGravar mudanças em disco? (s/n)"
read ans

if [ "$ans" == 's' ] || [ "$ans" == 'S' ]; then

	#### preparação do script de rollback ####

	estado="backup" && echo $estado >> $temp_dir/progresso.txt
	
	rm -Rf "$chamados_dir/$app/ROLLBACK_*"

	bak_dir="$chamados_dir/$app/ROLLBACK_$data"

	mkdir -p $bak_dir

	cp $temp_dir/arq.adicionado $temp_dir/arq.remover_novos
	cp $temp_dir/arq.alterado $temp_dir/arq.restaurar_alterados
	cp $temp_dir/arq.excluido $temp_dir/arq.restaurar_excluidos

	sed -r "s|^\"|\"$bak_dir/|" $temp_dir/d_destino.txt > $temp_dir/dir.restaurar_todos
	cp $temp_dir/dir.adicionado $temp_dir/dir.remover_novos						# toda a estrutura de diretórios do destino será recriada no diretório ROLLBACK.

	sed -i -r 's|(^.*$)|\"\1\"|' $temp_dir/arq.restaurar_alterados					#reinserção das aspas na lista de arquivos modificados.

	sed -i -r "s|^\"|\"$destino/|" $temp_dir/arq.restaurar_alterados				#caminho absoluto no diretório de origem para arquivos e diretórios adicionados ou modificados.
	sed -i -r "s|^\"|\"$destino/|" $temp_dir/arq.restaurar_excluidos

	sed -i -r "s|(^\"$destino/)(.*$)|\$\(cp -f \1\2 \"$bak_dir/\2\)|" $temp_dir/arq.restaurar_alterados
	sed -i -r "s|/[^/]+\"\)$|\"\)|" $temp_dir/arq.restaurar_alterados

	sed -i -r "s|(^\"$destino/)(.*$)|\$\(cp -f \1\2 \"$bak_dir/\2\)|" $temp_dir/arq.restaurar_excluidos		
	sed -i -r "s|/[^/]+\"\)$|\"\)|" $temp_dir/arq.restaurar_excluidos					#cópia de novos arquivos: $(cp -f "<caminho_origem/arquivo_origem>" "<caminho_destino>")
	
	sed -i -r "s|^\"|\"$destino/|" $temp_dir/arq.remover_novos						#caminho absoluto no diretório de destino para arquivos e diretórios a serem removidos.
	sed -i -r "s|^\"|\"$destino/|" $temp_dir/dir.remover_novos							

	sed -i -r "s|(^\"$destino/)(.*$)|\$\(rm -f \1\2\)|" $temp_dir/arq.remover_novos
	sed -i -r "s|(^\"$destino/)(.*$)|\$\(rmdir \1\2\)|" $temp_dir/dir.remover_novos
	
	rm -f $bak_dir/rollback.txt
	touch $bak_dir/rollback.txt

	cat $temp_dir/arq.remover_novos >> $bak_dir/rollback.txt					# 1 - remoção de arquivos a serem criados no destino.
	cat $temp_dir/dir.remover_novos >> $bak_dir/rollback.txt					# 2 - remoção de diretórios a serem criados no destino.
							
	if [ "$(cat $temp_dir/dir.restaurar_todos | wc -l)" -gt "0" ]; then
		cat $temp_dir/dir.restaurar_todos | xargs mkdir -p
		sed -i -r "s|(^\"$bak_dir/)(.*$)|\$\(mkdir -p \"$destino/\2\)|" $temp_dir/dir.restaurar_todos	# 3 - criação da estrutura de diretórios dentro da pasta ROLLBACK
		cat $temp_dir/dir.restaurar_todos >> $bak_dir/rollback.txt
	fi

	if [ "$(cat $temp_dir/arq.restaurar_alterados | wc -l)" -gt "0" ]; then								
		cat $temp_dir/arq.restaurar_alterados | xargs -d "\n" -L 1 sh -c			# 5 - cópia de arquivos a serem modificados para a pasta ROLLBACK
		sed -i -r "s|(^\$\(cp -f )(\"$destino)(/[^\"]*\" )(\"$bak_dir)(.*$)|\1\4\3\2\5|" $temp_dir/arq.restaurar_alterados
		cat $temp_dir/arq.restaurar_alterados >> $bak_dir/rollback.txt
	fi

	if [ "$(cat $temp_dir/arq.restaurar_excluidos | wc -l)" -gt "0" ]; then
		cat $temp_dir/arq.restaurar_excluidos | xargs -d "\n" -L 1 sh -c			# 4 - cópia de arquivos a serem excluidos para a pasta ROLLBACK
		sed -i -r "s|(^\$\(cp -f )(\"$destino)(/[^\"]*\" )(\"$bak_dir)(.*$)|\1\4\3\2\5|" $temp_dir/arq.restaurar_excluidos
		cat $temp_dir/arq.restaurar_excluidos >> $bak_dir/rollback.txt 
	fi	

	estado="fim_$estado" && echo $estado >> $temp_dir/progresso.txt

	#### gravação das alterações em disco ####
		
	estado="escrita" && echo $estado >> $temp_dir/progresso.txt
	
	sed -i -r 's|(^.*$)|\"\1\"|' $temp_dir/arq.alterado						#reinserção das aspas na lista de arquivos modificados.

	sed -i -r "s|^\"|\"$origem/|" $temp_dir/arq.adicionado						#caminho absoluto no diretório de origem para arquivos e diretórios adicionados ou modificados.
	sed -i -r "s|^\"|\"$origem/|" $temp_dir/arq.alterado

	sed -i -r "s|(^\"$origem/)(.*$)|\$\(cp -f \1\2 \"$destino/\2\)|" $temp_dir/arq.adicionado		
	sed -i -r "s|/[^/]+\"\)$|\"\)|" $temp_dir/arq.adicionado					#cópia de novos arquivos: $(cp -f "<caminho_origem/arquivo_origem>" "<caminho_destino>")

	sed -i -r "s|(^\"$origem/)(.*$)|\$\(cp -f \1\2 \"$destino/\2\)|" $temp_dir/arq.alterado		#sobrescrita de arquivos alterados: $(cp -f "<caminho_origem/arquivo_origem>" "<caminho_destino/arquivo_destino>")

	sed -i -r "s|^\"|\"$destino/|" $temp_dir/arq.excluido						#caminho absoluto no diretório de destino para arquivos e diretórios a serem removidos.
	sed -i -r "s|^\"|\"$destino/|" $temp_dir/dir.adicionado							
	sed -i -r "s|^\"|\"$destino/|" $temp_dir/dir.excluido

	if [ "$modo" == 'd' ]; then
		cat $temp_dir/arq.excluido | xargs --no-run-if-empty rm -f					# 1 - remoção de arquivos marcados para exclusão no destino.
		cat $temp_dir/dir.excluido | xargs --no-run-if-empty rmdir					# 2 - remoção de diretórios marcados para exclusão no destino.
	fi

	cat $temp_dir/dir.adicionado | xargs --no-run-if-empty mkdir -p						# 3 - criação de diretórios no destino. 
	cat $temp_dir/arq.adicionado | xargs --no-run-if-empty -d "\n" -L 1 sh -c				# 4 - cópia de arquivos novos no destino.
	cat $temp_dir/arq.alterado | xargs --no-run-if-empty -d "\n" -L 1 sh -c					# 5 - sobrescrita de arquivos modificados.

	estado="fim_$estado" && echo $estado >> $temp_dir/progresso.txt

	##### HISTORICO DE DEPLOY #####

	estado="log" && echo $estado >> $temp_dir/progresso.txt
	
	let "tamanho_app=$(echo $app | wc -c)-1"

	app_log=$(echo '                ' | sed -r "s|^ {$tamanho_app}|$app|")
	data_log=$(echo $data | sed -r "s|^(....)(..)(..)(..)(..)(..)$|\3/\2/\1      \4h\5m\6s       |")
	rev_log=$(echo $rev | sed -r "s|^(.........).*$|\1|")
	rev_log=$(echo '                ' | sed -r "s|^ {9}|$rev_log|")

	echo -e "$data_log$app_log$rev_log$chamado" >> $historico

	cp $historico $chamados_dir

	grep -i "$app" $historico > $atividade_dir/historico_deploy_$app.txt
	cp $atividade_dir/historico_deploy_$app.txt $chamados_dir/$app

	estado="fim_$estado" && echo $estado >> $temp_dir/progresso.txt

	echo -e "\nDeploy concluído."
else
	echo -e "\nDeploy abortado."
	mv "$atividade_dir" "${atividade_dir}_PENDENTE"
fi

exit

#TODO: averiguar a possibilidade de utilizar o rsync para o diff entre origem e destino. Ex: rsync -rnivc --delete origem/VISAO/ destino/VISAO/ > modificacoes_rsync.txt

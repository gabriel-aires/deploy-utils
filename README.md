# deploy-utils

## Descrição:

Sistema para automatização e rastreabilidade do processo de implantação de releases.

## Dependências:

O sistema foi testado na distribuição Red Hat Enterprise Linux Server 6.7 com os pacotes abaixo:

**Pacote**|**Versão**
----------|----------
bash      |     4.1.2
dos2unix  |       3.1
unix2dos  |       2.2
coreutils |       8.4
findutils |     4.4.2
cifs-utils|     4.8.1
nfs-utils |     1.2.3
samba     |    3.6.23
git       |     1.7.1
rsync     |     3.0.6
grep      |      2.20
sed       |     4.2.1
perl      |    5.10.1
httpd     |    2.2.15

## Instalação:

A última versão estável do sistema pode ser obtida a partir do git. Para a primeira instalação, executar os comandos abaixo como administrador:

### Atualização de pacotes
```
yum update -y
shutdown -r now
```

### Instalação do servidor de deploy
```
cd /opt
git clone git@git.anatel.gov.br:producao/deploy-utils.git
cd /opt/deploy-utils/
./src/server/sh/setup.sh --reconfigure
chkconfig --add deploy_server
chkconfig deploy_server on
```

### Configuração HTTPS (opcional)
```
service deploy_server stop
yum install mod_ssl openssl
openssl genrsa -out ca.key 2048
openssl req -new -key ca.key -out ca.csr
openssl x509 -req -days 365 -in ca.csr -signkey ca.key -out ca.crt
cp ca.crt /etc/pki/tls/certs
cp ca.key /etc/pki/tls/private/ca.key
cp ca.csr /etc/pki/tls/private/ca.csr
vim /opt/deploy-utils/src/server/conf/global.conf  # alterar as variáveis ssl_enable, ssl_crt_path, ssl_key_path e apache_vhost_port
/opt/deploy-utils/src/server/sh/setup.sh
```

### Compartilhamento de diretórios utilizados pelos agentes
```
service nfs stop
chkconfig nfs on
echo /opt/deploy-utils/src/server/conf/agents >> /etc/exports
echo /var/lock/deploy-utils >> /etc/exports
echo /opt/deploy-utils/src/server/log/ >> /etc/exports
echo /opt/deploy-utils/src/server/upload/ >> /etc/exports
vim /etc/exports # editar cada entrada conforme o exemplo a seguir: /var/lock/deploy-utils máquina01(rw,no_root_squash) máquina02(rw,no_root_squash) ...
service nfs restart
```

Para a instalação dos agentes propriamente ditos, referir-se à documentação correspondente no diretório docs.

## Autor:

Gabriel Aires Guedes - airesgabriel@gmail.com

Atualizado pela última vez em 12/04/2016.

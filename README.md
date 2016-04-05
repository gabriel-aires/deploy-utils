# deploy-utils

## Descrição:

Sistema para automatização e rastreabilidade do processo de implantação de releases.

## Dependências:

O sistema foi testado com os pacotes abaixo.

**Pacote**|**Versão**
----------|----------
bash      |     4.1.2
coreutils |       8.4
findutils |     4.4.2
grep      |     2.6.3
cifs-utils|     4.8.1
nfs-utils |     1.2.3
git       |     1.7.1
rsync     |     3.0.6
samba     |    3.6.23
sed       |     4.2.1
perl      |    5.10.1

## Instalação:

A última versão estável do sistema pode ser obtida a partir do git. Para a primeira instalação, executar os comandos abaixo como administrador:

```
cd /opt
git clone git@git.anatel.gov.br:producao/deploy-utils.git
/opt/deploy-utils/src/server/sh/setup.sh --reconfigure
```

## Autor:

Gabriel Aires Guedes - airesgabriel@gmail.com

Atualizado pela última vez em 05/04/2016.

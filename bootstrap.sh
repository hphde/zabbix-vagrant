#!/bin/bash
#set -x
TIMEZONE=${3:-"Europe/Berlin"}
PG_VER='12'
NGX_VER='116'
PHP_VER='72'
ZABBIX_SRVCFG='/etc/zabbix/zabbix_server.conf'
ZABBIX_WEBCFG='/etc/zabbix/web/zabbix.conf.php'

OS_MAJOR=$(cat /etc/redhat-release|grep -oP 'release \K.')
OS_MINOR=$(cat /etc/redhat-release|grep -oP 'release ..\K.')
echo "CentOS variant <$OS_MAJOR>"
case "$OS_MAJOR" in
  7)
    PHPFPM="rh-php$PHP_VER-php-fpm"
    NGX_SERVICE="rh-nginx$NGX_VER-nginx"
    ZABBIX_NGXCFG='/etc/opt/rh/rh-nginx'$NGX_VER'/nginx/conf.d/zabbix.conf'
    ZABBIX_PHPCFG='/etc/opt/rh/rh-php'$PHP_VER'/php-fpm.d/zabbix.conf'
    ;;
  8)
    PHPFPM="php-fpm"
    NGX_SERVICE="nginx"
    ZABBIX_NGXCFG='/etc/nginx/conf.d/zabbix.conf'
    ZABBIX_PHPCFG='/etc/php-fpm.d/zabbix.conf'
    ;;
  *)
    echo "... unexpected. Use 7 or 8. Exiting"
    exit 99
    ;;
esac
PG_CFG='/var/lib/pgsql/'$PG_VER'/data/postgresql.conf'
PG_HBA='/var/lib/pgsql/'$PG_VER'/data/pg_hba.conf'

DB=${1:-mysql}
echo "DB variant <$DB>"
case "$DB" in
  postgresql)
    DB_SHORT="pgsql"
    ;;
  mysql)
    DB_SHORT="mysql"
    ;;
  *)
    echo "... unexpected. Use postgresql or mysql. Exiting"
    exit 99
esac
DBPASSFILE=/root/.DBPASSWORD
if [[ -f $DBPASSFILE ]]; then
  DBPASSWORD=$(cat $DBPASSFILE)
else
  DBPASSWORD=$(openssl rand -base64 14)
  # No (back)slashes to simplify sed handling
  DBPASSWORD=$(echo ${DBPASSWORD//\//.})
  DBPASSWORD=$(echo ${DBPASSWORD//\\/.})
  echo $DBPASSWORD >/root/.DBPASSWORD
fi

WEBSERVER=${2:-apache}
echo "Webserver variant <$WEBSERVER>"
case "$WEBSERVER" in
  nginx)
    WEBSERVICE="$NGX_SERVICE"
    ;;
  apache)
    WEBSERVICE="httpd"
    ;;
  *)
    echo "... unexpected. Use nginx or apache. Exiting"
    exit 99
esac

print_head(){
  echo " "
  echo " * ** ***  $1  *** ** *"
  echo " "
}
disable_selinux(){
  setenforce 0
  sed -i 's/SELINUX=\(enforcing\|permissive\)/SELINUX=disabled/g' /etc/selinux/config
}
base_install(){
  print_head "Base Installation"
  timedatectl set-timezone $TIMEZONE
  localectl set-locale LANG="en_US.UTF-8" LC_CTYPE="en_US"
  yum -y install epel-release
  yum -y update
  yum -y upgrade
  yum -y install net-tools htop checkpolicy
}
mysql_install(){
  print_head "MariaDB (MySQL) Installation"
  yum -y install mariadb mariadb-server
  systemctl enable --now mariadb.service
}
postgres_install(){
  print_head "Postgres Installation"
  yum -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-$OS_MAJOR-x86_64/pgdg-redhat-repo-latest.noarch.rpm
  if [[ "$OS_MAJOR" == "8" ]]; then
    yum -qy module disable postgresql
  fi
  yum -y install postgresql$PG_VER postgresql$PG_VER-server
  PGSETUP_INITDB_OPTIONS='--encoding=UTF8 --locale=C' /usr/pgsql-$PG_VER/bin/postgresql-$PG_VER-setup initdb
  sed -i 's/^host *all *all *127.0.0.1\/32 *ident/host all all 127.0.0.1\/32 md5/' $PG_HBA
  sed -i 's/^host *all *all *::1\/128 *ident/host all all ::1\/128 md5/' $PG_HBA
  # Allow selinux to connect webserver to db
  setsebool -P httpd_can_network_connect_db on
  systemctl enable --now postgresql-$PG_VER
}
timescale_install(){
  print_head "Timescale Installation"
  REPO='/etc/yum.repos.d/timescale_timescaledb.repo'
  cat >$REPO <<'EOF'
[timescale_timescaledb]
name=timescale_timescaledb
baseurl=https://packagecloud.io/timescale/timescaledb/el/OS_MAJOR/$basearch
repo_gpgcheck=1
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/timescale/timescaledb/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
EOF
  sed -i 's/OS_MAJOR/'$OS_MAJOR'/g' $REPO
  yum -y update
  yum -y install timescaledb-postgresql-$PG_VER
  grep -q 'timescaledb.last_tuned_version' $PG_CFG || timescaledb-tune --pg-config=/usr/pgsql-$PG_VER/bin/pg_config -yes
  grep -q "shared_preload_libraries = 'timescaledb'" $PG_CFG || echo "shared_preload_libraries = 'timescaledb'" >> $PG_CFG
  systemctl restart postgresql-$PG_VER.service
}
zabbix_selinux(){
  # setenforce 0
  # grep zabbix_t /var/log/audit/audit.log | audit2allow -M zabbix_server_add
  cat >zabbix_server_add.te <<'EOF'
module zabbix_server_add 1.1;
require {
        type krb5_keytab_t;
        type zabbix_var_run_t;
        type tmp_t;
        type zabbix_t;
        class sock_file { create unlink write };
        class unix_stream_socket connectto;
        class process setrlimit;
        class capability dac_override;
        class dir search;
}
allow zabbix_t krb5_keytab_t:dir search;
allow zabbix_t self:process setrlimit;
allow zabbix_t self:unix_stream_socket connectto;
allow zabbix_t tmp_t:sock_file { create unlink write };
allow zabbix_t zabbix_var_run_t:sock_file { create unlink write };
allow zabbix_t self:capability dac_override;
EOF
  checkmodule -M -m -o zabbix_server_add.mod zabbix_server_add.te
  semodule_package -m zabbix_server_add.mod -o zabbix_server_add.pp
  semodule -i zabbix_server_add.pp
  # getsebool -a | grep zabbix
  setsebool -P zabbix_can_network on
  setsebool -P httpd_can_connect_zabbix on
  setsebool -P httpd_can_network_connect on
}
zabbix_install(){
  print_head "Zabbix Installation"
  yum -y install https://repo.zabbix.com/zabbix/5.0/rhel/$OS_MAJOR/x86_64/zabbix-release-5.0-1.el$OS_MAJOR.noarch.rpm
  yum clean all
  case "$OS_MAJOR" in
    7)
      yum -y install zabbix-server-$DB_SHORT zabbix-agent
      yum -y install centos-release-scl
      sed -i 's/enabled=0/enabled=1/g' /etc/yum.repos.d/zabbix.repo
      yum -y install zabbix-web-$DB_SHORT-scl zabbix-$WEBSERVER-conf-scl
      ;;
    8)
      yum -y install zabbix-server-$DB_SHORT zabbix-web-$DB_SHORT zabbix-$WEBSERVER-conf zabbix-agent
      ;;
  esac
  case "$DB" in
    postgresql)
      sudo -i -u postgres createuser zabbix
      sudo -i -u postgres psql -c "ALTER USER zabbix WITH PASSWORD '"$DBPASSWORD"';"
      sudo -i -u postgres createdb -O zabbix zabbix
      zcat /usr/share/doc/zabbix-server-pgsql*/create.sql.gz | sudo -u zabbix psql zabbix >/dev/null 2>&1
      echo "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;" | sudo -u postgres psql zabbix
      zcat /usr/share/doc/zabbix-server-pgsql*/timescaledb.sql.gz | sudo -u zabbix psql zabbix >/dev/null 2>&1
      ;;
    mysql)
      SQL="create database zabbix character set utf8 collate utf8_bin;"
      SQL+="create user zabbix@localhost identified by '$DBPASSWORD';"
      SQL+="grant all privileges on zabbix.* to zabbix@localhost;"
      mysql -uroot -e "$SQL"
      zcat /usr/share/doc/zabbix-server-mysql*/create.sql.gz | mysql -uzabbix -p$DBPASSWORD zabbix
      ;;
  esac
  sed -i 's/^# *DBPassword=.*$/DBPassword='$DBPASSWORD'/' $ZABBIX_SRVCFG
  sed -i 's/^DBPassword=.*$/DBPassword='$DBPASSWORD'/' $ZABBIX_SRVCFG
  sed -i 's/^; php_value\[date.timezone] = Europe\/Riga/php_value[date.timezone] = '$(echo ${TIMEZONE/\//\\\/})'/' $ZABBIX_PHPCFG
  if [[ "$WEBSERVER" == "nginx" ]]; then
    sed -i 's/^listen.acl_users = apache$/listen.acl_users = apache,nginx/' $ZABBIX_PHPCFG
    sed -i 's/^# *listen *80;/listen 80;/' $ZABBIX_NGXCFG
    sed -i 's/^# *server_name *example.com;/server_name localhost;\nserver_name '$(hostname)';/' $ZABBIX_NGXCFG
  fi
  zabbix_selinux
  cat >$ZABBIX_WEBCFG <<'EOF'
<?php
$DB['TYPE'] = 'DBVARIANT';
$DB['SERVER'] = 'localhost';
$DB['PORT'] = '0';
$DB['DATABASE'] = 'zabbix';
$DB['USER'] = 'zabbix';
$DB['PASSWORD'] = 'DBPASSWORD';
$DB['SCHEMA'] = '';
$DB['ENCRYPTION'] = false;
$DB['KEY_FILE'] = '';
$DB['CERT_FILE'] = '';
$DB['CA_FILE'] = '';
$DB['VERIFY_HOST'] = false;
$DB['CIPHER_LIST'] = '';
$DB['DOUBLE_IEEE754'] = true;
$ZBX_SERVER = 'localhost';
$ZBX_SERVER_PORT = '10051';
$ZBX_SERVER_NAME = 'Zabbix';
$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
EOF
  sed -i 's/DBPASSWORD/'$DBPASSWORD'/' $ZABBIX_WEBCFG
  sed -i 's/DBVARIANT/'$(echo ${DB^^})'/' $ZABBIX_WEBCFG
  systemctl restart zabbix-server zabbix-agent $WEBSERVICE $PHPFPM
  systemctl enable zabbix-server zabbix-agent $WEBSERVICE $PHPFPM
}
db_install(){
  print_head "Database Installation"
  case "$DB" in
    postgresql)
      postgres_install
      timescale_install
      ;;
    mysql)
      mysql_install
      ;;
  esac
}
db_cleanup(){
  print_head "Zabbix DB Cleanup"
  case "$DB" in
    postgresql)
      sudo -i -u postgres dropdb zabbix >/dev/null 2>&1
      sudo -i -u postgres dropuser zabbix >/dev/null 2>&1
      ;;
    mysql)
      SQL="drop database zabbix;"
      SQL+="drop user zabbix@localhost;"
      mysql -uroot -e "$SQL" >/dev/null 2>&1
      ;;
  esac
}
# This Vagrant works with selinux but just in case you have troubles...
#disable_selinux
base_install
db_install
db_cleanup
zabbix_install
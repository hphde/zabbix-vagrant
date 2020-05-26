# Zabbix V5 Vagrant

## Contents

Default:
Zabbix 5, MariaDB (mysql), Apache, CentOS 8

## Alternatives

* CentOS: 7 or 8
* Database: MariaDB (mysql) or PostgreSQL+TimescaleDB
* Webserver: Apache or NGinx

NOTES:

* MariaDB is v5.5 with CentOS7 and V10.3 with CentOS8
* PostgreSQL12/CentOS8 has no TimescaleDB available yet, thus v11 is used

## Howto

Checkout repo, cd to it and run `vagrant up`

Create `.env` file for alternatives and options:

```ruby
BOX='centos/7'
DB='postgresql'
WEBSERVER='nginx'
#MEM = 1024
#CPUS = 2
#BOOTSTRAP = 'bootstrap.sh'
#NETWORK_MASK = 24
#NETWORK_BASE = '192.168.56.0'
ZABBIXPORT = 9090
#TIMEZONE = 'Europe/Berlin'
```

Zabbix is reachable over the URLs that Vagrant spits out in the end. Credentials are the Zabbix defaults `Admin/zabbix`

NOTE: The database password is generated randomly and stored under `/root/.DBPASSWORD` - if you remove/edit the file, contents will be regenerated/distributed.

## Using without Vagrant

You could run `bootstrap.sh` standalone on CentOS 7 or 8 and it will install Zabbiv 5 with MariaDB and Apache by default. The script accepts three parameters. The first is the database variant (`mysql` or `postgresql`), the second is the webserver variant (`apache` or `nginx`) and the last is the timezone - default `Europe/Berlin`. The script hasn't been tested on RHEL, so it might need some additional adjustments for that.

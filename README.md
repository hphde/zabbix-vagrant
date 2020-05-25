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

Create `.env` file for alternatives and options with

```ruby
BOX='centos/7'
DB='postgresql'
WEBSERVER='nginx'
#MEM = 1024
#CPUS = 2
#BOOTSTRAP = 'bootstrap.sh'
#NETWORK_MASK = 24
#NETWORK_BASE = '192.168.56.0'
```

Zabbix is reachable over <http://localhost:8080/zabbix> if running in a local VM and over the machine it spits out in the end  
For example <http://192-168-56-3.sslip.io/> (nginx) or <http://192-168-56-3.sslip.io/zabbix> (apache)

Credentials are the Zabbix defaults `Admin/zabbix`

NOTE: The database password is generated randomly and stored under `/root/.DBPASSWORD` - if you remove/edit the file, contents will be regenerated/distributed.

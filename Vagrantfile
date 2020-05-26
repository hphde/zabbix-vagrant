Vagrant.configure("2") do |config|
  config.env.enable

  BOX = ENV['BOX'] || 'centos/8'
  DB = ENV['DB'] || 'mysql'
  WEBSERVER = ENV['WEBSERVER'] || 'apache'
  NETWORK_MASK = ENV['NETWORK_MASK'] || 24
  NETWORK_BASE = ENV['NETWORK_BASE'] || '192.168.56.0'
  MEM = ENV['MEM'] || 1024
  CPUS = ENV['CPUS'] || 2
  BOOTSTRAP = ENV['BOOTSTRAP'] || 'bootstrap.sh'
  ZABBIXPORT = ENV['ZABBIXPORT'] || 8080

  NETWORK = IPAddr.new(NETWORK_BASE).mask(NETWORK_MASK)
  HOST_IP = NETWORK | IPAddr.new('0.0.0.3')
  # sslip.io nip.io xip.io
  DNS_PROVIDER = "sslip.io"
  HOST_NAME = "#{HOST_IP.to_s.gsub('.','-')}.#{DNS_PROVIDER}"
end

Vagrant.configure("2") do |config|
  config.vm.box_check_update = false

  # vagrant plugin install vagrant-env

  # Type
  config.vm.box = BOX.to_s

  # Use generated hostname
  config.vm.hostname = HOST_NAME.to_s

  # Provider Settings
  config.vm.provider "virtualbox" do |vb|
    vb.memory = MEM.to_s
    vb.cpus = CPUS.to_s
    vb.customize ["modifyvm", :id, "--audio", "none"]
  end

  # Network Settings
  config.vm.network "private_network", ip: HOST_IP.to_s
  config.vm.network :forwarded_port, guest: 80, host: ZABBIXPORT.to_s

  # Folder Settings
  # Disable the default share
  config.vm.synced_folder ".", "/vagrant", disabled: true
  # sync on up or reload
  #config.vm.synced_folder "data", "/data", type: "rsync", rsync__exclude: ".git/"
  # shared folder works only with vbox guest additions
  #config.vm.synced_folder "data", "/data", :mount_options => ["dmode=777", "fmode=666"]
  
  # Bootstrapping
  config.vm.provision "shell", path: BOOTSTRAP.to_s, args: [DB.to_s, WEBSERVER.to_s]

  # Show info
  if WEBSERVER == 'nginx'
    URL = ''
  else
    URL = 'zabbix'
  end
  config.vm.post_up_message = "Zabbix is available at http://localhost:#{ZABBIXPORT}/#{URL} or http://#{HOST_NAME}/#{URL}"
end

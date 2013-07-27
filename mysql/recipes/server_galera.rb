#
# Cookbook Name:: mysql
# Recipe:: server_galera
#
# Copyright 2012, AT&T Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)

include_recipe "mysql::client"

if Chef::Config[:solo]
  missing_attrs = %w{
    server_debian_password server_root_password server_repl_password
  }.select do |attr|
    node["mysql"][attr].nil?
  end.map { |attr| "node['mysql']['#{attr}']" }

  if !missing_attrs.empty? or node["wsrep"]["password"].nil?
    Chef::Application.fatal!([
        "You must set #{missing_attrs.join(', ')} in chef-solo mode.",
        "For more information, see https://github.com/opscode-cookbooks/mysql#chef-solo-note"
      ].join(' '))
  end

  if node['galera']['nodes'].empty?
    fail_msg = "You must set node['galera']['nodes'] to a list of IP addresses or hostnames for each node in your cluster if you are using Chef Solo"
    Chef::Application.fatal!(fail_msg)
  end
  cluster_addresses = node["galera"]["nodes"]
  # Just assume first node is reference node...
  reference_node = node["galera"]["nodes"][0]
else
  # generate all passwords
  node.set_unless['mysql']['server_debian_password'] = secure_password
  node.set_unless['mysql']['server_root_password']   = secure_password
  node.set_unless['mysql']['server_repl_password']   = secure_password
  node.set_unless['wsrep']['password']               = secure_password

  # SST authentication string. This will be used to send SST to joining nodes.
  # Depends on SST method. For mysqldump method it is wsrep_sst:<wsrep password>
  node.set['wsrep']['sst_auth'] = "#{node['wsrep']['user']}:#{node['wsrep']['password']}"
  
  # Note: actually this block need move to some initial recipe which will run at start any role on every node
  # This block needs to make search role from node attributes
  node.save
  sttime=Time.now.to_f
  allnodes = search(:node, "chef_environment:#{node.chef_environment}")
  allnodes.each do |nd|
    while nd["roles"].nil?||nd.key?("roles")&&nd["roles"].empty? do
      if (Time.now.to_f-sttime)>=sttime
        Chef::Application.fatal! "Timeout exceeded while roles syncing on node #{nd.name}.."
      else
        ::Chef::Log.info "Found that chef-client on node #{nd.name} was never launched or unsucceful ended. Please re-run chef-client or remove that node from curren chef_environment.."
        sleep 10
        nd = search(:node, "name:#{nd.name} AND chef_environment:#{node.chef_environment}")[0]
      end
    end
  end

  galera_role = node["galera"]["chef_role"]
  galera_reference_role = node["galera"]["reference_node_chef_role"]
  cluster_name = node["wsrep"]["cluster_name"]
  cluster_addresses = []

  ::Chef::Log.info "Searching for nodes having role '#{galera_role}' and cluster name '#{cluster_name}'"
  # Shorter query format (alff), also reduce result count by chef_environment
  results = search(:node, "role:#{galera_role} AND wsrep_cluster_name:#{cluster_name} AND chef_environment:#{node.chef_environment}")
  galera_nodes = results

  if results.empty?
    ::Chef::Application.fatal!("Searched for role #{galera_role} and cluster name #{cluster_name} found no nodes. Exiting.")
  elsif results.size < 3
    ::Chef::Application.fatal!("You need at least three Galera nodes in the cluster. Found #{results.size}. Exiting.")
  else
    ::Chef::Log.info "Found #{results.size} nodes in cluster #{cluster_name}."
    # Now we grab each node's IP address and store in our cluster_addresses array
    results.each do | result |
    if result['mysql']['bind_interface']
      address = result['network']["ipaddress_#{result['mysql']['bind_interface']}"]
    else
      address = result['mysql']['bind_address']
    end
    unless result.name == node.name
      ::Chef::Log.info "Adding #{address} to list of cluster addresses in cluster '#{cluster_name}'."
      cluster_addresses << address
    end
    end
    
    ::Chef::Log.info "Searching for reference node having role '#{galera_reference_role}' in cluster '#{cluster_name}'"
    results = search(:node, "role:#{galera_reference_role} AND wsrep_cluster_name:#{cluster_name} AND chef_environment:#{node.chef_environment}")
    if results.empty?
      ::Chef::Application.fatal!("Could not find node with reference role. Exiting.")
    elsif results.size != 1
      ::Chef::Application.fatal!("Can only be a single node in cluster '#{cluster_name}' with reference role. Found #{results.size}. Exiting.")
    else
      reference_node = results[0]
    end
  end
  node.save
end

# Compose list of galera ip's
wsrep_ip_list = "gcomm://" + cluster_addresses.join(',')


if platform_family?('windows') or platform_family?('mac_os_x')
  fail_msg = "Windows and Mac OSX is not supported by the Galera MySQL solution."
  Chef::Application.fatal!(fail_msg)
end

# If the user does have the bind_interface set, override
# the bind_address with whatever address corresponds to the
# interface.
if node['mysql']['bind_interface']
  node.set['mysql']['bind_address'] = node['network']["ipaddress_#{node['mysql']['bind_interface']}"]
end
#if reference_node['mysql']['bind_interface']
#  reference_address = reference_node['network']["ipaddress_#{reference_node['mysql']['bind_interface']}"]
#else
#  reference_address = reference_node['mysql']['bind_address']
#end
#is_reference_node = (reference_address == node["mysql"]["bind_address"])

# Install all support packages first
packages = node['galera']['support_packages'].split(" ")
packages.each do | pack |
  package pack do
    action :install
  end
end

# Download, cache, then install the Galera WSREP package
arch = node['kernel']['machine']
download_root = node['galera']['packages']['galera']['download_root']
galera_package = node['galera']['packages']['galera'][arch]
Chef::Log.info "Downloading #{galera_package}"
remote_file "#{Chef::Config[:file_cache_path]}/#{galera_package}" do
  source "#{download_root}/#{galera_package}"
  action :create_if_missing
end

dpkg_package "#{galera_package}" do
  source "#{Chef::Config[:file_cache_path]}/#{galera_package}"
end

# Download, cache, and then install the custom MySQL server for Galera package
download_root = node['galera']['packages']['mysql_server']['download_root']
mysql_server_package = node['galera']['packages']['mysql_server'][arch]
Chef::Log.info "Downloading #{mysql_server_package}"
remote_file "#{Chef::Config[:file_cache_path]}/#{mysql_server_package}" do
  source "#{download_root}/#{mysql_server_package}"
  action :create_if_missing
end

dpkg_package "#{mysql_server_package}" do
  source "#{Chef::Config[:file_cache_path]}/#{mysql_server_package}"
end

[File.dirname(node['mysql']['pid_file']),
  File.dirname(node['mysql']['tunable']['slow_query_log']),
  node['mysql']['confd_dir'],
  node['mysql']['log_dir'],
  node['mysql']['data_dir']].each do |directory_path|
  directory directory_path do
    owner "mysql"
    group "mysql"
    action :create
    recursive true
  end
end

file node["galera"]["mysqld_pid"] do
  owner "mysql"
  group "mysql"
end

# The following variables in the my.cnf MUST BE set
# this way for Galera to work properly.
node.set['mysql']['tunable']['binlog_format'] = "ROW"
node.set['mysql']['tunable']['innodb_autoinc_lock_mode'] = "2"
node.set['mysql']['tunable']['innodb_locks_unsafe_for_binlog'] = "1"
node.set['mysql']['tunable']['innodb_support_xa'] = "0"

# Doesn't look like the MySQL binaries from codership will start
# with --skip-federated...
skip_federated = false

service "mysql" do
  service_name node['mysql']['service_name']
  supports :status => true, :restart => true, :reload => true
  action :nothing
  provider Chef::Provider::Service::Upstart
end

template "#{node['mysql']['conf_dir']}/my.cnf" do
  source "my.cnf.erb"
  owner "root"
  group node['mysql']['root_group']
  mode 00644
  notifies :restart, resources(:service => "mysql")
  variables(
    "skip_federated" => skip_federated
  )
end

sst_receive_address = node['network']["ipaddress_#{node['wsrep']['sst_receive_interface']}"]
template "#{node['mysql']['confd_dir']}/wsrep.cnf" do
  source "wsrep.cnf.erb"
  owner "root"
  group node['mysql']['root_group']
  mode 00644
  notifies :restart, "service[mysql]"
  variables(
    "sst_receive_address" => sst_receive_address,
    "wsrep_cluster_address" => wsrep_ip_list,
    "wsrep_node_address" => node['mysql']['bind_address']
  )
end

# Resources as a functions block`
# Check if wsrep status is "synced"
script "Check-sync-status" do
  user "root"
  interpreter "bash"
  code <<-EOH
  TIMER=#{node["galera"]["global_timer"]}
  until [ $TIMER -lt 1 ]; do
  /usr/bin/mysql -p#{node['mysql']['server_root_password']} -Nbe "show status like 'wsrep_local_state_comment'" | /bin/grep -q Synced
  rs=$?
  if [[ $rs == 0 ]] ; then
  exit 0
  fi
  echo Waiting for sync..
  sleep 5
  let TIMER-=5
  done
  exit 1
  EOH
  action :nothing
end

# Set flag that first stage of galera cluster init completed
ruby_block "Set-initial_replicate-state" do
  block do
    node.set_unless["galera"] ||={}
    node.set_unless["galera"]["cluster_initial_replicate"] = "ok"
    node.save
  end
  action :nothing
end

# Search that all galera nodes finished first stage
# of galera cluster initialization
ruby_block "Search-other-galera-mysql-servers" do
  block do
    galera_nodes.each do |result|
      # Remove reference from check
      if result.run_list.role_names.include?(galera_reference_role)
        next
      end
      hash = {}
      hash["attr"] = "galera"
      hash["key"] = "cluster_initial_replicate"
      hash["var"] = "ok"
      hash["timeout"] = node["galera"]["global_timer"]
      hash["sttime"]=Time.now.to_f
      check_state_attr(result,hash)
    end
  end
  action :nothing
end

# Set final flag that current node have fully working status
ruby_block "Cluster-ready" do
  block do
    node.set["galera"]["cluster_status"] = "ready"
  end
  action :nothing
end
# End of block


# Is this node reference node or not.
if node.run_list.role_names.include?(galera_reference_role)
  master = true
else
  master = false
end

# Start of galera cluster configuration
unless node["galera"]["cluster_initial_replicate"] == "ok"
  if master
    wsrep_cluster_address = "gcomm://"

    # TODO: It would be nice if we could implement howto check that mysql 
    # proccess is accepting connections and remove from script ugly 'sleep'.
    # Start mysql daemon in cluster initialization mode
    script "create-cluster" do
      user "root"
      interpreter "bash"
      code <<-EOH
      mysqld --pid-file=#{node["galera"]["mysqld_pid"]} --wsrep_cluster_address=#{wsrep_cluster_address} &>1 &
      sleep 10
      EOH
    end

    # Install new empty system DB
    execute 'mysql-install-db' do
      command "mysql_install_db"
      action :run
      # Do not need to install databases on non-reference nodes since
      # SST will replicate the databases to those nodes
      not_if { File.exists?(node['mysql']['data_dir'] + '/mysql/user.frm') }
    end

    # set the root password for situations that don't support pre-seeding.
    # (eg. platforms other than debian/ubuntu & drop-in mysql replacements)
    execute "assign-root-password" do
      command "\"#{node['mysql']['mysqladmin_bin']}\" -u root password \"#{node['mysql']['server_root_password']}\""
      action :run
      only_if "\"#{node['mysql']['mysql_bin']}\" -u root -e 'show databases;'"
    end

    # Make some clean
    execute "delete-blank-users" do
      sql_command = "SET wsrep_on=OFF; DELETE FROM mysql.user WHERE user='';"
      command %Q["#{node['mysql']['mysql_bin']}" -u root #{node['mysql']['server_root_password'].empty? ? '' : '-p' }"#{node['mysql']['server_root_password']}" -e "#{sql_command}"]
      action :run
    end

    # Grant access to wsrep user
    wsrep_user = node['wsrep']['user']
    wsrep_pass = node['wsrep']['password']
    execute "grant-wsrep-user" do
      sql_command = "SET wsrep_on=OFF; GRANT ALL ON *.* TO #{wsrep_user}@'%' IDENTIFIED BY '#{wsrep_pass}';"
      command %Q["#{node['mysql']['mysql_bin']}" -u root #{node['mysql']['server_root_password'].empty? ? '' : '-p' }"#{node['mysql']['server_root_password']}" -e "#{sql_command}"]
      action :run
      notifies :run, "script[Check-sync-status]", :immediately
      notifies :create, "ruby_block[Set-initial_replicate-state]", :immediately
      notifies :create, "ruby_block[Search-other-galera-mysql-servers]", :immediately
    end

    # Check that all non-reference nodes are in operating condition
    ruby_block "Check-cluster-status" do
      block do
        galera_nodes.each do |result|
          # Remove reference from check
          if result.run_list.role_names.include?(galera_reference_role)
            next
          end
          hash = {}
          hash["attr"] = "galera"
          hash["key"] = "cluster_status"
          hash["var"] = "ready"
          hash["timeout"] = 300
          hash["sttime"]=Time.now.to_f
          check_state_attr(result,hash)
        end
      end
    end

    # Block to stop mysql proccess by pid when all non-reference nodes are  ALREADY working with correct config
    script "Stop-master-galera-server" do
      interpreter "bash"
      code <<-EOH
      kill `cat #{node["galera"]["mysqld_pid"]}`
      ps ax|grep -v grep|grep -q rsync_sst.conf
      ss=$?
      if [[ $ss == 0 ]] ; then
      kill `cat #{node["galera"]["rsync_pid"]}`
      fi
      TIMER=60
      until [ $TIMER -lt 1 ]; do
      ps ax|grep -v grep|grep -q mysql
      rs=$?
      if [[ $rs == 1 ]] ; then
      sleep 5
      exit 0
      fi
      echo Stopping mysqld proccess. Please wait a little while..
      sleep 5
      let TIMER-=5
      done
      exit 1
      EOH
      # After that start mysql service in normal mode
      notifies :start, "service[mysql]", :immediately
      # Check that service succesfuly started
      notifies :run, "script[Check-sync-status]", :immediately
      # Set flag that reference node is in operating condition
      notifies :create, "ruby_block[Cluster-ready]"
    end
  else
    wsrep_cluster_address = wsrep_ip_list

    # Waiting for start reference node in cluster mode initialization mode
    ruby_block "Check-master-state" do
      block do
        sttime=Time.now.to_f
        result = reference_node
        until result.attribute?("galera")&&result["galera"].key?("cluster_initial_replicate")&&result["galera"]["cluster_initial_replicate"]=="ok" do
          if (Time.now.to_f-sttime)>=300
            Chef::Log.error "Timeout exceeded while reference node #{result.name} syncing.."
            exit 1
          else
            Chef::Log.info "Waiting while node #{result.name} syncing.."
            sleep 10
            result = search(:node, "name:#{result.name} AND chef_environment:#{node.chef_environment}")[0]
          end
        end
      end
      # Start mysql service
      notifies :start, "service[mysql]", :immediately
      # Check that all non-reference nodes are synced with reference node
      notifies :run, "script[Check-sync-status]", :immediately
      notifies :create, "ruby_block[Set-initial_replicate-state]", :immediately
      notifies :create, "ruby_block[Search-other-galera-mysql-servers]", :immediately
      # Set flag that non-reference node is in operating condition
      notifies :create, "ruby_block[Cluster-ready]"
    end

  end
end

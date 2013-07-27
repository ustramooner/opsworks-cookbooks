#
# Cookbook Name:: mysql
# Recipe:: galera_packages
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

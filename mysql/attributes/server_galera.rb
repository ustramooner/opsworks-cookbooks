#
# Cookbook Name:: mysql
# Attributes:: server_galera
#
# Copyright 2012, AT&T Inc.
# Portions of this file from the serveralnines.com cookbook
# called galera:
# https://github.com/severalnines/S9s_cookbooks/tree/master/galera
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

# Interface on this node to bind MySQL to.
default['mysql']['bind_interface'] = 'eth0'

default['mysql']['version'] = '5.5.28'

default['galera']['packages']['mysql_server']['download_root'] = "https://launchpad.net/codership-mysql/5.5/5.5.28-23.7/+download/"
default['galera']['packages']['galera']['download_root'] = "https://launchpad.net/galera/2.x/23.2.2/+download/"

case node['platform']
when 'centos', 'redhat', 'fedora', 'suse', 'scientific', 'amazon'
  default['galera']['support_packages'] = "openssl psmisc libaio wget rsync nc"
  default['galera']['packages']['galera']['i386'] = 'galera-23.2.2-1.rhel5.i386.rpm'
  default['galera']['packages']['galera']['x86_64'] = 'galera-23.2.2-1.rhel5.x64_64.rpm'
  default['galera']['packages']['mysql_server']['i386'] = 'MySQL-server-5.5.28_wsrep_23.7-1.rhel5.i386.rpm'
  default['galera']['packages']['mysql_server']['x86_64'] = 'MySQL-server-5.5.28_wsrep_23.7-1.rhel5.x86_64.rpm'
  default['wsrep']['provider'] = "/usr/lib64/galera/libgalera_smm.so"
else
  default['galera']['support_packages'] = "libssl0.9.8 psmisc libaio1 wget rsync netcat"
  default['galera']['packages']['galera']['i386'] = 'galera-23.2.2-i386.deb'
  default['galera']['packages']['galera']['x86_64'] = 'galera-23.2.2-amd64.deb'
  default['galera']['packages']['mysql_server']['i386'] = 'mysql-server-wsrep-5.5.28-23.7-i386.deb'
  default['galera']['packages']['mysql_server']['x86_64'] = 'mysql-server-wsrep-5.5.28-23.7-amd64.deb'
  default['wsrep']['provider'] = "/usr/lib/galera/libgalera_smm.so"
end

# Define galera pid's
default["galera"]["mysqld_pid"] = "/var/run/cluster_init.pid"
default["galera"]["rsync_pid"] = "/var/lib/mysql//rsync_sst.pid"

# Define timeouts
default["galera"]["global_timer"] = 300
default["galera"]["local_timer"] = 60

# The name of the Chef role for servers involved in a Galera cluster
# When writing the wsrep_urls, the recipe searches for nodes that
# are assigned this Chef role and have a matching wsrep_cluster_name
default['galera']['chef_role'] = 'galera'

# The name of the Chef role for servers that are the reference node
# in a cluster. The reference node is the first server in a cluster
# started and, if taken out of load-balancing rotation, can serve
# as the node that is most easily used as a backup and conflict resolver.
default['galera']['reference_node_chef_role'] = 'galera-reference'

# Sets debug logging in the WSREP adapter
default['wsrep']['debug'] = false

# The user of the MySQL user that will handle WSREP SST communication.
# Note that this user's password is set via secure_password in the
# server_galera recipe, like other passwords are set in the MySQL
# cookbooks.
default['wsrep']['user'] = "wsrep_sst"

# Port that SST communication will go over.
default['wsrep']['port'] = 4567

# Options specific to the WSREP provider.
default['wsrep']['provider_options'] = ""

# Logical cluster name. Should be the same for all nodes in the cluster.
default['wsrep']['cluster_name'] = "my_galera_cluster"

# How many threads will process writesets from other nodes
# (more than one untested)
default['wsrep']['slave_threads'] = 1

# Generate fake primary keys for non-PK tables (required for multi-master
# and parallel applying operation)
default['wsrep']['certify_non_pk'] = 1

# Maximum number of rows in write set
default['wsrep']['max_ws_rows'] = 131072

# Maximum size of write set
default['wsrep']['max_ws_size'] = 1073741824

# how many times to retry deadlocked autocommits
default['wsrep']['retry_autocommit'] = 1

# change auto_increment_increment and auto_increment_offset automatically
default['wsrep']['auto_increment_control'] = 1

# enable "strictly synchronous" semantics for read operations
default['wsrep']['casual_reads'] = 0

# State Snapshot Transfer method. Note that if you set this
# to mysqldump, you will need to set wsrep_user above to root.
default['wsrep']['sst_method'] = "rsync"

# Interface on this node to receive SST communication.
default['wsrep']['sst_receive_interface'] = 'eth0'

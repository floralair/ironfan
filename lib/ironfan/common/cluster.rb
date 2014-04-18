#
#   Copyright (c) 2012-2014 VMware, Inc. All Rights Reserved.
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

require 'ironfan'
require 'ironfan/common/facet'
require 'ironfan/common/server'
require 'ironfan/common/server_slice'

module Ironfan
  module Common
    CLUSTER_DEF_KEY = 'cluster_definition'
    GROUPS_KEY = 'groups'
    CLUSTER_CONF_KEY = 'cluster_configuration'
    RACK_TOPOLOGY_POLICY_KEY = 'rack_topology_policy'
    HTTP_PROXY = 'http_proxy'
    NO_PROXY = 'no_proxy'

    class Cluster < Ironfan::Cluster

      def initialize(provider, *args)
        super(provider, *args)
      end

      def new_facet(*args)
        Ironfan::Common::Facet.new(*args)
      end

      def sync_cluster_role
        super
        save_rack_topology
      end

      protected

      def create_cluster_role
        super
        save_cluster_configuration
        save_http_proxy_configuration
        save_general_configuration
      end

      def new_slice(*args)
        Ironfan::Common::ServerSlice.new(*args)
      end

      # Save cluster configuration into cluster role
      def save_cluster_configuration
        conf = cluster_attributes(CLUSTER_CONF_KEY)
        conf ||= {}
        merge_to_cluster_role({ CLUSTER_CONF_KEY => conf })
      end

      def save_general_configuration
        # The standard OS yum repos means the default yum repos for CentOS/RHEL.
        # Serengeti has installed the required RPMs from default yum repos into Serengeti internal yum server,
        # so the default yum repos will be disabled by default. This can speed up yum installation significantly.
        # If any RPM from standard yum repos is not in Serengeti internal yum server, you can add the RPM into Serengeti internal yum server,
        # or add "knife[:enable_standard_os_yum_repos] = true" into /opt/serengeti/.chef/knife.rb
        conf = {}
        conf[:enable_standard_os_yum_repos] = Chef::Config[:knife][:enable_standard_os_yum_repos] || false
        merge_to_cluster_role(conf)
      end

      # Save http_proxy setting
      def save_http_proxy_configuration
        conf = {}
        conf[:http_proxy] = cluster_attributes(HTTP_PROXY)
        conf[:http_proxy] = nil if conf[:http_proxy].to_s.empty?
        conf[:no_proxy] = cluster_attributes(NO_PROXY)
        conf[:no_proxy] = nil if conf[:no_proxy].to_s.empty?
        merge_to_cluster_role(conf)
        # http_proxy and no_proxy will be used in chef bootstrap script
        Chef::Config[:knife][:bootstrap_proxy] = conf[:http_proxy]
        Chef::Config[:knife][:bootstrap_no_proxy] = conf[:no_proxy]
      end

      # save rack topology used by Hadoop
      def save_rack_topology
        topology_policy = cluster_attributes(RACK_TOPOLOGY_POLICY_KEY)
        topology_policy.upcase! if topology_policy
        topology_enabled = (topology_policy and topology_policy != 'NONE')
        topology_hve_enabled = (topology_policy and topology_policy == 'HVE')

        topology = self.servers.collect do |svr|
          vm = svr.fog_server
          next if !vm or !vm.ipaddress or !vm.physical_host
          rack = vm.rack.to_s.empty? ? 'default-rack' : vm.rack
          case topology_policy
          when 'RACK_AS_RACK'
            vm.all_ip_addresses.collect { |ip| "#{ip} /#{rack}" }.join("\n")
          when 'HOST_AS_RACK'
            vm.all_ip_addresses.collect { |ip| "#{ip} /#{vm.physical_host}" }.join("\n")
          when 'HVE'
            vm.all_ip_addresses.collect { |ip| "#{ip} /#{rack}/#{vm.physical_host}" }.join("\n")
          else
            nil
          end
        end
        topology = topology.join("\n")

        conf = {
          :hadoop => {
            :rack_topology => {
              :enabled => topology_enabled,
              :hve_enabled => topology_hve_enabled,
              :data => topology
            }
          }
        }
        Chef::Log.debug('saving Rack Topology to cluster role: ' + conf.to_s)
        merge_to_cluster_role(conf)
      end

      def cluster_attributes(key)
        Ironfan::IaasProvider.cluster_spec[CLUSTER_DEF_KEY][key] rescue nil
      end
    end
  end
end

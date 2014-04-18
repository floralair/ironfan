#
#   Portions Copyright (c) 2012-2014 VMware, Inc. All Rights Reserved.
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

require 'ironfan/ec2/facet'
require 'ironfan/ec2/server'
require 'ironfan/ec2/server_slice'

module Ironfan
  module Ec2

    class Cluster < Ironfan::Common::Cluster

      def initialize(*args)
        super(:ec2, *args)
      end

      def discover!
        @aws_instance_hash = {}
        super
        discover_volumes!
      end

      def discover_volumes!
        servers.each(&:discover_volumes!)
      end

      def discover_addresses!
        servers.each(&:discover_addresses!)
      end

      def after_cloud_created(attrs)
        role('ssh')
        create_cluster_security_group unless attrs[:no_security_group]
      end

      def security_groups
        cloud.security_groups
      end

      # Create a security group named for the cluster
      # which is friends with everything in the cluster
      def create_cluster_security_group
        clname = self.name # put it in scope
        cloud.security_group(clname){ authorize_group(clname) }
      end

      protected

      def fog_servers
        @fog_servers = @cloud.fog_servers.select{|fs| fs.key_name == cluster_name.to_s && (fs.state != "terminated") }
      end

      def new_facet(*args)
        Ironfan::Ec2::Facet.new(*args)
      end

      def new_slice(*args)
        Ironfan::Ec2::ServerSlice.new(*args)
      end

    end

  end
end
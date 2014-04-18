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

module Ironfan
  module Ec2
    class ServerSlice < Ironfan::ServerSlice

      # Return security groups
      def security_groups
        sg = {}
        servers.each{|svr| sg.merge!(svr.security_groups) }
        sg
      end

      # Create security keypairs
      def sync_keypairs
        step("ensuring keypairs exist")
        keypairs  = servers.map{|svr| [svr.cluster.cloud.keypair, svr.cloud.keypair] }.flatten.map(&:to_s).reject(&:blank?).uniq
        keypairs  = keypairs - cloud.fog_keypairs.keys
        keypairs.each do |keypair_name|
          keypair_obj = Ironfan::Ec2Keypair.create!(keypair_name)
          cloud.fog_keypairs[keypair_name] = keypair_obj
        end
      end

      # Create security groups, their dependencies, and synchronize their permissions
      def sync_security_groups
        step("ensuring security groups exist and are correct")
        security_groups.each{|name,group| group.run }
      end

      #
      # Override VM actions methods defined in parent class
      #

      def sync_to_cloud
        sync_keypairs
        sync_security_groups
        super
      end

      def display hh = :default
        headings =
          case hh
          when :minimal  then MINIMAL_HEADINGS
          when :default  then DEFAULT_HEADINGS
          when :expanded then EXPANDED_HEADINGS
          else hh.to_set
          end
        headings += ["Bogus"] if servers.any?(&:bogus?)
        defined_data = servers.map do |svr|
          hsh = {
            "Name"   => svr.fullname,
            "Facet"  => svr.facet_name,
            "Index"  => svr.facet_index,
            "Chef?"  => (svr.chef_node? ? "yes" : "[red]no[reset]"),
            "Bogus"  => (svr.bogus? ? "[red]#{svr.bogosity}[reset]" : ''),
            "Env"    => svr.environment,
          }
          # if (cs = svr.chef_server)
          #   hsh.merge!(
          #     "Env"    => cs.environment,
          #     )
          # end
          if (fs = svr.fog_server)
            hsh.merge!(
              "InstanceID" => (fs.id && fs.id.length > 0) ? fs.id : "???",
              "Flavor"     => fs.flavor_id,
              "Image"      => fs.image_id,
              "AZ"         => fs.availability_zone,
              "SSH Key"    => fs.key_name,
              "State"      => "[#{MACHINE_STATE_COLORS[fs.state] || 'white'}]#{fs.state}[reset]",
              "Public IP"  => fs.public_ip_address,
              "Private IP" => fs.private_ip_address,
              "Created At" => fs.created_at ? fs.created_at.strftime("%Y%m%d-%H%M%S") : nil
            )
          else
            hsh["State"] = "not exist"
          end

          hsh['Volumes'] = []
          svr.composite_volumes.each do |name, vol|
            if    vol.ephemeral_device? then next
            elsif vol.volume_id         then hsh['Volumes'] << vol.volume_id
            elsif vol.create_at_launch? then hsh['Volumes'] << vol.snapshot_id
            end
          end
          hsh['Volumes']    = hsh['Volumes'].join(',')

          hsh['Elastic IP'] = svr.cloud.public_ip if svr.cloud.public_ip
          if block_given?
            extra_info = yield(svr)
            hsh.merge!(extra_info)
            headings += extra_info.keys
          end
          hsh
        end
        if defined_data.empty?
          ui.info "Nothing to report"
        else
          Formatador.display_compact_table(defined_data, headings.to_a)
        end
      end
    end
  end
end
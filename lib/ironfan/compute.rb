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

# include cloud providers
require 'ironfan/ec2/cloud'
require 'ironfan/vsphere/cloud'
require 'ironfan/static/cloud'

module Ironfan
  #
  # Base class allowing us to layer settings for facet over cluster
  #
  class ComputeBuilder < Ironfan::DslObject
    attr_reader :cloud, :volumes, :chef_roles
    has_keys :name, :bogosity, :environment, :chef_attributes
    @@role_implications ||= Mash.new
    @@run_list_rank     ||= 0

    def initialize(builder_name, attrs={})
      super(attrs)
      set :name, builder_name
      set :chef_attributes, Mash.new
      @run_list_info = attrs[:run_list] || Mash.new
      @volumes = Mash.new
    end

    # set the bogosity to a descriptive reason. Anything truthy implies bogusness
    def bogus?
      !! self.bogosity
    end

    # Magic method to produce cloud instance:
    # * returns the cloud instance, creating it if necessary.
    # * executes the block in the cloud's object context
    #
    # @example
    #   cloud do
    #     image_name     'maverick'
    #     security_group :nagios
    #   end
    #
    #   # defines ec2-specific behavior
    #   cloud(:ec2) do
    #     public_ip      '1.2.3.4'
    #     region         'us-east-1d'
    #   end
    #
    def cloud cloud_provider=nil, hsh={}, &block
      return @cloud if @cloud
      case cloud_provider
        when :ec2
          @cloud ||= Ironfan::Ec2::Cloud.new(self)
        when :vsphere
          @cloud ||= Ironfan::Vsphere::Cloud.new(self)
        when :static
          @cloud ||= Ironfan::Static::Cloud.new(self)
        else
          raise "Unknown cloud provider #{cloud_provider.inspect}. Only supports :ec2, :vsphere and :static so far."
      end
      @cloud.configure(hsh, &block) if block
      after_cloud_created(hsh)
      @cloud
    end

    # An abstract method for doing some tasks after the Cloud object is created
    def after_cloud_created(attrs)
    end

    # sugar for cloud(:vsphere)
    def vsphere(attrs={}, &block)
      cloud(:vsphere, attrs, &block)
    end

    # sugar for cloud(:ec2)
    def ec2(attrs={}, &block)
      cloud(:ec2, attrs, &block)
    end

    # Magic method to describe a volume
    # * returns the named volume, creating it if necessary.
    # * executes the block (if any) in the volume's context
    #
    # @example
    #   # a 1 GB volume at '/data' from the given snapshot
    #   volume(:data) do
    #     size        1
    #     mount_point '/data'
    #     snapshot_id 'snap-12345'
    #   end
    #
    # @param volume_name [String] an arbitrary handle -- you can use the device
    #   name, or a descriptive symbol.
    # @param attrs [Hash] a hash of attributes to pass down.
    #
    def volume(volume_name, attrs={}, &block)
      volumes[volume_name] ||= Ironfan::Volume.new(:parent => self, :name => volume_name)
      volumes[volume_name].configure(attrs, &block)
      volumes[volume_name]
    end

    def raid_group(rg_name, attrs={}, &block)
      volumes[rg_name] ||= Ironfan::RaidGroup.new(:parent => self, :name => rg_name)
      volumes[rg_name].configure(attrs, &block)
      volumes[rg_name].sub_volumes.each do |sv_name|
        volume(sv_name){ in_raid(rg_name) ; mountable(false) ; tags({}) }
      end
      volumes[rg_name]
    end

    def root_volume(attrs={}, &block)
      volume(:root, attrs, &block)
    end

    #
    # Adds the given role to the run list, and invokes any role_implications it
    # implies (for instance, defining and applying the 'ssh' security group if
    # the 'ssh' role is applied.)
    #
    # You can specify placement of `:first`, `:normal` (or nil) or `:last`; the
    # final runlist is assembled as
    #
    # * run_list :first  items -- cluster, then facet, then server
    # * run_list :normal items -- cluster, then facet, then server
    # * run_list :last   items -- cluster, then facet, then server
    #
    # (see Ironfan::Server#combined_run_list for full details though)
    #
    def role(role_name, placement=nil)
      add_to_run_list("role[#{role_name}]", placement)
      self.instance_eval(&@@role_implications[role_name]) if @@role_implications[role_name]
    end

    # Add the given recipe to the run list. You can specify placement of
    # `:first`, `:normal` (or nil) or `:last`; the final runlist is assembled as
    #
    # * run_list :first  items -- cluster, then facet, then server
    # * run_list :normal items -- cluster, then facet, then server
    # * run_list :last   items -- cluster, then facet, then server
    #
    # (see Ironfan::Server#combined_run_list for full details though)
    #
    def recipe(name, placement=nil)
      add_to_run_list(name, placement)
    end

    # Roles and recipes for this element only.
    #
    # See Ironfan::Server#combined_run_list for run_list order resolution
    def run_list
      groups = run_list_groups
      [ groups[:first], groups[:normal], groups[:last] ].flatten.compact.uniq
    end

    # run list elements grouped into :first, :normal and :last
    def run_list_groups
      @run_list_info.keys.sort_by{|item| @run_list_info[item][:rank] }.group_by{|item| @run_list_info[item][:placement] }
    end

    #
    # Some roles imply aspects of the machine that have to exist at creation.
    # For instance, on an ec2 machine you may wish the 'ssh' role to imply a
    # security group explicity opening port 22.
    #
    # @param [String] role_name -- the role that triggers the block
    # @yield block will be instance_eval'd in the object that calls 'role'
    #
    def self.role_implication(name, &block)
      @@role_implications[name] = block
    end

  protected

    def add_to_run_list(item, placement)
      raise "run_list placement must be one of :first, :normal, :last or nil (also means :normal)" unless [:first, :last, :own, nil].include?(placement)
      @@run_list_rank += 1
      placement ||= :normal
      @run_list_info[item] ||= { :rank => @@run_list_rank, :placement => placement }
    end

  end
end

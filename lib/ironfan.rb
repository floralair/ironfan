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

require 'chef/mash'
require 'chef/config'
#
require 'gorillib/metaprogramming/class_attribute'
require 'gorillib/hash/reverse_merge'
require 'gorillib/object/blank'
require 'gorillib/hash/compact'
require 'set'
#
require 'ironfan/dsl_object'
require 'ironfan/cloud'
require 'ironfan/security_group'
require 'ironfan/compute'           # base class for machine attributes
require 'ironfan/facet'             # similar machines within a cluster
require 'ironfan/cluster'           # group of machines with a common mission
require 'ironfan/server'            # realization of a specific facet
require 'ironfan/discovery'         # pair servers with Fog and Chef objects
require 'ironfan/server_slice'      # collection of server objects
require 'ironfan/volume'            # configure external and internal volumes
require 'ironfan/private_key'       # coordinate chef keys, cloud keypairs, etc
require 'ironfan/role_implications' # make roles trigger other actions (security groups, etc)
#
require 'ironfan/chef_layer'        # interface to chef for server actions
#
require 'ironfan/deprecated'        # stuff slated to go away
#
# include cloud providers
require 'ironfan/common/cluster'
require 'ironfan/ec2/cluster'

#require 'ironfan/vsphere/cloud_manager'
require 'ironfan/static/cloud_manager'
require 'thread'

module Ironfan

  @mutex = Mutex.new
  
  # path to search for cluster definition files
  def self.cluster_path
    return Chef::Config[:cluster_path] if Chef::Config[:cluster_path]
    raise "Holy smokes, you have no cookbook_path or cluster_path set up. Follow chef's directions for creating a knife.rb." if Chef::Config[:cookbook_path].blank?
    cl_path = Chef::Config[:cookbook_path].map{|dir| File.expand_path('../clusters', dir) }.uniq
    ui.warn "No cluster path set. Taking a wild guess that #{cl_path.inspect} is \nreasonable based on your cookbook_path -- but please set cluster_path in your knife.rb"
    Chef::Config[:cluster_path] = cl_path
  end

  #
  # Delegates
  def self.clusters
    Chef::Config[:clusters] ||= Mash.new
  end

  def self.ui=(ui) @ui = ui ; end
  def self.ui()    @ui      ; end

  def self.chef_config=(cc) @chef_config = cc ; end
  def self.chef_config()    @chef_config      ; end

  #
  # Defines a cluster with the given name.
  #
  # @example
  #   Ironfan.cluster :ec2, 'demosimple' do
  #     cloud :ec2 do
  #       availability_zones  ['us-east-1d']
  #       flavor              "t1.micro"
  #       image_name          "ubuntu-natty"
  #     end
  #     role                  :base_role
  #     role                  :chef_client
  #
  #     facet :sandbox do
  #       instances 2
  #       role                :nfs_client
  #     end
  #   end
  #
  #
  def self.cluster(provider, name, attrs = {}, &block)
    cl = ( self.clusters[name] ||= self.new_cluster(provider, name, attrs) )
    cl.configure(&block)
    cl
  end

  def self.clear_clusters()
    @mutex.synchronize do
      Chef::Config[:clusters] = nil
      @cluster_filenames = nil
    end
  end
  #
  # Return cluster if it's defined. Otherwise, search Ironfan.cluster_path
  # for an eponymous file, load it, and return the cluster it defines.
  #
  # Raises an error if a matching file isn't found, or if loading that file
  # doesn't define the requested cluster.
  #
  # @return [Ironfan::Cluster] the requested cluster
  def self.load_cluster(cluster_name)
    raise ArgumentError, "Please supply a cluster name" if cluster_name.to_s.empty?
    @mutex.synchronize do
      return clusters[cluster_name] if clusters[cluster_name]

      cluster_file = cluster_filenames[cluster_name] or die("Couldn't find a definition for #{cluster_name} in cluster_path: #{cluster_path.inspect}")

      Chef::Log.info("Loading cluster #{cluster_file}")

      #require cluster_file
      cluster_definition = IO.read(cluster_file)
      eval cluster_definition
      unless clusters[cluster_name] then  die("#{cluster_file} was supposed to have the definition for the #{cluster_name} cluster, but didn't") end

      clusters[cluster_name]
    end
  end

  #
  # Map from cluster name to file name
  #
  # @return [Hash] map from cluster name to file name
  def self.cluster_filenames
    return @cluster_filenames if @cluster_filenames
    @cluster_filenames = {}
    cluster_path.each do |cp_dir|
      Dir[ File.join(cp_dir, '*.rb') ].each do |filename|
        cluster_name = File.basename(filename).gsub(/\.rb$/, '')
        @cluster_filenames[cluster_name] ||= filename
      end
    end
    @cluster_filenames
  end

  #
  # Create a cluster under Ironfan.cluster_path and return the cluster it defines.
  #
  # @param [String] cluster_def_file -- full path of the file containing the cluster definition in json format.
  # @param overwrite -- whether overwrite existing cluster file.
  #
  # @return [Ironfan::Cluster] the created cluster.
  #
  def self.create_cluster(cluster_def_file, overwrite = false)
    raise ArgumentError, "Please supply a cluster definition file" if cluster_def_file.to_s.empty?

    # get cluster definition from json file
    cluster_def = JSON.parse(File.read(cluster_def_file))['cluster_definition']
    cluster_name = cluster_def['name']
    die("'name' of cluster is not specified in #{cluster_def_file}") if !cluster_name

    # check whether target cluster file exists
    Chef::Log.debug("cluster definition files: #{cluster_filenames.inspect}")
    cluster_filename = cluster_filenames[cluster_name]
    if cluster_filename and !overwrite
      die("Cluster #{cluster_name} already exists in #{cluster_filename}. Aborted.")
    end

    # create new Cluster object
    cloud_provider_def = JSON.parse(File.read(cluster_def_file))['cloud_provider']
    cloud_provider_name = cloud_provider_def['name'].to_sym
    cluster = Ironfan.cluster(cloud_provider_name, cluster_name)
    cluster.cloud cloud_provider_name
    cluster.cloud.flavor 'default' # FIXME: should not be hard coded in future

    cluster_def.each do |key, value|
      case key
      when 'distro'
        cluster.hadoop_distro cluster_def[key]
        cluster.cluster_role do
          override_attributes({ :hadoop => { :distro_name => cluster.hadoop_distro,  :distro_vendor => cluster_def['distro_vendor'], :distro_version => cluster_def['distro_version'] } })
        end
      when 'template_id'
        # cluster.cloud.image_name value
        cluster.cloud.image_name 'centos5' # FIXME: should not be hard coded in future
      when 'flavor'
        cluster.cloud.flavor value
      when 'roles'
        value.each do |role|
          cluster.role role
        end
      when 'groups'
        facets = cluster_def[key]
        facets.each do |facet_def|
          facet = cluster.facet(facet_def['name'])
          facet_def.each do |key, value|
            case key
            when 'template_id'
              facet.cloud(cloud_provider_name).image_name value
            when 'instance_num'
              facet.instances value
            when 'ha'
              facet.facet_role do
                override_attributes({ :hadoop => { :ha_enabled => ['on','ft'].include?(value) } })
              end
            when 'roles'
              value.each do |role|
                facet.role role
              end
            end
          end
        end
      end
    end

    # save Cluster object
    cluster.save

    load_cluster(cluster_name)
  end

  #
  # Utility to die with an error message.
  # If the last arg is an integer, use it as the exit code.
  #
  def self.die *strings
    exit_code = strings.last.is_a?(Integer) ? strings.pop : -1
    strings.each{|str| ui.error str }
    exit exit_code
  end

  #
  # Utility to turn an error into a warning
  #
  # @example
  #   Ironfan.safely do
  #     cloud.fog_connection.associate_address(self.fog_server.id, address)
  #   end
  #
  def self.safely
    begin
      yield
    rescue StandardError => boom
      ui.info( boom )
      Chef::Log.error( boom )
      Chef::Log.error( boom.backtrace.join("\n") )
    end
  end

  protected

  # Create a new Cluster instance with the specified provider type and name
  def self.new_cluster(provider, name, attrs)
    provider = provider.to_sym
    name = name.to_sym

    cluster =
      case provider
      when :ec2
        Ironfan::Ec2::Cluster.new(name, attrs)
      when :vsphere
        Ironfan::Common::Cluster.new(:vsphere, name, attrs)
      when :static
        Ironfan::Common::Cluster.new(:static, name, attrs)
      else
        raise "Unknown cloud provider #{provider.inspect}. Only supports :ec2 and :vsphere so far."
      end

    cluster
  end
  def self.new_cloud_manager(provider)
    provider = provider.to_sym

    cloud_manager =
      case provider
      when :ec2
        nil # TODO
      when :vsphere
        Ironfan::Vsphere::CloudManager.new
      when :static
        Ironfan::Static::CloudManager.new
      else
        raise "Unknown cloud provider #{provider.inspect}. Only supports :ec2 and :vsphere so far."
      end
    cloud_manager
  end
end

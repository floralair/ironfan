#
# Author:: Philip (flip) Kromer (<flip@infochimps.com>)
# Copyright:: Copyright (c) 2011 Infochimps, Inc
# Portions Copyright (c) 2012-2014 VMware, Inc. All Rights Reserved.
# License:: Apache License, Version 2.0
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

require File.expand_path('ironfan_knife_common', File.dirname(__FILE__))

module Ironfan
  class Script < Chef::Knife
    include Ironfan::KnifeCommon

    deps do
      Ironfan::KnifeCommon.load_deps
    end

    option :dry_run,
      :long        => "--dry-run",
      :description => "Don't really run, just use mock calls",
      :boolean     => true,
      :default     => false
    option :yes,
      :long        => "--yes",
      :description => "Skip confirmation prompts on risky actions.",
      :boolean     => true

    option :from_file,
      :long        => "--fromfile FILENAME",
      :short       => "-f FILENAME",
      :description => "Specify the file containing the cluster definition in json format. And specify --yes to overwrite existing cluster file.",
      :required    => false

    def run
      load_ironfan
      die(banner) if @name_args.empty?
      configure_dry_run

      target = get_relevant_slice(* @name_args)
      if target.empty?
        ui.info("No nodes need to #{sub_command}, exiting")
        exit 0
      end

      # Pre-populate information in cloud and chef
      target.cluster.action = sub_command
      target.sync_to_cloud
      target.sync_to_chef

      ui.info(["\n", ui.color("Running #{sub_command}", :cyan), " on #{target.joined_names} ..."].join())
      display(target)

      unless config[:yes]
        ui.info("")
        confirm_execution(target)
      end

      exit_value = perform_execution(target)
      exit_value = 0 if exit_value == true
      exit_value = 1 if exit_value == false
      exit_value = exit_value.select{ |i| i != SUCCESS and i != true }.empty? ? SUCCESS : FAILURE if exit_value.is_a?(Array)

      # Sync information to cloud
      target.sync_to_cloud

      ui.info("")
      ui.info "Finished! Current state:"
      display(target)

      Chef::Log.debug("Exit value of Knife command is: #{exit_value.inspect}")
      exit exit_value
    end

    def perform_execution(target)
      target.send(sub_command)
    end
  end
end

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

require File.expand_path('ironfan_script', File.dirname(__FILE__))

class Chef
  class Knife
    class ClusterConfig < Ironfan::Script
      import_banner_and_options(Ironfan::Script)

      option :cloud,
        :long        => '--[no-]cloud',
        :description => 'Refresh cloud machine info; use --no-cloud to skip',
        :boolean     => true,
        :default     => true
      option :set_chef_client_flag,
        :long        => "--set-chef-client-flag [true|false]",
        :description => "set chef client flag and return"

      def relevant?(server)
        true
      end

      def perform_execution(target)
        if config[:set_chef_client_flag] == 'true'
          target.set_chef_client_flag(true, true) if !target.empty?
          return SUCCESS
        end
        if config[:set_chef_client_flag] == 'false'
          target.set_chef_client_flag(true, false) if !target.empty?
          return SUCCESS
        end
      end
    end
  end
end

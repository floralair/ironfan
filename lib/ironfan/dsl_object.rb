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

Mash.class_eval do
  def reverse_merge!(other_hash)
    # stupid mash doesn't take a block arg, which breaks the implementation of
    # reverse_merge!
    other_hash.each_pair do |key, value|
      key = convert_key(key)
      regular_writer(key, convert_value(value)) unless has_key?(key)
    end
    self
  end
  def to_mash
    self.dup
  end unless method_defined?(:to_mash)
end

Hash.class_eval do
  def to_mash
    Mash.new(self)
  end unless method_defined?(:to_mash)
end

module Ironfan
  #
  # Provides magic methods, defined with has_keys
  #
  # @example
  #   class Mom < Ironfan::DslObject
  #     has_keys(:college, :combat_boots, :fat, :so_fat)
  #   end
  #
  #   class Person
  #     def momma &block
  #       @momma ||= Mom.new
  #       @momma.configure(&block) if block
  #     end
  #   end
  #
  #   yo = Person.new
  #   yo.mamma.combat_boots :wears
  #   yo.momma do
  #     fat    true
  #     so_fat 'When she sits around the house, she sits *AROUND* the house'
  #   end
  #
  class DslObject
    class_attribute :keys
    self.keys = []

    def initialize(attrs={}, &block)
      @settings = Mash.new
      configure(attrs, &block)
    end

    #
    # Defines DSL attributes
    #
    # @param [Array(String)] key_names DSL attribute names
    #
    # @example
    #   class Mom < Ironfan::DslObject
    #     has_keys(:fat, :so_fat)
    #   end
    #   yer_mom = Mom.new
    #   yer_mom.fat :quite
    #
    def self.has_keys(*key_names)
      key_names.map!(&:to_sym)
      self.keys += key_names
      self.keys.uniq!
      key_names.each do |key|
        next if method_defined?(key)
        define_method(key){|*args| set(key, *args) }
      end
    end

    #
    # Sets the DSL attribute, unless the given value is nil.
    #
    def set(key, val=nil)
      @settings[key.to_s] = val unless val.nil?
      @settings[key.to_s]
    end

    def to_hash
      @settings.to_hash
    end

    def to_mash
      @settings.dup
    end

    def to_s
      "<#{self.class} #{to_hash.inspect}>"
    end

    def reverse_merge!(hsh)
      @settings.reverse_merge!(hsh.to_hash)
    end

    def configure(hsh={}, &block)
      @settings.merge!(hsh.to_hash)
      instance_eval(&block) if block
      self
    end

    # delegate to the knife ui presenter
    def ui()      Ironfan.ui ; end
    # delegate to the knife ui presenter
    def self.ui() Ironfan.ui ; end

    def step(desc, *style)
      ui.info("  #{"%-15s" % (name.to_s+":")}\t#{ui.color(desc.to_s, *style)}")
    end

    # helper method for bombing out of a script
    def die(*args) Ironfan.die(*args) ; end

    # helper method for turning exceptions into warnings
    def safely(*args, &block) Ironfan.safely(*args, &block) ; end

    # helper method for debugging only
    def dump(*args) args.each{|arg| Chef::Log.debug( arg.inspect ) } end

    protected

    # Utility method for defining abstract methods
    def raise_not_implemented
      caller[0] =~ /`(.*?)'/
      caller_method = $1
      raise NotImplementedError.new("Must implement method '#{caller_method}' in subclass")
    end

  end
end

require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

require IRONFAN_DIR("lib/ironfan")

describe Ironfan do
  describe 'create_cluster' do

    before :all do
      @cluster_name = "hadoop_cluster_test"
      @cluster_filename = File.join(Ironfan.cluster_path.first, "#{@cluster_name}.rb")
      File.delete(@cluster_filename) if File.exists?(@cluster_filename)
      @cluster = Ironfan::create_cluster(IRONFAN_DIR('spec/data/cluster_definition.json'), true)
    end

    it 'creates a new cluster file' do
      File.exists?(@cluster_filename).should == true
      @cluster.name.should == :hadoop_cluster_test
    end

    it 'cluster distro is correct' do
      @cluster.hadoop_distro.should == "apache"
    end

    it 'cluster cloud is correct' do
      cloud = @cluster.cloud
      cloud.image_name.should == "centos"
      cloud.flavor.should == "default"
    end

    it 'facets are in correct order' do
      @cluster.facets.keys.should == ["master", "worker", "client"]
    end

    it 'facet master is correct' do
      facet = @cluster.facet(:master)
      facet.name.should == :master
      facet.run_list.should == ["role[hadoop_namenode]", "role[hadoop_jobtracker]"]
      facet.instances.should == 1
    end

    it 'facet worker is correct' do
      facet = @cluster.facet(:worker)
      facet.name.should == :worker
      facet.run_list.should == ["role[hadoop_datanode]", "role[hadoop_tasktracker]"]
      facet.instances.should == 3
    end

    it 'facet client is correct' do
      facet = @cluster.facet(:client)
      facet.name.should == :client
      facet.run_list.should == ["role[hadoop_client]", "role[pig]", "role[hive]", "role[hive_server]"]
      facet.instances.should == 1
    end
  end
end


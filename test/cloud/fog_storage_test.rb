require File.expand_path(File.join(__FILE__, '../..', 'test_helper'))
require 'rubber/cloud/fog_storage'
require 'ostruct'

class FogStorageTest < Test::Unit::TestCase

  context "fog storage" do

    setup do
      @provider = Fog::Storage.new(:provider => 'AWS',
                                   :aws_access_key_id => 'XXX',
                                   :aws_secret_access_key => 'YYY')
      @bucket = 'mybucket'
      @provider.put_bucket(@bucket)
      @storage = Rubber::Cloud::FogStorage.new(@provider, @bucket)
    end

    should "require a bucket" do
      
      assert_raise do
        Rubber::Cloud::FogStorage.new(@provider, nil)
      end

      assert_raise do
        Rubber::Cloud::FogStorage.new(@provider, "")
      end
      
    end
    
    context "ensure_bucket" do
      
      should "created bucket if not there" do
        assert @provider.directories.get('somebucket').nil?
        @storage = Rubber::Cloud::FogStorage.new(@provider, 'somebucket')
        @storage.ensure_bucket
        assert @provider.directories.get('somebucket')
      end
      
      should "still work if bucket already exists" do
        assert @provider.directories.create(:key => 'somebucket')
        assert @provider.directories.get('somebucket')
        @storage = Rubber::Cloud::FogStorage.new(@provider, 'somebucket')
        @storage.ensure_bucket
        assert @provider.directories.get('somebucket')
      end
      
    end
    
    context 'storing a file' do
      
      should 'require a key' do
        assert_raise do
          @storage.store(nil, "data")
        end
      end
    
      should "store a file path" do
        @storage.store("filename", "data")
    
        assert_equal("data", @provider.get_object(@bucket, 'filename').body)
      end
    
      should "singlepart files under 5 mb" do
        @provider.expects(:initiate_multipart_upload).never
        data = 'a' * (5 * 10**6 - 1)
    
        @storage.store('filename', data)
    
        assert_equal data, @provider.get_object(@bucket, 'filename').body
      end
    
      should "multipart files over 5 mb" do
        @storage.expects(:singlepart_store).never
        data = 'a' * (5 * 2**20 + 1)
    
        #FIXME: Fog mock for initiate_multipart_upload isn't implemented. Remove mocks when it is
        @provider.expects(:initiate_multipart_upload).returns(OpenStruct.new(:body => {'UploadId' => 'fake-upload-id'}))
        @provider.expects(:upload_part).returns(OpenStruct.new(:headers => {'ETag' => 'fake-etag'}))
        @provider.expects(:complete_multipart_upload)
    
        io = Tempfile.new('s3-helper-test')
        io.unlink
        io.write(data)
        io.rewind
    
        @storage.store('filename', io)
    
        #FIXME: proper assertion when Fog mock supports multipart upload
        #assert_equal data, @provider.get_object(@bucket, 'filename').body
    
      end
      
    end
    
    
    context 'fetching a file' do
      
      should 'require a filename' do
        assert_raise do
          @storage.fetch(nil)
        end
      end
        
      should "fetch a file with a path" do
        @provider.put_object(@bucket, 'path/filename', 'some data')
    
        assert_equal('some data', @storage.fetch("path/filename"))
      end

      should "return nil for non-existent file" do
        assert_nil @storage.fetch("path/filename")
      end

    end

    
    context 'fetching many files' do
      should "fetch files without a prefix" do
        @provider.put_object(@bucket, 'path1/file1', 'some data1')
        @provider.put_object(@bucket, 'path2/file2', 'some data2')
    
        files = []
        @storage.walk_tree do |s3_file|
          files << s3_file
        end
        assert_equal 2, files.size
        assert_equal('path1/file1', files[0].key)
        assert_equal('some data1', files[0].body)
        assert_equal('path2/file2', files[1].key)
        assert_equal('some data2', files[1].body)
      end
    
      should "restrict fetched files to a prefix" do
        @provider.put_object(@bucket, 'path1/file1', 'some data1')
        @provider.put_object(@bucket, 'path2/file2', 'some data2')
    
        files = []
        @storage.walk_tree('path1') do |s3_file|
          files << s3_file
        end
        assert_equal 1, files.size
        assert_equal('path1/file1', files[0].key)
        assert_equal('some data1', files[0].body)
      end
    
    end
    
    should "stream a file" do
      yielded_value = nil
      @provider.put_object(@bucket, 'path/filename', 'my chunk')
      
      @storage.fetch("path/filename", {}) { |chunk| yielded_value = chunk }
    
      assert_equal yielded_value, 'my chunk'
    end
    
    should "stream a file for non-existent key" do
      yielded_value = 'x'
      
      @storage.fetch("path/filename", {}) { |chunk| yielded_value = chunk }
    
      assert_equal 'x', yielded_value
    end
    
    context 'deleting a file' do
      should 'require a filename' do
        assert_raise do
          @storage.delete(nil)
        end
      end
    
      should 'delete a file' do
        @provider.put_object(@bucket, 'path/filename', 'some data')
        assert_equal 1, @provider.get_bucket(@bucket).body['Contents'].size
        assert_equal 'path/filename', @provider.get_bucket(@bucket).body['Contents'].first['Key']
    
        @storage.delete('path/filename')
        assert_equal 0, @provider.get_bucket(@bucket).body['Contents'].size
      end
    end
  
  end
end

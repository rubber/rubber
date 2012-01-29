require File.expand_path(File.join(__FILE__, '../..', 'test_helper'))
require 'rubber/cloud/aws_table_store'

class AwsTableStoreTest < Test::Unit::TestCase

  context "aws table store" do

    setup do
      @provider = ::Fog::AWS::SimpleDB.new(:aws_access_key_id => 'XXX',
                                           :aws_secret_access_key => 'YYY')
      @table = 'mytable'
      @provider.create_domain(@table)
      @table_store = Rubber::Cloud::AwsTableStore.new(@provider, @table)
    end

    should "require a table" do
      
      assert_raise do
        Rubber::Cloud::AwsTableStore.new(@provider, nil)
      end

      assert_raise do
        Rubber::Cloud::AwsTableStore.new(@provider, "")
      end
      
      assert Rubber::Cloud::AwsTableStore.new(@provider, @table)
    end
    
    context "ensure_table" do
      
      should "created table if not there" do
        assert_raises { @provider.domain_metadata('sometable') }
        @table_store = Rubber::Cloud::AwsTableStore.new(@provider, 'sometable')
        assert @provider.domain_metadata('sometable')
      end
      
      should "still work if table already exists" do
        @provider.create_domain('sometable')
        assert @provider.domain_metadata('sometable')
        @table_store = Rubber::Cloud::AwsTableStore.new(@provider, 'sometable')
        assert @provider.domain_metadata('sometable')
      end
      
    end
    
    context 'encode and decode' do
      
      setup do
        @data = [123, "foo", {'foo' => 'bar'}, ["foo", "bar"]]
      end
      
      should 'roundtrip' do
        @data.each do |d|
          assert_equal d, @table_store.decode(@table_store.encode(d))
        end
      end

      should 'decode_attributes' do
        d = {'"foo"' => ['["bar"]']}  
        assert_equal({'"foo"' => "bar"}, @table_store.decode_attributes(d))
      end
      
    end
    
    context 'put' do
      
      should 'put data' do
        @table_store.put('mykey', {'foo' => 'bar'})
        assert_equal({'foo' => ['["bar"]']},
                     @provider.get_attributes(@table, 'mykey',
                                              'AttributeName' => ['foo']).body['Attributes'])
      end
      
      should 'overwrite data' do
        @table_store.put('mykey', {'foo' => 'bar'})
        @table_store.put('mykey', {'foo' => 'baz'})
        assert_equal({'foo' => ['["baz"]']},
                     @provider.get_attributes(@table, 'mykey',
                                              'AttributeName' => ['foo']).body['Attributes'])
      end
      
    end
    
    context 'get' do
      
      should 'get data' do
        @table_store.put('mykey', {'foo' => 'bar', 'baz' => 2})
        assert_equal({'foo' => 'bar', 'baz' => 2}, @table_store.get('mykey'))
        assert_equal({'foo' => 'bar', 'baz' => 2}, @table_store.get('mykey', ['foo', 'baz']))
        assert_equal({'baz' => 2}, @table_store.get('mykey', ['baz']))
      end
      
    end
    
    context 'delete' do
      
      should 'delete data' do
        @table_store.put('mykey', {'foo' => 'bar', 'baz' => 2})
        @table_store.delete('mykey')
        assert_equal({}, @table_store.get('mykey'))
      end
      
      should 'delete partial data' do
        @table_store.put('mykey', {'foo' => 'bar', 'baz' => 2})
        @table_store.delete('mykey', ['foo'])
        assert_equal({'baz' => 2}, @table_store.get('mykey'))
      end
      
    end
    
    # no fog mocks for select, so use mocha
    context 'find' do
      
      should 'find all with no params' do
        response = mock('fog response') do
          expects(:body).twice().returns({'Items' => {}})
        end
        
        @provider.expects(:select).with("select * from `#{@table}` limit 200", {}).returns(response)
        assert_equal({}, @table_store.find())
      end
      
      should 'find with key' do
        response = mock('fog response') do
          expects(:body).twice().returns({'Items' => {}})
        end
        
        @provider.expects(:select).with("select * from `#{@table}` where ItemName = 'foo' limit 200", {}).returns(response)
        assert_equal({}, @table_store.find('foo'))
      end
      
      should 'find with attributes' do
        response = mock('fog response') do
          expects(:body).twice().returns({'Items' => {}})
        end
        
        @provider.expects(:select).with("select foo, bar from `#{@table}` limit 200", {}).returns(response)
        assert_equal({}, @table_store.find(nil, ['foo', 'bar']))
      end
      
      should 'find with limit' do
        response = mock('fog response') do
          expects(:body).twice().returns({'Items' => {}})
        end
        
        @provider.expects(:select).with("select * from `#{@table}` limit 5", {}).returns(response)
        assert_equal({}, @table_store.find(nil, nil, :limit => 5))
      end
      
      should 'find with offset' do
        response = mock('fog response') do
          expects(:body).twice().returns({'Items' => {}})
        end
        
        @provider.expects(:select).with("select * from `#{@table}` limit 200", {'NextToken' => 'blah'}).returns(response)
        assert_equal({}, @table_store.find(nil, nil, :offset => 'blah'))
      end
      
      should 'add next_offset' do
        response = mock('fog response') do
          expects(:body).twice().returns({'Items' => {}, 'NextToken' => 'blah'})
        end
        
        @provider.stubs(:select).returns(response)
        resp = @table_store.find()
        assert_equal 'blah', resp.next_offset
      end
      
    end
    
  end
end

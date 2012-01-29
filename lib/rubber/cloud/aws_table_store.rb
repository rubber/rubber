require 'json'

module Rubber
  module Cloud
    
    class AwsTableStore

      RETRYABLE_EXCEPTIONS = [Excon::Errors::Error]

      attr_reader :metadata

      def logger
        Rubber.logger
      end
      
      def initialize(provider, table_key)
        raise "table_key required" unless table_key && table_key.size > 0
        
        @table_provider = provider
        @table_key = table_key
        
        ensure_table_key
      end
  
      # create the table if needed
      def ensure_table_key()
        Rubber::Util.retry_on_failure(*RETRYABLE_EXCEPTIONS) do
          begin
            @metadata = @table_provider.domain_metadata(@table_key)
          rescue Excon::Errors::BadRequest
            @table_provider.create_domain(@table_key)
            @metadata = @table_provider.domain_metadata(@table_key)
          end
        end
      end
      
      def encode(v)
        [v].to_json
      end
      
      def decode(v)
        JSON.parse(v).first
      end
      
      def decode_attributes(data)
        Hash[data.collect {|k, v| [k, decode(v.first)] }]
      end
      
      def put(key, attributes)
        data = Hash[attributes.collect {|k, v| [k, encode(v)] }]
        @table_provider.put_attributes(@table_key, key, data, :replace => attributes.keys)
        return true
      end
      
      def get(key, attributes=[])
        response = @table_provider.get_attributes(@table_key, key, 'AttributeName' => attributes)
        data = response.body['Attributes']
        return decode_attributes(data)
      end
  
      def delete(key, attributes=nil)
        @table_provider.delete_attributes(@table_key, key, attributes)
        return true
      end
      
      def find(key=nil, attributes=nil, opts={})
        query = "select"
        query << " " + (attributes ? attributes.join(", ") : '*')
        query << " from `#{@table_key}`"
        query << " where ItemName = '#{key}'" if key
        query << " limit " + (opts[:limit] ? opts[:limit].to_s : "200")
        
        query_opts = {}
        query_opts["NextToken"] = opts[:offset].to_s if opts[:offset]
        
        response = @table_provider.select(query, query_opts)

        data = response.body['Items']
        result = TableResponse.new
        data.each do |name, attribs|
          result[name] = decode_attributes(attribs)
        end 
            
        result.next_offset = response.body['NextToken']
        
        return result
      end
      
      class TableResponse < Hash
        attr_accessor :next_offset
        
        def initialize(*args)
          super
        end
      end
      
    end

  end
end

=begin
  simpledb limits:

  Domain size	 10 GB per domain
  Domain size	 1 billion attributes per domain
  Domain name	 3-255 characters (a-z, A-Z, 0-9, '_', '-', and '.')
  Domains per account	 250
  Attribute name-value pairs per item	 256
  Attribute name length	 1024 bytes
  Attribute value length	 1024 bytes
  Item name length	 1024 bytes
  Attribute name, attribute value, and item name allowed characters	
  All UTF-8 characters that are valid in XML documents.
  
  Control characters and any sequences that are not valid in XML are returned Base64-encoded. For more information, see Working with XML-Restricted Characters.
  Attributes per PutAttributes operation	256
  Attributes requested per Select operation	 256
  Items per BatchPutAttributes operation	25
  Maximum items in Select response	2500
  Maximum query execution time	5 seconds
  Maximum number of unique attributes per Select expression	
  20
  Maximum number of comparisons per Select expression	
  20
  Maximum response size for Select	1MB
=end

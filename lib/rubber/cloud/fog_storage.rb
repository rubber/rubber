module Rubber
  module Cloud
    
    class FogStorage

      RETRYABLE_EXCEPTIONS = [Excon::Errors::Error]

      def logger
        Rubber.logger
      end
      
      def initialize(storage_provider, bucket)
        raise "bucket required" unless bucket && bucket.size > 0
        
        @storage_provider = storage_provider
        @bucket = bucket
        @directory = @storage_provider.directories.get(@bucket)
      end
  
      # create the bucket if needed
      def ensure_bucket()
        Rubber::Util.retry_on_failure(*RETRYABLE_EXCEPTIONS) do
          @directory = @storage_provider.directories.create(:key => @bucket) unless @directory
        end
        return self
      end
    
      # data can be a string or io handle
      def store(key, data, opts={})
        if data.respond_to?(:read)
          multipart_store(key, data, opts)
        else
          singlepart_store(key, data, opts)
        end
      end
  
      def singlepart_store(key, data, opts={})
        raise "a key is required" unless key && key.size > 0
        
        file = nil
  
        # store the object
        logger.debug "Storing object: #{key}"
  
        ensure_bucket()
        
        Rubber::Util.retry_on_failure(*RETRYABLE_EXCEPTIONS) do
          file = @directory.files.new(opts.merge(:key => key))
          file.body = data
          file.save
        end
  
        file
      end
  
      def multipart_store(key, data, opts={})
        raise "a key is required" unless key && key.size > 0
        
        opts = {:chunk_size => (5 * 2**20)}.merge(opts)
  
        chunk = data.read(opts[:chunk_size])
  
        if chunk.size < opts[:chunk_size]
          singlepart_store(key, chunk, opts)
        else
          logger.info "Multipart uploading #{key}"
  
          part_ids = []
  
          ensure_bucket()
          
          response = @storage_provider.initiate_multipart_upload(@bucket, key)
          begin
            upload_id = response.body['UploadId']
  
            while chunk
              next_chunk = data.read(opts[:chunk_size])
              if data.eof?
                chunk << next_chunk
                next_chunk = nil
              end
              part_number = part_ids.size + 1
              logger.info("Uploading part #{part_number}")
              Rubber::Util.retry_on_failure(*RETRYABLE_EXCEPTIONS) do
                response = @storage_provider.upload_part(@bucket, key, upload_id, part_number, chunk)
                part_ids << response.headers['ETag']
              end
              chunk = next_chunk
            end
  
            @storage_provider.complete_multipart_upload(@bucket, key, upload_id, part_ids)
            logger.info("Completed multipart upload: #{upload_id}")
  
          rescue Exception => e
            logger.error("Aborting multipart upload: #{upload_id}")
            @storage_provider.abort_multipart_upload(@bucket, key, upload_id)
            raise
          end
        end
      end
  
      def fetch(key, opts={}, &block)
        raise "a key is required" unless key && key.size > 0
        
        if block_given?
          # TODO (nirvdrum 05/24/13) Remove when https://github.com/fog/fog/issues/1832 is fixed.
          begin
            @directory.files.get(key, opts, &block)
          rescue Excon::Errors::NotFound
            nil
          end
        else
          Rubber::Util.retry_on_failure(*RETRYABLE_EXCEPTIONS) do
            begin
              file = @directory.files.get(key, opts)
              file.body if file
            rescue Excon::Errors::NotFound
              nil
            end
          end
        end
      end
      
      def delete(key, opts={})
        raise "a key is required" unless key && key.size > 0
        
        # store the object
        logger.debug "Deleting object: #{key}"
        Rubber::Util.retry_on_failure(*RETRYABLE_EXCEPTIONS) do
          file = @directory.files.get(key, opts);
          file.destroy if file
        end
      end
  
      def walk_tree(prefix=nil)
        # Grab a new bucket connection since this method destroys
        # the cached copy of files once the prefix is applied.
        Rubber::Util.retry_on_failure(*RETRYABLE_EXCEPTIONS) do
          @storage_provider.directories.get(@bucket, :prefix => prefix).files.each do |f|
            yield f
          end
        end
      end
  
    end

  end
end

#encoding: UTF-8
require "google/cloud/video_intelligence/v1"
require 'data_collector'
require_relative './helper'
require_relative './storage'

module GCloud
  module VideoIntelligence
   class ToLargeFileError < StandardError; end

   class Client
      include DataCollector::Core
      include GCloud

      attr_accessor :client, :logger, :gconfig, :client_config

      GCLOUD_SERIVCE_CONFIG_FILE="video_intelligence.json"

      def initialize
        @logger = Logger.new(STDOUT)
        @logger.level = Logger::DEBUG

        # Set up the DataCollector configuration
        @client_config = DataCollector::Core.config
        
        @client_config.path  = '/app/config/'
        @client_config.name  = 'config.yml'

        if @client_config[:gconfig_application_credentials_file].nil?
          raise "Please set the path of your Google Cloud service account credentials JSON file. example: /app/config/application_default_credentials.json"
        end

        @client_config[:max_video_duration] = @client_config[:max_video_duration] || 60 * 10 # 10 min.
        ENV['GOOGLE_APPLICATION_CREDENTIALS'] = @client_config[:gconfig_application_credentials_file]

        @client_config[:gconfig_file] = File.join( @client_config[:gconfig_path], GCLOUD_SERIVCE_CONFIG_FILE )
        if @client_config[:gconfig_file].nil?
           @logger.error ("Unable to find #{ @client_config[:gconfig_file]}")
          raise "Please set the gconfig_path of the service config. example: /app/config/"
        end

        @client = Google::Cloud::VideoIntelligence::V1::VideoIntelligenceService::Client.new
        @gconfig = JSON.parse(  File.read(@client_config[:gconfig_file]) , symbolize_names: true)


        if @client_config[:use_google_storage]
          @gStorageClient = GCloud::Storage::Client.new
          @gStorageClient.logger = Logger.new(STDOUT)

          @gStorageClient.logger.info "Starting Google Storage Client"
          @gStorageClient.client_config.keys
        end

      end

      def response
        @logger.debug "Starting video annotation process with Google Video Intelligence API"
        @logger.debug "Client configuration: features #{@gconfig[:features]}"
        @logger.debug "Client configuration: video_context #{@gconfig[:video_context]}"

        unless @client_config[:input_file].nil?
          video = FFMPEG::Movie.new(@client_config[:input_file] )

          if video.duration > @client_config[:max_video_duration] 
            raise ToLargeFileError, "#{@client_config[:input_file]} sikpped! It #{@client_config[:input_file]} exceeds the maximum allowed duration of #{@client_config[:max_video_duration] } seconds."
          end

          if  @client_config[:use_google_storage] && video.duration > 30 # don't use Storage if duration is less than 30 sec

            @gconfig[:output_uri] = "gs://#{ @client_config[:gconfig_storage_bucket] }/#{google_cloud_output_file}"
            @gconfig[:input_uri] = "gs://#{ @client_config[:gconfig_storage_bucket] }/#{google_cloud_input_file}" 

            google_cloud_output_file =  File.join( "transcripts/video/", File.basename(@client_config[:output_file])  )
            output_file = File.join( @client_config[:output_dir], @client_config[:output_file]) 


            if @gStorageClient.file_exists?(file: google_cloud_output_file)
              @logger.info "Output file with annotations already exists in Google Storage: #{@gconfig[:output_uri]}"
              @gStorageClient.download_from_google_storage(  source: google_cloud_output_file,  target: output_file)
            
              @gStorageClient.remove_from_google_storage(file: google_cloud_output_file) 
              @gStorageClient.remove_from_google_storage(file: google_cloud_input_file)
              
              return JSON.parse( File.read(output_file) , symbolize_names: true)
            end

            
            google_cloud_input_file =  File.join( "video-files", File.basename(@client_config[:input_file])  )
            @logger.info "Upload to Google cloud Storage #{google_cloud_input_file}"
            @gStorageClient.upload_to_google_storage( source: @client_config[:input_file], target: google_cloud_input_file)

            @gconfig.delete(:input_content)
            
            begin 
              operation = @client.annotate_video(::Google::Cloud::VideoIntelligence::V1::AnnotateVideoRequest.new ( @gconfig ) )
              puts "Operation started"

              # ?????? https://cloud.google.com/video-intelligence/docs/long-running-operations
              operation.wait_until_done!
              raise operation if operation.error?
              pp "Operation finished! Output available in #{@gconfig[:output_uri]}"

            rescue Google::Cloud::ResourceExhaustedError => e  
              @logger.error "Resource Exhausted: #{e.message}"
            rescue StandardError => e
              @gStorageClient.download_from_google_storage(  source: google_cloud_output_file,  target: output_file)
              raise e
            end

            @logger.info "Download annotations to #{google_cloud_output_file}"
            @gStorageClient.download_from_google_storage(  source: google_cloud_output_file,  target: output_file)
            
            @gStorageClient.remove_from_google_storage(file: google_cloud_output_file) 

            @gStorageClient.remove_from_google_storage(file: google_cloud_input_file)

            return JSON.parse( File.read(output_file) , symbolize_names: true)
          else
            
            if @gconfig[:input_content].nil?
              @gconfig.delete(:input_uri)
              @gconfig[:input_content] = File.open( @client_config[:input_file], 'rb') { |io| io.read }
            end

            operation = @client.annotate_video(::Google::Cloud::VideoIntelligence::V1::AnnotateVideoRequest.new ( @gconfig ) )
            operation.wait_until_done!
            operation.results
            raise operation.results.message if operation.error?
            return JSON.parse( operation.response.to_json , symbolize_names: true)

          end  

        end
      rescue ToLargeFileError => e
        @logger.warn "Skipping automatic processing: #{@client_config[:input_file]} exceeds the maximum allowed duration of #{@client_config[:max_video_duration] } seconds."

        big_file = File.join(  File.dirname(@client_config[:input_file]), "tobig/#{ File.basename(@client_config[:input_file] , File.extname(@client_config[:input_file]) ) }#{File.extname(@client_config[:input_file])}") 
        big_file_dirname = File.dirname( big_file ) 

        FileUtils.mkdir_p(big_file_dirname) unless File.directory?( big_file_dirname )

        @logger.warn "#{@client_config[:input_file]} moved to #{ big_file } "

        FileUtils.move(@client_config[:input_file], big_file)
        puts "Client Error: #{e.message}"
        raise e
      rescue StandardError => e
        puts "Error in VideoIntelligence::Client: #{e.message}"
        raise e
      end

      def select_files
        # Select files from the records directory
        @logger.debug "Selecting files from input directories: #{@client_config[:input_dirs]}"
        raise "Input directories are not set in the client configuration." if @client_config[:input_dirs].nil? || @client_config[:input_dirs].empty?
        input_files = []
        @client_config[:input_dirs] = [@client_config[:input_dirs]] unless @client_config[:input_dirs].is_a?(Array)
        @client_config[:input_dirs].each do |input_dir|
          @logger.debug "Input directory: #{input_dir}"
          input_files << select_files_from_dir(input_dir) 
        end
        input_files.flatten!
      end

    end
  end
end
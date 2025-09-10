#encoding: UTF-8
require "google/cloud/storage" # https://cloud.google.com/ruby/docs/reference/google-cloud-storage/latest
require 'data_collector'
require_relative './helper'

module GCloud
  module Storage
   class Client
      include DataCollector::Core
      include GCloud

      attr_accessor :client, :logger, :gconfig, :client_config

      def initialize(client_config: nil, client: nil, logger: Logger.new(STDOUT), gconfig: {})

        @client_config = client_config
        @client = client
        @logger = logger
        @gconfig = gconfig

        @logger.level = Logger::DEBUG   

        if @client_config.nil?
          # Set up the DataCollector configuration
          @client_config = DataCollector::Core.config
          
          @client_config.path  = '/app/config/'
          @client_config.name  = 'config.yml'

          commandline_arguments = parse_commandline_arguments()
          if commandline_arguments[:config_file]
            @client_config.path = File.dirname(commandline_arguments[:config_file])
            @client_config.name = File.basename(commandline_arguments[:config_file])
          end     
          
        end

        if @client_config[:gconfig_application_credentials_file].nil?
          raise "Please set the path of your Google Cloud service account credentials JSON file. example: /app/config/application_default_credentials.json"
        end
        ENV['GOOGLE_APPLICATION_CREDENTIALS'] = @client_config[:gconfig_application_credentials_file]

        if @client_config[:gconfig_file].nil?
          raise "Please set the path of the service config JSON file. example: /app/config/application_default_credentials.json"
        end

        @gconfig = JSON.parse( File.read(  ENV['GOOGLE_APPLICATION_CREDENTIALS'] ), symbolize_names: true)
        
        if @gconfig[:quota_project_id].nil?
          raise "quota_project_id is missing inpplication_default_credentials.json "
        end
        
        ENV['GOOGLE_CLOUD_PROJECT'] = @gconfig[:quota_project_id]

        @client = Google::Cloud::Storage.new()
        @bucket = @client.bucket @client_config[:gconfig_storage_bucket]

      end
    

      def read_buckets
        #pp "######################### Bucket wired-coder-368209 overview "
        @client.buckets.all do |bucket|
        #  puts bucket.name
        # puts  "-------------------"
        #  puts bucket.location
        #  puts bucket.files.count
        end
      end

      def file_exists?(file:)
        file = @bucket.file(file)
        unless file.nil?
          true
        else
          false
        end
      end

      def upload_to_google_storage(source:, target:)
        if File.exist?(source)
          @bucket.create_file(source,target)
        else
          raise "Failed to upload #{source}. It does not exist."
        end
      rescue Exception => e
        pp e
        # no no no
      end
      

      def download_from_google_storage(source:, target:)
        file = @bucket.file(source)
        output_dir = File.dirname( target ) 
        FileUtils.mkdir_p(output_dir) unless File.directory?( output_dir )
        if file&.exists?
          file.download target, verify: :none
        else
          raise "#{source} Not found in Google Cloud Storage" 
        end
      rescue Exception => e
        pp "Error in download_from_google_storage"
        pp e
        # no no no
      end

      def remove_from_google_storage(file:)
        file = @bucket.file(file)
        unless file.nil?
          file.delete
        end
      rescue Exception => e
        pp e
        # no no no
      end

    end
  end
end
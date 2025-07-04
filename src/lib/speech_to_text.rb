#encoding: UTF-8
require 'exiftool_vendored'
require "google/cloud/speech/v1" # https://cloud.google.com/ruby/docs/reference/google-cloud-speech-v1/latest
require 'data_collector'
require 'optparse'

require_relative './helper'
require_relative './storage'

module GCloud
  module SpeechToText
   class Client
      include DataCollector::Core
      include GCloud

      attr_accessor :client, :logger, :gconfig, :client_config

      GCLOUD_SERIVCE_CONFIG_FILE="speech_to_text.json"

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
          @client_config[:gconfig_file] = File.join( @client_config[:gconfig_path], GCLOUD_SERIVCE_CONFIG_FILE )
          if @client_config[:gconfig_file].nil?
            @logger.error ("Unable to find #{ @client_config[:gconfig_file]}")
            raise "Please set the gconfig_path of the service config. example: /app/config/"
          end
        end

        @client = Google::Cloud::Speech::V1::Speech::Client.new
        @gconfig = JSON.parse(  File.read(@client_config[:gconfig_file]) , symbolize_names: true)

        @gStorageClient = GCloud::Storage::Client.new(client_config: @client_config, logger:@logger)

        @gStorageClient.logger.info "Starting Google Storage Client"
        @gStorageClient.client_config.keys
        input_files =  @gStorageClient.read_buckets

      end




      def response

        if @gconfig[:audio][:uri].nil? && @gconfig[:audio][:content].nil?
          raise "No audio provided to process"
        end

        unless @gconfig[:audio][:uri].nil?
          google_cloud_file =  File.join( "audio-files", File.basename(@gconfig[:audio][:uri])  )
          
          @gStorageClient.upload_to_google_storage(source: @gconfig[:audio][:uri], target: google_cloud_file)
          @gconfig[:audio] = { "uri": "gs://#{ @client_config[:gconfig_storage_bucket] }/#{google_cloud_file}" }

          operation = @client.long_running_recognize @gconfig
          puts "Operation started"

          operation.wait_until_done!
          
          raise operation.results.message if operation.error?
          
          pp "Operation finished with transcription model: #{@gconfig[:config][:model]}"

          @gStorageClient.remove_from_google_storage(file: google_cloud_file)

          return JSON.parse( operation.response.to_json , symbolize_names: true)
          
        end
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
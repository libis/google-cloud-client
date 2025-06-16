#encoding: UTF-8
require "google/cloud/video_intelligence/v1"
require 'data_collector'
require_relative './helper'

module GCloud
  module VideoIntelligence
   class Client
      include DataCollector::Core
      include GCloud::VideoIntelligence

      attr_accessor :client, :logger, :gconfig, :client_config

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
        ENV['GOOGLE_APPLICATION_CREDENTIALS'] = @client_config[:gconfig_application_credentials_file]

        if @client_config[:gconfig_file].nil?
          raise "Please set the path of the service config JSON file. example: /app/config/application_default_credentials.json"
        end

        @client = Google::Cloud::VideoIntelligence::V1::VideoIntelligenceService::Client.new
        @gconfig = JSON.load ( File.open(@client_config[:gconfig_file]) )

      end

      def response
        @logger.debug "Starting video annotation process with Google Video Intelligence API"
        @logger.debug "Client configuration: features #{@gconfig["features"]}"
        @logger.debug "Client configuration: video_context #{@gconfig["video_context"]}"
        
        response = @client.annotate_video(::Google::Cloud::VideoIntelligence::V1::AnnotateVideoRequest.new ( @gconfig ) )
        
        response.wait_until_done!
        raise response.results.message if response.error?
        response.response
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
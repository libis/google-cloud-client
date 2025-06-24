#encoding: UTF-8
$LOAD_PATH << '.' << './lib'
require 'logger'
require 'streamio-ffmpeg'
require_relative './lib/video_intelligence'

begin

  google_ai_service = "Video Intelligence"

  start_parsing = DateTime.now.to_time
  
  gClient = GCloud::VideoIntelligence::Client.new
  gClient.logger = Logger.new(STDOUT)

  gClient.logger.info "Starting Google #{google_ai_service} Client"
  # gClient.client_config.keys
  input_files =  gClient.select_files
  gClient.logger.info "Selected input files: #{input_files}"
  gClient.logger.info "Input files count: #{input_files.count}"

  if input_files.empty?
    gClient.logger.warn "No input files found in the specified directories. ( #{input_files} )" 
    exit 0
  end

  input_files.each do |input_file|
    begin
      gClient.logger.info "Processing file: #{input_file}"

      unless gClient.gconfig.nil?
        initial_config = gClient.gconfig.clone
      end

      output_path = File.join( gClient.client_config[:output_dir], File.basename(input_file) )

      if File.file?(output_path) 
        gClient.logger.info "#{output_path} exists. Skipping video intelligence request for file: #{input_file}"
        next     
      end

      metadata = gClient.get_metadata_from_record(input_file)

      unless metadata[:language_code].nil? || metadata[:language_code].empty?
        unless gClient.gconfig[:video_context][:text_detection_config].nil?
          gClient.gconfig[:video_context][:text_detection_config][:language_hints] = [ gClient.gconfig[:video_context][:text_detection_config][:language_hints] , metadata[:language_code] ].flatten.uniq.compact.reject { |c| c.empty? }
        end
        unless gClient.gconfig[:video_context][:speech_transcription_config].nil?
          gClient.gconfig[:video_context][:speech_transcription_config][:language_code] = metadata[:language_code]
        end
      end

      gClient.client_config[:output_file] = "#{ File.basename(input_file , File.extname(input_file) ) }_video_intelligence_#{ metadata[:language_code].gsub('-','_')}.json"

      output_file = File.join( gClient.client_config[:output_dir], gClient.client_config[:output_file]) 

      if File.file?(output_file) 
        gClient.logger.info "#{output_file} exists. Skipping #{google_ai_service} request for input_file: #{input_file}"
        next      
      end

      if gClient.client_config[:use_google_storage]
        gClient.client_config[:input_file] = input_file
      else
        ## This will notnt use the google cloud storage option 
        gClient.gconfig[:input_content] = File.open(input_file, 'rb') { |io| io.read }
      end

      response = gClient.response

      response[:file_generatedAtTime] = Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")
      response[:_source] = { "@id": metadata[:recordid] }      

      # pp response

      File.open(output_file, 'w') do |f|
        f.write(  response.to_json )
      end
      unless gClient.gconfig.nil?
        gClient.gconfig = initial_config
      end

      output_path = File.join( gClient.client_config[:output_dir], File.basename(input_file) )

      FileUtils.move(input_file, output_path)
      gClient.logger.info "#{input_file} processed and saved to: #{output_path}"
    rescue GCloud::VideoIntelligence::ToLargeFileError => e
      puts "Skipping file due to size: #{e.message}"
      next
    rescue StandardError => e
      puts "Unexpected error: #{e.message}"
      raise e
    end
  end

rescue StandardError => e
  puts "An error occurred: #{e.message}"
  puts "Backtrace:\n#{e.backtrace.join("\n")}"
  exit 1
end

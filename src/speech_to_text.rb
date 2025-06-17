#encoding: UTF-8
$LOAD_PATH << '.' << './lib'
require 'logger'
require_relative './lib/speech_to_text'

begin

  google_ai_service = "Speech To Text"

#  language_code = "en-US"
#  TRANSCRIPTION_MODEL = "default" # "latest_long" or "latest_short"

  start_parsing = DateTime.now.to_time
  
  gClient = GCloud::SpeechToText::Client.new
  gClient.logger = Logger.new(STDOUT)

  gClient.logger.info "Starting Google #{google_ai_service} Client"
  input_files =  gClient.select_files
  gClient.logger.info "Selected input files: #{input_files}"
  gClient.logger.info "Input files count: #{input_files.count}"

  if input_files.empty?
    gClient.logger.warn "No input files found in the specified directories. ( #{input_files} )" 
    exit 0
  end

  input_files.each do |input_file|
    gClient.logger.info "Processing file: #{input_file}"

    unless gClient.gconfig.nil?
      initial_config = gClient.gconfig.clone
    end

    audio_file = input_file

    if File.extname(audio_file) == ".mp4"
      audio_file = "#{File.dirname(audio_file)}/#{File.basename(audio_file,'.*')}.flac"
      begin
        gClient.rip_audio_from_video(input_file, audio_file)
      rescue
        pp "MAY DAY MAY DAY"
        gClient.logger.warn "Unable to extract audio from #{input_file}"
        exit
        next
      end
    end
    
    gClient.gconfig[:audio][:uri] = audio_file

    audio_file_metadata = Exiftool.new(audio_file)

    unless audio_file_metadata.to_hash[:sample_rate].nil?
       gClient.gconfig[:config][:sample_rate_hertz] = audio_file_metadata.to_hash[:sample_rate]
    end

    if File.extname(audio_file) == ".flac"
       gClient.gconfig[:config][:encoding] = "FLAC"
    end

    metadata = gClient.get_metadata_from_record(input_file)

    unless metadata[:language_code].nil?
      gClient.gconfig[:config][:language_code] = metadata[:language_code]
      gClient.gconfig[:config][:alternative_language_codes] = [ gClient.gconfig[:config][:alternative_language_codes] , metadata[:language_code] ].flatten.compact
    end

    output_file = File.join( gClient.client_config[:output_dir], "#{ File.basename(input_file , File.extname(input_file) ) }_speech_to_text_#{ metadata[:language_code].gsub('-','_')}.json") 

    if File.file?(output_file) 
      gClient.logger.info "#{output_file} exists. Skipping #{google_ai_service} request for input_file: #{input_file}"
      next
    end

    response = gClient.response

    response[:file_generatedAtTime] = Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")
    response[:_source] = { "@id": metadata[:recordid] }      

    File.open(output_file, 'w') do |f|
      f.write(  response.to_json )
    end
    unless gClient.gconfig.nil?
      gClient.gconfig = initial_config
    end

    output_path = File.join( gClient.client_config[:output_dir], File.basename(input_file) )

    FileUtils.move(input_file, output_path)
    gClient.logger.info "#{input_file} processed and saved to: #{output_path}"

  end

rescue StandardError => e
  puts "An error occurred: #{e.message}"
  puts "Backtrace:\n#{e.backtrace.join("\n")}"
  exit 1
end

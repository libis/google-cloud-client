#encoding: UTF-8
$LOAD_PATH << '.' << './lib'
require 'logger'
require 'mustache'
require_relative './lib/speech_to_text'

begin

  google_ai_service = "Speech To Text"

#  language_code = "en-US"
#  TRANSCRIPTION_MODEL = "default" # "latest_long" or "latest_short"

  start_parsing = Time.now
  
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

    recordid = gClient.get_record_id(input_file)

    unless gClient.gconfig.nil?
      initial_config = gClient.gconfig.clone
    end

    if File.extname(input_file) == ".json"
      input_hash = JSON.parse(File.read(input_file)) 
      audio_file = gClient.get_related_media_file(input_file)
      metadata = {}
      # "$..data.items[?(@.id == '#{recordid}')].category.snippet.title"
      # "$..data.items[?(@.id == '#{recordid}')]"   
      if gClient.client_config[:metadata_from_input]
        gClient.client_config[:metadata_from_input].each do |tag, jpath|
          tag = tag.to_s.gsub('_jpath', '').to_sym
          jpath =  jpath.gsub('{{recordid}}', recordid)
          path = JsonPath.new( jpath )
          metadata[tag] = path.on(input_hash).first unless path.on(input_hash).empty? 
        end
      end
    else
      metadata = gClient.get_metadata_from_record(input_file)
      audio_file = input_file
    end

    if audio_file.nil? || audio_file.empty?
      raise "No audio file found for input file: #{input_file}"
    end

    gClient.logger.info "Media file (audio): #{audio_file}"
    gClient.logger.info "metadata_file ?: #{input_file}"

    if File.extname(audio_file) == ".mp4"
      audio_file = "#{File.dirname(audio_file)}/#{File.basename(audio_file,'.*')}.flac"
      begin
        gClient.rip_audio_from_video(input_file, audio_file)
      rescue
        gClient.logger.warn "Unable to extract audio from #{input_file}"
        exit
        next
      end
    end
    
    gClient.gconfig[:audio][:uri] = audio_file

    gClient.client_config[:input_file] = audio_file

    audio_file_metadata = Exiftool.new(audio_file)
   
    unless audio_file_metadata.to_hash[:sample_rate].nil?
      gClient.gconfig[:config][:sample_rate_hertz]   = audio_file_metadata.to_hash[:sample_rate]
      gClient.gconfig[:config][:audio_channel_count] = audio_file_metadata.to_hash[:channels]
    end

    if File.extname(audio_file) == ".flac"
      gClient.gconfig[:config][:encoding] = "FLAC"
    end

    # use default language code (as configured in speech_to_text.json) if not provided
    unless metadata.nil? || metadata[:language_code].nil? || metadata[:language_code].empty?
      gClient.gconfig[:config][:language_code] = metadata[:language_code]
      gClient.gconfig[:config][:alternative_language_codes] = [ gClient.gconfig[:config][:alternative_language_codes] , metadata[:language_code] ].flatten.compact
    end

    metadata[:google_ai_service] = google_ai_service.downcase.gsub(' ', '_')
    metadata[:language_code] = gClient.gconfig[:config][:language_code]

    unless gClient.client_config[:output_file_template].nil? || gClient.client_config[:output_file_template].empty?
      output_file = gClient.client_config[:output_file_template]
      output_file= Mustache.render(gClient.client_config[:output_file_template], metadata)
      output_file = File.join( gClient.client_config[:output_dir], output_file ) 
    else
      output_file = File.join( gClient.client_config[:output_dir], "#{ File.basename(input_file , File.extname(input_file) ) }_speech_to_text_#{ gClient.gconfig[:config][:language_code].gsub('-','_')}.json") 
    end
    
    if File.file?(output_file) 
      gClient.logger.info "#{output_file} exists. Skipping #{google_ai_service} request for input_file: #{input_file}"
      next
    end

    gClient.client_config[:output_file] = output_file


    response = gClient.response

    response[:file_generatedAtTime] = Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")
    response[:_source] = { "@id": metadata[:recordid] }      

    output_dir = File.dirname( output_file ) 
    FileUtils.mkdir_p(output_dir) unless File.directory?( output_dir )
    
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

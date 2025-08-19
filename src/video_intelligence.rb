#encoding: UTF-8
$LOAD_PATH << '.' << './lib'
require 'logger'
require 'mustache'
require 'streamio-ffmpeg'
require_relative './lib/video_intelligence'

begin

  google_ai_service = "Video Intelligence"

#  language_code = "en-US"
#  TRANSCRIPTION_MODEL = "default" # "latest_long" or "latest_short"

  start_parsing = DateTime.now.to_time
  
  gClient = GCloud::VideoIntelligence::Client.new
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
    begin
      gClient.logger.info "Processing file: #{input_file}"

      recordid = gClient.get_record_id(input_file)

      unless gClient.gconfig.nil?
        initial_config = gClient.gconfig.clone
      end

      if File.extname(input_file) == ".json"
        media_file = gClient.get_related_media_file(input_file)
        unless gClient.client_config[:metadata_from_input]
          metadata = gClient.get_metadata_from_record(input_file)
        else
          input_hash = JSON.parse(File.read(input_file))                     
          # "$..data.items[?(@.id == '#{recordid}')].category.snippet.title"
          # "$..data.items[?(@.id == '#{recordid}')]"
          metadata = {record: input_hash, recordid: recordid}  
          gClient.client_config[:metadata_from_input].each do |tag, jpath|
            tag = tag.to_s.gsub('_jpath', '').to_sym
            jpath = jpath.gsub('{{recordid}}', recordid)
            path = JsonPath.new( jpath )
            metadata[tag] = path.on(input_hash).first unless path.on(input_hash).empty? 
          end     
        end
      else
        metadata = gClient.get_metadata_from_record(input_file)
        media_file = input_file
      end

      if media_file.nil? || media_file.empty?
        raise "No media file found for input file: #{input_file}"
      end

      gClient.logger.info "Media file (video): #{media_file}"
      gClient.logger.info "metadata_file: #{input_file}"

      if gClient.client_config[:use_google_storage]
        gClient.client_config[:input_file] = media_file
      else
        ## This will notnt use the google cloud storage option 
        gClient.gconfig[:input_content] = File.open(input_file, 'rb') { |io| io.read }
      end

      # use default language code (as configured in speech_to_text.json) if not provided
      unless metadata.nil? || metadata[:language_code].nil? || metadata[:language_code].empty?
        gClient.gconfig[:video_context][:speech_transcription_config][:language_code] = metadata[:language_code]
        gClient.gconfig[:video_context][:language_hints] = [ gClient.gconfig[:video_context][:language_hints]  , metadata[:language_code] ].flatten.compact
      end

      unless metadata.nil? || metadata[:record][:keywords].nil? || metadata[:record][:keywords].empty? 
        metadata[:record][:keywords] = [ metadata[:record][:keywords] ] unless metadata[:record][:keywords].is_a?(Array)
        gClient.gconfig[:video_context][:speech_transcription_config][:speech_contexts] = [ { "phrases": metadata[:record][:keywords] } ]
      end

      metadata[:google_ai_service] = google_ai_service.downcase.gsub(' ', '_')
      metadata[:language_code] = gClient.gconfig[:video_context][:speech_transcription_config][:language_code]

      unless gClient.client_config[:output_file_template].nil? || gClient.client_config[:output_file_template].empty?
        output_file = gClient.client_config[:output_file_template]
        output_file= Mustache.render(gClient.client_config[:output_file_template], metadata)
        output_file = File.join( gClient.client_config[:output_dir], output_file ) 
      else
        output_file = File.join( gClient.client_config[:output_dir], "#{ File.basename(input_file , File.extname(input_file) ) }_#{ metadata[:google_ai_service] }_#{ metadata[:language_code].gsub('-','_')}.json") 
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

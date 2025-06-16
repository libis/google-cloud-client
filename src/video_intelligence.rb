#encoding: UTF-8
$LOAD_PATH << '.' << './lib'
require 'logger'
require_relative './lib/video_intelligence'

begin

  start_parsing = DateTime.now.to_time
  
  gClient = GCloud::VideoIntelligence::Client.new
  gClient.logger = Logger.new(STDOUT)

  gClient.logger.info "Starting Google Video Intelligence Client"
  # gClient.client_config.keys
  input_files =  gClient.select_files
  gClient.logger.info "Selected input files: #{input_files}"
  gClient.logger.info "Input files count: #{input_files.count}"

  if input_files.empty?
    gClient.logger.warn "No input files found in the specified directories. ( #{input_files} )" 
    exit 0
  end

  input_files.each do |video_file_path|
    gClient.logger.info "Processing file: #{video_file_path}"

    unless gClient.gconfig["video_context"].nil?
      initial_config = gClient.gconfig["video_context"]
    end

    output_path = File.join( gClient.client_config[:output_dir], File.basename(video_file_path) )

    if File.file?(output_path) 
      gClient.logger.info "#{output_path} exists. Skipping video intelligence request for file: #{video_file_path}"
      next
    end

    gClient.gconfig["input_content"] = File.open(video_file_path, 'rb') { |io| io.read }

    recordid = File.basename(video_file_path).gsub( Regexp.new( gClient.client_config[:recordid_from_file_name][:search]), gClient.client_config[:recordid_from_file_name][:replace])

    # Get the record from the elasticsearch index with the process that is defined in the client config
    es_record = gClient.method( gClient.client_config[:get_record][:process] ) .call(recordid)

    if es_record.nil?  
      gClient.logger.warn "Record not found in Elasticsearch index for ID: #{recordid}. Skipping file: #{video_file_path}"
    else
      if es_record.is_a?(Hash) && es_record.keys.include?("error")
        gClient.logger.war "Error retrieving record for ID: #{recordid}. Error: #{es_record['error']}"
        next
      end

      if es_record.is_a?(Hash) && es_record.keys.include?("_source")
        if es_record["_source"].keys.include?("inLanguage")
          language_code = es_record["_source"]["inLanguage"]["@id"]
          unless language_code.nil? || language_code == "und"
             language_code = gClient.language_code_to_bcp47(language_code)
          end
          gClient.logger.info "Language code for video file: #{language_code}"
          if language_code.nil? || language_code == "und"
            #pp es_record["_source"].keys
            #pp es_record["_source"]["comment"].keys
            pp es_record["_source"]["comment"].class
            if es_record["_source"]["comment"].nil?
              pp "es_record[\"_source\"][\"comment\"] !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NILNILNINLIN"
            end
            unless es_record["_source"]["comment"].nil?
              es_record["_source"]["comment"] = [ es_record["_source"]["comment"] ] unless es_record["_source"]["comment"].is_a?(Array)
              language_code_list = es_record["_source"]["comment"].map{ |l| l["inLanguage"]["@id"] }
              language_code = language_code_list.group_by { |e| e }.max_by { |_, v| v.size }&.first
              language_code = gClient.language_code_to_bcp47(language_code)
            end
          end
          
          gClient.logger.info "Language code for video file: #{language_code}"
          unless language_code.nil? || language_code.empty?
            unless gClient.gconfig["video_context"]["text_detection_config"].nil?
              gClient.gconfig["video_context"]["text_detection_config"]["language_hints"] << language_code if !gClient.gconfig["video_context"]["text_detection_config"]["language_hints"].include?(language_code)
            end
            unless gClient.gconfig["video_context"]["speech_transcription_config"].nil?
              gClient.gconfig["video_context"]["speech_transcription_config"]["language_code"] = language_code
            end
          end
        end
      end
    end

    pp "=================== >>language_code #{language_code} << ==================="
    if language_code.nil?
      language_code = "un_UN"
    end

    output_file = File.join( gClient.client_config[:output_dir], "#{ File.basename(video_file_path , File.extname(video_file_path) ) }_video_intelligence_#{ language_code.gsub('-','_')}.json") 

    if File.file?(output_file) 
      gClient.logger.info "Output file already exists: #{output_file}. Skipping video intelligence request for file: #{video_file_path}"  
      next
    end

    # Perform the video intelligence request
    gClient.logger.info "Sending video intelligence request for file: #{video_file_path}"

    response = gClient.response

    response = JSON.parse( response.to_json )

    response["file_generatedAtTime"] = Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")
    response["_source"] = { "@id": recordid }      
    
    File.open(output_file, 'w') do |f|
      f.write(  response.to_json  )
    end
    unless gClient.gconfig["video_context"].nil?
      gClient.gconfig["video_context"] = initial_config
    end

##########################################################################
# This service does not support any language detection. It's no use to run this service with en-US as defualt !!!!    
#    if gClient.gconfig["features"].include?("SPEECH_TRANSCRIPTION")
#      language_code = "en-US"
#      gClient.gconfig["video_context"]["speech_transcription_config"]["language_code"] = language_code
#      gClient.gconfig["features"] = ["SPEECH_TRANSCRIPTION"] 
#  
#      output_file = File.join( gClient.client_config[:output_dir], "#{ File.basename(video_file_path , File.extname(video_file_path) ) }_video_intelligence_#{ language_code.gsub('-','_')}.json") 
#
#      pp "=================== >>language_code #{language_code} << ==================="
#
#      # Perform the video intelligence request
#      gClient.logger.info "Sending video intelligence request for file: #{video_file_path}"
#
#      response = gClient.response
#      File.open(output_file, 'w') do |f|
#        f.write( response.to_json )
#      end
#    end
##########################################################################



    output_path = File.join( gClient.client_config[:output_dir], File.basename(video_file_path) )

    FileUtils.move(video_file_path, output_path)
    gClient.logger.info "Video file processed and saved to: #{output_path}"

  end

rescue StandardError => e
  puts "An error occurred: #{e.message}"
  puts "Backtrace:\n#{e.backtrace.join("\n")}"
  exit 1
end

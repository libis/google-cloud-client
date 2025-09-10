#encoding: UTF-8
require 'elasticsearch'
require 'find'

DEFAULT_REGIONS = {
 "af" => "ZA", "am" => "ET", "ar" => "001", "as" => "IN", "az" => "AZ",
 "be" => "BY", "bg" => "BG", "bn" => "BD", "bs" => "BA", "ca" => "ES",
 "cs" => "CZ", "cy" => "GB", "da" => "DK", "de" => "DE", "el" => "GR",
 "en" => "US", "es" => "ES", "et" => "EE", "eu" => "ES", "fa" => "IR",
 "fi" => "FI", "fil" => "PH", "fr" => "FR", "ga" => "IE", "gl" => "ES",
 "gu" => "IN", "ha" => "NG", "he" => "IL", "hi" => "IN", "hr" => "HR",
 "hu" => "HU", "hy" => "AM", "id" => "ID", "ig" => "NG", "is" => "IS",
 "it" => "IT", "ja" => "JP", "jv" => "ID", "ka" => "GE", "kk" => "KZ",
 "km" => "KH", "kn" => "IN", "ko" => "KR", "ky" => "KG", "lb" => "LU",
 "lo" => "LA", "lt" => "LT", "lv" => "LV", "mg" => "MG", "mi" => "NZ",
 "mk" => "MK", "ml" => "IN", "mn" => "MN", "mr" => "IN", "ms" => "MY",
 "mt" => "MT", "my" => "MM", "ne" => "NP", "nl" => "NL", "no" => "NO",
 "or" => "IN", "pa" => "IN", "pl" => "PL", "ps" => "AF", "pt" => "BR",
 "ro" => "RO", "ru" => "RU", "sd" => "PK", "si" => "LK", "sk" => "SK",
 "sl" => "SI", "sq" => "AL", "sr" => "RS", "sv" => "SE", "sw" => "TZ",
 "ta" => "IN", "te" => "IN", "th" => "TH", "ti" => "ET", "tr" => "TR",
 "uk" => "UA", "ur" => "PK", "uz" => "UZ", "vi" => "VN", "yi" => "001",
 "yo" => "NG", "zh" => "CN", "zu" => "ZA"
}

module GCloud

  def get_record_id(input_file)
    File.basename(input_file).gsub( Regexp.new( @client_config[:recordid_from_file_name][:search] ), @client_config[:recordid_from_file_name][:replace])
  end

  def parse_commandline_arguments
    
    options = {}

    parser = OptionParser.new do |opts|
      opts.banner = "Usage: script.rb [options]"

      opts.on("-c", "--config FILE", "Path to config file") do |file|
        options[:config_file] = file
      end

      opts.on("-h", "--help", "Prints this help") do
        puts opts
        exit
      end
    end
    
    # Parse the command-line arguments
    begin
      parser.parse!
      return options
    rescue OptionParser::InvalidOption => e
      puts e
      puts parser
      exit 1
    end

  end

  def select_files_from_dir(input_dir)
    source_files = []
    excluded_dir =  "/tobig/"
    
    if File.directory?(input_dir)
      Find.find(input_dir) do |file|
        if File.directory?(file)
          @logger.debug "Skipping directories: #{file}"
          next # Skip directories
        end
        if file.match?(excluded_dir)
          Find.prune # Skip this directory and its contents
        else
          unless @client_config[:record_pattern].nil?
            if file.match?(@client_config[:record_pattern])
              @logger.debug "Adding file: #{file}"
            else
              @logger.debug "Skipping file: #{file} (does not match pattern)"
              next
            end
          else
            @logger.debug "Adding file: #{file}"
          end
          source_files << file
        end
      end
         else
      raise "Input directory does not exist: #{input_dir}"
    end
    
    source_files 
  end

  def search_file_in_dir(recordid, params: {})
    dirs = params[:dirs] || []
    found_file = nil
    unless params[:pattern].nil? || params[:pattern].empty?
       recordid = Mustache.render(params[:pattern], {recordid: recordid})
    end

    dirs.each do |dir|
      Find.find(dir) do |file|
        if File.file?(file) && File.basename(file).include?(recordid)
          found_file = file
          @logger.debug "Found file: #{found_file}"
          break
        end
      end
      break if found_file # Exit the loop if the file is found
    end
    found_file
  end

  def metadata_from_file(recordid, params: {})
    metadata_file = search_file_in_dir(recordid, params: params)
    @logger.debug "metadata_file : #{metadata_file}"
    unless metadata_file.nil?
      params[:input_file] = metadata_file
      metadata = file_get_record(recordid, params: params)
      return metadata
    end
  end
  

  def elasticsearch_get_record(recordid, params: {})
    # This method should be implemented to retrieve a record from Elasticsearch
    # For now, it returns nil to simulate a record not found
    # nil
    begin

      @es_url = URI.parse( ENV['ES_URL'] ||params[:es_host] )
      @logger.debug "Elasticsearch Host: #{ @es_url.host}"
      
      @es_url.user = ENV['ES_USER'] if ENV['ES_USER'] && ENV['ES_PASSWORD']
      @es_url.password = ENV['ES_PASSWORD'] if ENV['ES_USER'] && ENV['ES_PASSWORD']

      @es_client = Elasticsearch::Client.new url:  @es_url, transport_options: {  ssl:  { verify: false } }

      if check_elasticsearch_health()
        @logger.debug "Elasticsearch is healthy"
        es_index = params[:es_index]
        
        @es_url.path="/#{es_index}/_doc/#{recordid}"

        record = send_elastic_request( @es_url  ) 
        
        if record.status.success?
          @logger.debug "Record retrieved successfully from Elasticsearch for ID: #{recordid}"
          record = JSON.parse(record.body.to_s)
          if record.is_a?(Hash) && record.keys.include?("error")
            @logger.warn "Error retrieving record for ID: #{recordid}. Error: #{record['error']}"
            return nil
          end
          if record_metadata.is_a?(Hash) && record_metadata.keys.include?("_source")
            return record["_source"]
          end
        end
        @logger.error "Failed to retrieve record from Elasticsearch for ID: #{recordid}. Response: #{record.status}"
        return nil
      else
        raise "Elasticsearch is not healthy"
      end

      #####  @es_client elasticsearch gem version 7.5.0 is not compatible with google-cloud-video_intelligence-v1', '~> 1.3' ####
      exit
      

      #es_url.path = '/' + @client_config[:get_record_metadata][:params][:es_index] + '/_doc/' + recordid

      #@logger.debug "Elasticsearch URL: #{es_url.to_s}"
      #@logger.debug "Elasticsearch Params: #{@client_config[:get_record_metadata][:params]}"

      #response = HTTP.follow.get(es_url)
      #if response.status.success?
      #  record = JSON.parse(response.body.to_s)
      #  pp record
      #  
      #end
    exit
    rescue StandardError => e
      pp e
      @logger.error "Error retrieving record from Elasticsearch: #{e.message}"
      @logger.error "Error retrieving record from Elasticsearch for ID: #{recordid}"
      raise e
    end
  end

  def file_get_record(recordid, params: {})
    record = JSON.parse(File.read(params[:input_file]), symbolize_names: true)
    return record
  end
    
  def check_elasticsearch_health
          
    health = send_elastic_request( @es_url + "/_cluster/health") 

    if health.status.success?
      @logger.debug "Elasticsearch health check successful"
      status = JSON.parse( health.body )["status"]
      unless status === 'green' || status=== 'yellow'
        message = "ElasticSearch Health status not OK [ #{ status } ]"
        @logger.error message
        raise message
      end
    return true
    end
    return false

    #####  @es_client elasticsearch gem version 7.5.0 is not compatible with google-cloud-video_intelligence-v1', '~> 1.3' ####
    exit
    health = @es_client.cluster.health
    @logger.debug "cluster.health.status: #{health['status']}"
    
    if @es_client.info['version']['number'] != @es_version
        message = "Wrong Elasticsearch version on server: #{ @es_client.info['version']['number'] } on server but expected #{ @es_version }"
        @logger.warn message
        raise message
    end

    unless health['status'] === 'green' || health['status'] === 'yellow'
      message = "ElasticSearch Health status not OK [ #{health['status']} ]"
      @logger.error message
      raise message
    end
    return true
  
  rescue StandardError => e
    @logger.error "Error checking Elasticsearch health: #{e.message}"
    return false
  end

  def send_elastic_request(uri) 

    ctx = nil
    http_query_options = {}
    # shouldn't use this but we all do ...
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http_query_options[:ssl_context] = ctx

    http = HTTP.basic_auth(user: uri.user, pass: uri.password)

    pp uri
    http.follow.get( uri,  http_query_options)

  end

  def language_code_to_bcp47(language)
    if language.nil? || language.empty?
      return nil
    end

    # Normalize the language code to lowercase
    normalized_language = language.downcase

    # Check if the language code exists in the DEFAULT_REGIONS hash
    if DEFAULT_REGIONS.key?(normalized_language)
      region = DEFAULT_REGIONS[normalized_language]
      return "#{normalized_language}-#{region}"
    else
      @logger.warn "Language code '#{language}' not found in DEFAULT_REGIONS. Returning nil."
      return nil
    end
  end 
  
  def rip_audio_from_video(video_file_path, audio_file_path)
    # convert to mono channel, 16-bit PCM, 16kHz
    if File.extname(audio_file_path) == ".flac"
      system("ffmpeg -y -i #{video_file_path} -ac 1 -c:a flac #{audio_file_path}", exception: true) 
    else
      system("ffmpeg -y -i #{video_file_path} -acodec pcm_s16le -ac 1 -ar 16000 #{audio_file_path}", exception: true) 
    end
  end

  def get_metadata_from_record(input_file)
    recordid = get_record_id(input_file)
    @logger.info "Search related metadata file for ID: #{recordid}"
    @logger.debug "Extracting metadata fom record with ID: #{recordid}"

    # Get the record from the elasticsearch index with the process that is defined in the client config
    params = @client_config[:get_record_metadata][:params]
    params[:input_file] = input_file
    begin
      record_metadata = method( @client_config[:get_record_metadata][:process] ).call(recordid, params: params )
    rescue RuntimeError => e
      puts "An error occurred: #{e.message}"
      puts "Backtrace:\n#{e.backtrace.join("\n")}"
      exit 1
    rescue StandardError => e
      puts "An error occurred: #{e.message}"
      puts "Backtrace:\n#{e.backtrace.join("\n")}"
      return nil
    end

    if record_metadata.keys.include?("inLanguage")
      language_code = get_language_code_from_metadata(metadata: record_metadata)
    end
    
    {
      record: record_metadata,
      recordid: recordid,
      language_code: language_code
    }

  end

  def get_language_code_from_metadata(metadata: nil)
    language_code = ""
    language_code = metadata["inLanguage"]["@id"]
    unless language_code.nil? || language_code == "und"
        language_code = language_code_to_bcp47(language_code) || ""
    end
    if language_code.nil? || language_code == "und"
      unless metadata["comment"].nil?
        metadata["comment"] = [ metadata["comment"] ] unless metadata["comment"].is_a?(Array)
        language_code_list = metadata["comment"].map{ |l| l["inLanguage"]["@id"] }
        language_code = language_code_list.group_by { |e| e }.max_by { |_, v| v.size }&.first
        language_code = language_code_to_bcp47(language_code) || ""
      end
    end
    return language_code
  end

  def get_related_media_file(input_file)
    @logger.info "Search related media file for ID: #{input_file}"
    recordid = File.basename(input_file).gsub( Regexp.new( @client_config[:recordid_from_file_name][:search]), @client_config[:recordid_from_file_name][:replace])

    # Get the record from the elasticsearch index with the process that is defined in the client config
    begin
      media_file = method( @client_config[:get_record_media][:process] ).call(recordid, params: @client_config[:get_record_media][:params])
    rescue RuntimeError => e
      puts "An error occurred: #{e.message}"
      puts "Backtrace:\n#{e.backtrace.join("\n")}"
      exit 1
    rescue StandardError => e
      puts "An error occurred: #{e.message}"
      puts "Backtrace:\n#{e.backtrace.join("\n")}"
      return nil
    end

    if media_file.nil?
      @logger.warn "No media_file found with #{ @client_config[:get_record_media][:process] } for ID: #{recordid}"
      return nil
    else
      return media_file
    end

  end
 
end
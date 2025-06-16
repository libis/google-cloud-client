require 'elasticsearch'

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
  module VideoIntelligence
    def select_files_from_dir(input_dir)
      source_files = []
      if File.directory?(input_dir)
        Dir.glob("#{input_dir}/*").each do |file|
          if File.file?(file)
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
          if File.directory?(file)
            source_files << select_files_from_dir(file)
            source_files.flatten!
          end
        end
      else
        raise "Input directory does not exist: #{input_dir}"
      end
      
      source_files

    end

    def elasticsearch_get_record(recordid)
      # This method should be implemented to retrieve a record from Elasticsearch
      # For now, it returns nil to simulate a record not found
      # nil
      begin

        @es_url = URI.parse( ENV['ES_URL'] || @client_config[:get_record][:params][:es_host] )
        @logger.debug "Elasticsearch Host: #{ @es_url.host}"
        
        @es_url.user = ENV['ES_USER'] if ENV['ES_USER'] && ENV['ES_PASSWORD']
        @es_url.password = ENV['ES_PASSWORD'] if ENV['ES_USER'] && ENV['ES_PASSWORD']

        @es_client = Elasticsearch::Client.new url:  @es_url, transport_options: {  ssl:  { verify: false } }

        if check_elasticsearch_health()
          @logger.debug "Elasticsearch is healthy"
          es_index = @client_config[:get_record][:params][:es_index]
          
          @es_url.path="/#{es_index}/_doc/#{recordid}"

          record = send_elastic_request( @es_url  ) 
         
          if record.status.success?
            @logger.debug "Record retrieved successfully from Elasticsearch for ID: #{recordid}"
            record = JSON.parse(record.body.to_s)
            return record
          end
          @logger.error "Failed to retrieve record from Elasticsearch for ID: #{recordid}. Response: #{record.status}"
        else
          raise "Elasticsearch is not healthy"
        end

        #####  @es_client elasticsearch gem version 7.5.0 is not compatible with google-cloud-video_intelligence-v1', '~> 1.3' ####
        exit
        

        #es_url.path = '/' + @client_config[:get_record][:params][:es_index] + '/_doc/' + recordid

        #@logger.debug "Elasticsearch URL: #{es_url.to_s}"
        #@logger.debug "Elasticsearch Params: #{@client_config[:get_record][:params]}"

        #response = HTTP.follow.get(es_url)
        #if response.status.success?
        #  record = JSON.parse(response.body.to_s)
        #  pp record
        #  
        #end
      exit
      rescue StandardError => e
        @logger.error "Error retrieving record from Elasticsearch: #{e.message}"
        @logger.error "Error retrieving record from Elasticsearch for ID: #{recordid}"
        raise e
      end
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
  end
end

# Google Cloud Client

A Ruby client for interacting with Google Cloud services, including Video Intelligence.

## Features

- Authentication with Google Cloud
- Simple API for common Google Cloud operations
- Integration with Google Video Intelligence API

## Configuration

The application uses the following configuration files:

- `config.yml`: Main configuration file
- `application_default_credentials.json`: Google Cloud authentication credentials
- `video_intelligence.json`: Configuration for the Video Intelligence API

### `config.yml` Example
```yaml
record_pattern: ".*.mp4"  # Pattern used to select input files
recordid_from_file_name: # Extract record ID from filename using search and replace
  :search: 'regex' #regex 
   :replace: 'xxx_\1' #reges with groups
get_record:
  process: elasticsearch_get_record  # Process to retrieve record metadata
  params:   # Parameters for the process
input_dirs: ["input_folder"]  # Folders to search for input files
output_dir: "output_folder"  # Folder where results are stored
es_host: "localhost:9200"  # Elasticsearch host
es_index: "index"  # Elasticsearch index
log_file: "log.txt"  # Log file path
gconfig_file: "/config/video_intelligence.json"  # Google API config
gconfig_application_credentials_file: "/config/application_default_credentials.json"  # Auth credentials
```

### application_default_credentials
Refer to the Google Cloud documentation for setting up this file. (https://cloud.google.com/docs/authentication/application-default-credentials)

### video intelligence
https://cloud.google.com/video-intelligence/docs/text-detection  
https://cloud.google.com/video-intelligence/docs/transcription  
https://cloud.google.com/video-intelligence/docs/feature-label-detection  

## Usage
### video intelligence
#### To run the Video Intelligence process:  
```shell
docker-compose run --rm google_cloud_client ruby src/video_intelligence.rb
```

#### Process Overview
1. Select video files from input_dirs matching record_pattern.
2. Extract record_id from the filename using the get_record procedure.
3. Update video_intelligence.json with metadata from the record (if necessary).
4. Send the video file to the Google Video Intelligence API.
5. Append file_generatedAtTime and record_id to the API response.
6. Save the response to output_dir.
7. Move the input video file to the output folder.

## Contributing

Contributions are welcome! Please open issues or submit pull requests.

## License

This project is licensed under the MIT License.
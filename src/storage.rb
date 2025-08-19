#encoding: UTF-8
$LOAD_PATH << '.' << './lib'
require 'logger'
require_relative './lib/storage'

begin

  start_parsing = Time.now
  
  gStorageClient = GCloud::Storage::Client.new
  gStorageClient.logger = Logger.new(STDOUT)

  gStorageClient.logger.info "Starting Google Storage Client"
  buckets =  gStorageClient.read_buckets
  pp buckets

rescue StandardError => e
  puts "An error occurred: #{e.message}"
  puts "Backtrace:\n#{e.backtrace.join("\n")}"
  exit 1
end

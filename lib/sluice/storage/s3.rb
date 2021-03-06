# Copyright (c) 2012 SnowPlow Analytics Ltd. All rights reserved.
#
# This program is licensed to you under the Apache License Version 2.0,
# and you may not use this file except in compliance with the Apache License Version 2.0.
# You may obtain a copy of the Apache License Version 2.0 at http://www.apache.org/licenses/LICENSE-2.0.
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the Apache License Version 2.0 is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the Apache License Version 2.0 for the specific language governing permissions and limitations there under.

# Authors::    Alex Dean (mailto:support@snowplowanalytics.com), Michael Tibben
# Copyright:: Copyright (c) 2012 SnowPlow Analytics Ltd
# License::   Apache License Version 2.0

require 'fog'
require 'thread'

module Sluice
  module Storage
    module S3

      # TODO: figure out logging instead of puts (https://github.com/snowplow/sluice/issues/2)
      # TODO: consider moving to OO structure (https://github.com/snowplow/sluice/issues/3)

      # Constants
      CONCURRENCY = 10 # Threads
      RETRIES = 3      # Attempts
      RETRY_WAIT = 10  # Seconds

      # Class to describe an S3 location
      # TODO: if we are going to impose trailing line-breaks on
      # buckets, maybe we should make that clearer?
      class Location
        attr_reader :bucket, :dir, :s3location

        # Parameters:
        # +s3location+:: the s3 location config string e.g. "bucket/directory"
        def initialize(s3_location)
          @s3_location = s3_location

          s3_location_match = s3_location.match('^s3n?://([^/]+)/?(.*)/$')
          raise ArgumentError, 'Bad S3 location %s' % s3_location unless s3_location_match

          @bucket = s3_location_match[1]
          @dir = s3_location_match[2]
        end

        def dir_as_path
          if @dir.length > 0
            return @dir+'/'
          else
            return ''
          end
        end

        def to_s
          @s3_location
        end
      end

      # Helper function to instantiate a new Fog::Storage
      # for S3 based on our config options
      #
      # Parameters:
      # +region+:: Amazon S3 region we will be working with
      # +access_key_id+:: AWS access key ID
      # +secret_access_key+:: AWS secret access key
      def new_fog_s3_from(region, access_key_id, secret_access_key)
        Fog::Storage.new({
          :provider => 'AWS',
          :region => region,
          :aws_access_key_id => access_key_id,
          :aws_secret_access_key => secret_access_key
        })
      end
      module_function :new_fog_s3_from

      # Determine if a bucket is empty
      #
      # Parameters:
      # +s3+:: A Fog::Storage s3 connection
      # +location+:: The location to check
      def is_empty?(s3, location)
        s3.directories.get(location.bucket, :prefix => location.dir).files().length <= 1
      end
      module_function :is_empty?

      # Download files from an S3 location to
      # local storage, concurrently
      #
      # Parameters:
      # +s3+:: A Fog::Storage s3 connection
      # +from_location+:: S3Location to delete files from      
      # +to_directory+:: Local directory to copy files to
      # +match_regex+:: a regex string to match the files to delete
      def download_files(s3, from_location, to_directory, match_regex='.+')

        puts "  downloading files from #{from_location} to #{to_directory}"
        process_files(:download, s3, from_location, match_regex, to_directory)
      end
      module_function :download_files    

      # Delete files from S3 locations concurrently
      #
      # Parameters:
      # +s3+:: A Fog::Storage s3 connection
      # +from_location+:: S3Location to delete files from
      # +match_regex+:: a regex string to match the files to delete
      def delete_files(s3, from_location, match_regex='.+')

        puts "  deleting files from #{from_location}"
        process_files(:delete, s3, from_location, match_regex)
      end
      module_function :delete_files

      # Copies files between S3 locations concurrently
      #
      # Parameters:
      # +s3+:: A Fog::Storage s3 connection
      # +from_location+:: S3Location to copy files from
      # +to_location+:: S3Location to copy files to
      # +match_regex+:: a regex string to match the files to copy
      # +alter_filename_lambda+:: lambda to alter the written filename
      # +flatten+:: strips off any sub-folders below the from_location
      def copy_files(s3, from_location, to_location, match_regex='.+', alter_filename_lambda=false, flatten=false)

        puts "  copying files from #{from_location} to #{to_location}"
        process_files(:copy, s3, from_location, match_regex, to_location, alter_filename_lambda, flatten)
      end
      module_function :copy_files

      # Moves files between S3 locations concurrently
      #
      # Parameters:
      # +s3+:: A Fog::Storage s3 connection
      # +from_location+:: S3Location to move files from
      # +to+:: S3Location to move files to
      # +match_regex+:: a regex string to match the files to move
      # +alter_filename_lambda+:: lambda to alter the written filename
      # +flatten+:: strips off any sub-folders below the from_location
      def move_files(s3, from_location, to_location, match_regex='.+', alter_filename_lambda=false, flatten=false)

        puts "  moving files from #{from_location} to #{to_location}"
        process_files(:move, s3, from_location, match_regex, to_location, alter_filename_lambda, flatten)
      end
      module_function :move_files

      # Download a single file to the exact path specified.
      # Has no intelligence around filenaming.
      # Makes sure to create the path as needed.
      #
      # Parameters:
      # +s3+:: A Fog::Storage s3 connection
      # +from_file:: A Fog::File to download
      # +to_file:: A local file path
      def download_file(s3, from_file, to_file)

        FileUtils.mkdir_p(File.dirname(to_file))

        # TODO: deal with bug where Fog hangs indefinitely if network connection dies during download

        local_file = File.open(to_file, "w")
        local_file.write(from_file.body)
        local_file.close
      end
      module_function :download_file

      private

      # Concurrent file operations between S3 locations. Supports:
      # - Copy
      # - Delete
      # - Move (= Copy + Delete)
      #
      # Parameters:
      # +operation+:: Operation to perform. :copy, :delete, :move supported
      # +s3+:: A Fog::Storage s3 connection
      # +from_location+:: S3Location to process files from
      # +match_regex+:: a regex string to match the files to process
      # +to_loc_or_dir+:: S3Location or local directory to process files to
      # +alter_filename_lambda+:: lambda to alter the written filename
      # +flatten+:: strips off any sub-folders below the from_location
      def process_files(operation, s3, from_location, match_regex='.+', to_loc_or_dir=nil, alter_filename_lambda=false, flatten=false)

        # Validate that the file operation makes sense
        case operation
        when :copy, :move, :download
          if to_loc_or_dir.nil?
            raise StorageOperationError "File operation %s requires the to_loc_or_dir to be set" % operation
          end
        when :delete
          unless to_loc_or_dir.nil?
            raise StorageOperationError "File operation %s does not support the to_loc_or_dir argument" % operation
          end
          if alter_filename_lambda.class == Proc
            raise StorageOperationError "File operation %s does not support the alter_filename_lambda argument" % operation
          end
        else
          raise StorageOperationError "File operation %s is unsupported. Try :download, :copy, :delete or :move" % operation
        end

        files_to_process = []
        threads = []
        mutex = Mutex.new
        complete = false
        marker_opts = {}

        # If an exception is thrown in a thread that isn't handled, die quickly
        Thread.abort_on_exception = true

        # Create Ruby threads to concurrently execute s3 operations
        for i in (0...CONCURRENCY)

          # Each thread pops a file off the files_to_process array, and moves it.
          # We loop until there are no more files
          threads << Thread.new do
            loop do
              file = false
              match = false

              # Critical section:
              # only allow one thread to modify the array at any time
              mutex.synchronize do

                while !complete && !match do
                  if files_to_process.size == 0
                    # S3 batches 1000 files per request.
                    # We load up our array with the files to move
                    files_to_process = s3.directories.get(from_location.bucket, :prefix => from_location.dir).files.all(marker_opts)
                    # If we don't have any files after the s3 request, we're complete
                    if files_to_process.size == 0
                      complete = true
                      next
                    else
                      marker_opts['marker'] = files_to_process.last.key

                      # By reversing the array we can use pop and get FIFO behaviour
                      # instead of the performance penalty incurred by unshift
                      files_to_process = files_to_process.reverse
                    end
                  end

                  file = files_to_process.pop

                  match = if match_regex.is_a? NegativeRegex
                            !file.key.match(match_regex.regex)
                          else
                            file.key.match(match_regex)
                          end
                end
              end

              # If we don't have a match, then we must be complete
              break unless match

              # Ignore any EMR-created _$folder$ entries
              break if file.key.end_with?('_$folder$')

              # Match the filename, ignoring directory
              file_match = file.key.match('([^/]+)$')
              break unless file_match

              if alter_filename_lambda.class == Proc
                filename = alter_filename_lambda.call(file_match[1])
              else
                filename = file_match[1]
              end

              # What are we doing? Let's determine source and target
              # Note that target excludes bucket name where relevant
              source = "#{from_location.bucket}/#{file.key}"
              case operation
              when :download
                target = name_file(file.key, filename, from_location.dir_as_path, to_loc_or_dir, flatten)
                puts "    DOWNLOAD #{source} +-> #{target}"
              when :move
                target = name_file(file.key, filename, from_location.dir_as_path, to_loc_or_dir.dir_as_path, flatten)
                puts "    MOVE #{source} -> #{to_loc_or_dir.bucket}/#{target}"
              when :copy
                target = name_file(file.key, filename, from_location.dir_as_path, to_loc_or_dir.dir_as_path, flatten)
                puts "    COPY #{source} +-> #{to_loc_or_dir.bucket}/#{target}"
              when :delete
                # No target
                puts "    DELETE x #{source}" 
              end

              # Download is a stand-alone operation vs move/copy/delete
              if operation == :download
                retry_x(
                  Sluice::Storage::S3,
                  [:download_file, s3, file, target],
                  RETRIES,
                  "      +/> #{target}",
                  "Problem downloading #{file.key}. Retrying.")
              end

              # A move or copy starts with a copy file
              if [:move, :copy].include? operation
                retry_x(
                  file,
                  [:copy, to_loc_or_dir.bucket, target],
                  RETRIES,
                  "      +-> #{to_loc_or_dir.bucket}/#{target}",
                  "Problem copying #{file.key}. Retrying.")
              end

              # A move or delete ends with a delete
              if [:move, :delete].include? operation
                retry_x(
                  file,
                  [:destroy],
                  RETRIES,
                  "      x #{source}",
                  "Problem destroying #{file.key}. Retrying.")
              end
            end
          end
        end

        # Wait for threads to finish
        threads.each { |aThread|  aThread.join }

      end
      module_function :process_files

      # A helper function to attempt to run a
      # function retries times
      #
      # Parameters:
      # +function+:: Function to run
      # +retries+:: Number of retries to attempt
      # +attempt_msg+:: Message to puts on each attempt
      # +failure_msg+:: Message to puts on each failure
      def retry_x(object, send_args, retries, attempt_msg, failure_msg)
        i = 0
        begin
          object.send(*send_args)
          puts attempt_msg
        rescue
          raise unless i < retries
          puts failure_msg
          sleep(RETRY_WAIT)  # Give us a bit of time before retrying
          i += 1
          retry
        end        
      end
      module_function :retry_x

      # A helper function to prepare destination
      # filenames and paths. This is a bit weird
      # - it needs to exist because of differences
      # in the way that Amazon S3, Fog and Unix
      # treat filepaths versus keys.
      #
      # Parameters:
      # +filepath+:: Path to file (including old filename)
      # +new_filename+:: Replace the filename in the path with this
      # +remove_path+:: If this is set, strip this from the front of the path
      # +add_path+:: If this is set, add this to the front of the path
      # +flatten+:: strips off any sub-folders below the from_location
      #
      # TODO: this really needs unit tests
      def name_file(filepath, new_filename, remove_path=nil, add_path=nil, flatten=false)

        # First, replace the filename in filepath with new one
        dirname = File.dirname(filepath)
        new_filepath = (dirname == '.') ? new_filename : dirname + '/' + new_filename

        # Nothing more to do
        return new_filepath if remove_path.nil? and add_path.nil? and not flatten

        shortened_filepath =  if flatten
                                # Let's revert to just the filename
                                new_filename
                              else
                                # If we have a 'remove_path', it must be found at
                                # the start of the path.
                                # If it's not, you're probably using name_file()
                                # wrong.
                                if !filepath.start_with?(remove_path)
                                  raise StorageOperationError, "name_file failed. Filepath '#{filepath}' does not start with '#{remove_path}'"
                                end

                                # Okay, let's remove the filepath
                                new_filepath[remove_path.length()..-1]
                              end

        # Nothing more to do
        return shortened_filepath if add_path.nil?

        # Add the new filepath on to the start and return
        add_path + shortened_filepath
      end
      module_function :name_file

    end
  end
end
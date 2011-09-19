#!/usr/bin/env ruby
# Indexer command

#--
## This file is a part of the Restad project
## https://github.com/ymoreau/Restad
##
## Copyright (C) 2011 LIA (www.lia.univ-avignon.fr)
##
## This program is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program.  If not, see <http://www.gnu.org/licenses/>.
##++
#

require './utils'
require './config_parser.rb'
require './parser.rb'
require './data_manager.rb'
require 'optparse'

VERSION = '0.1'

#-------------------------------------------------------------------------------
# Parse the options
options = Hash.new
optparser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options] document-file OR documents-dir\n       #{$0} [options] -d"

  opts.separator ""
  opts.separator "Specific options:"

  options[:multiple_documents] = false
  opts.on('-a', '--multiple-documents', 'XML file(s) contain multiple documents.',
          'Will explode the input file(s) input depending on config.') do
    options[:multiple_documents] = true
  end

  options[:configfile] = Restad::ConfigParser::DEFAULT_FILE
  opts.on('-c', '--config FILE', String, 'Specify the config file path.') do |file|
    options[:configfile] = file
  end

  options[:copy_only] = false
  opts.on('-d', '--database-copy-only', 'Copy the temporary data files into database.') do
    options[:copy_only] = true
  end

  options[:use_files] = false
  opts.on('-f', '--use-temp-files', 'Use temporary files to store data before sending to database, uses RAM only by default.',
          'Will automatically be set when using copy-only or index-only mode.') do
    options[:use_files] = true
  end

  options[:index_only] = false
  opts.on('-i', '--index-only', 'Create the temporary data files without copying into database.',\
          'Ignored if copy-only option is set.') do
    options[:index_only] = true
  end

  options[:max_mem] = 2000
  opts.on('-m', '--max-mem SIZE', Integer, 'Specify the maximum memory to use in MB. Default is 2000 MB.',\
          'This includes the memory needed for program initial data.') do |max_size|
    options[:max_mem] = max_size
  end

  options[:display_refresh_frequency] = 100
  opts.on('-n', '--refresh-file-number NUMBER', Integer, 'Specify the number of files to parse before each refresh of the displayed infos.',
          'Default is 100. Value is also used for frequency of checking the max memory limit.') do |count|
    options[:display_refresh_frequency] = count
  end

  options[:tempdir] = nil
  opts.on('-p', '--temp-dir FILE', String, 'Specify the temporary files path. Only used for index or copy only modes.') do |path|
    options[:tempdir] = path
  end

  options[:recursive] = false
  opts.on('-r', '--recursive', 'Search recursively in the subdirs of the given dir.',\
          'Ignored if a file is given, or if using copy-only mode.') do
    options[:recursive] = true
  end

  options[:timing] = false
  opts.on('-t', '--timing', 'Output timing information.') do
    options[:timing] = true
  end

  options[:unique_docs] = false
  opts.on('-u', '--unique-docs', 'Ignore documents for which file-path is already in the database.',\
          'Document file-path is stored as given to the indexing command, then it may be relative or absolute.',\
          'Ignored if using copy-only mode.') do
    options[:unique_docs] = true
  end

  options[:verbose] = false
  opts.on('-v', '--verbose', 'Output more information.') do
    options[:verbose] = true
  end

  opts.separator ""
  opts.separator "Common options:"

  opts.on_tail("-h", "--help", "Show this message.") do
    puts opts
    exit
  end

  opts.on_tail("--version", "Show version.") do
    puts "Restad indexer #{VERSION}"
    exit
  end
end
optparser.parse! # Clear the options from ARGV list

if options[:copy_only]
  $stderr.puts "Index-only mode will be ignored because copy-only is set" if options[:index_only]
  options[:index_only] = false
end

# Display help if args are missing
if ARGV.size < 1 and (not options[:copy_only])
  puts optparser
  exit
end

#-------------------------------------------------------------------------------
# Parse the args
corpus = ARGV[0]

#-------------------------------------------------------------------------------
# Initialize the config
db = nil
doc_exploder = nil
unless options[:use_files]
  options[:use_files] = (options[:copy_only] or options[:index_only])
end
temp_dir = nil
begin
  config = Restad::ConfigParser.new(options[:configfile])

  if options[:use_files]
    # Check the temporary dir
    if options[:tempdir].nil?
      temp_dir = config.map["temp-dir"]
    else
      temp_dir = options[:tempdir]
    end
    temp_dir << '/' if temp_dir[-1] != '/'
    raise Restad::RestadException, "Temporary dir missing" if temp_dir.nil?
    raise Restad::RestadException, "Temporary dir not found" unless Dir.exist?(temp_dir)

    config.set_temporary_dir(temp_dir)
  end

  db = config.database_connection
  puts "Database connection successful" if options[:verbose]
  
  if options[:multiple_documents]
    doc_exploder = config.document_exploder
    raise Restad::RestadException, "Missing config info (document root tag)" if doc_exploder.nil?
    doc_exploder.refresh_frequency = options[:display_refresh_frequency]
    doc_exploder.max_mem = options[:max_mem]
  end
rescue Restad::RestadException => e
  db.finish unless db.nil?
  $stderr.puts e
  exit
end

#-------------------------------------------------------------------------------
# Index the documents
unless options[:copy_only]
  total_files_count = 0
  done_files_count = 0
  failed_files_count = 0
  begin
    # Check the corpus file/dir
    if File.directory?(corpus)
      raise Restad::RestadException, "'#{corpus}' dir not found" unless Dir.exist?(corpus)
      corpus_path = "#{corpus}#{'/' if corpus[-1] != '/'}*#{'*/*' if options[:recursive]}"
    else
      raise Restad::RestadException, "'#{corpus}' file not found" unless File.exist?(corpus)
      corpus_path = corpus
    end

    # List the files
    time = Time.now
    files = Dir.glob(corpus_path)
    total_files_count = files.size
    puts "#{total_files_count} file(s) found#{' in ' + Time.elapsed(time).to_s + 's' if options[:timing]}" if options[:verbose] or options[:timing]

    time = Time.now
    parser = Restad::Parser.new(db, options[:use_files], options[:unique_docs], options[:verbose], temp_dir, doc_exploder)
    puts "Parser initialized in #{Time.elapsed(time).to_s}s" if options[:timing]
    used_mem = Restad::Utils.used_memory
    puts "Using #{used_mem}MB initial data" if options[:verbose]
    raise Restad::RestadException, "Initial data use too much memory (#{used_mem}MB)" if used_mem > options[:max_mem]

    # Process the files
    refreshing_count = options[:display_refresh_frequency] + 1 # Forces the refresh at first loop
    time = Time.now
    files.each do |filename|
      next if File.directory?(filename) # Ignore directories

      # Do not print/puts anything during the loop, the line is updated during the process
      if refreshing_count > options[:display_refresh_frequency] and (options[:verbose] or options[:timing])
        output = ""
        output << "#{done_files_count} / #{files.size} (#{((done_files_count.to_f/files.size)*100).round}%)     (#{used_mem}MB used)        " if options[:verbose]
        output << "Time elapsed: #{Time.elapsed(time)}s" if options[:timing]
        print "\r#{output}                                "
      end

      # Parse the file
      if parser.parse(filename)
        done_files_count += 1
      else
        failed_files_count += 1
      end
      if refreshing_count > options[:display_refresh_frequency]
        used_mem = Restad::Utils.used_memory
        parser.flush_buffers if used_mem > (0.8 * options[:max_mem]).to_i
        refreshing_count = 1
      end

      refreshing_count += 1
    end
    parser.close_buffers # Automatically flush buffers before closing them
    puts "\r#{done_files_count} / #{files.size} file(s) done (#{failed_files_count} failed)\t#{'Time elapsed: ' + Time.elapsed(time).to_s + 's' if options[:timing]}" if options[:verbose] or options[:timing]

  rescue Restad::RestadException, PGError => e
    db.finish
    $stderr.puts "\n#{done_files_count} file(s) on #{total_files_count} have been processed (#{failed_files_count} have failed), in #{Time.elapsed(time)}s..."
    $stderr.puts "Error: #{e}"
    $stderr.puts "Warnings:\n#{parser.error_log}" unless parser.error_log.empty?
    exit
  end
  $stderr.puts "Warnings:\n#{parser.error_log}" unless parser.error_log.empty?
end

#-------------------------------------------------------------------------------
# Load the temporary files
if options[:copy_only] or (options[:use_files] and (not options[:index_only]))
  begin
    data_manager = Restad::DataManager.new(db, true, temp_dir)
    data_manager.load_temporary_files
  rescue Restad::RestadException, PGError => e
    $stderr.puts e
  end
end

db.finish


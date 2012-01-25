#!/usr/bin/env ruby
# pre-parser command

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
require './preparser.rb'
require 'optparse'

VERSION = '0.1'

#-------------------------------------------------------------------------------
# Parse the options
options = Hash.new
optparser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options] document-file OR documents-dir",
                "file(s) will be parsed as XML unless file extension is .dtd"

  opts.separator ""

  options[:configfile] = Restad::ConfigParser::DEFAULT_FILE
  opts.on('-c', '--config FILE', String, 'Specify the config file path.') do |file|
    options[:configfile] = file
  end

  options[:display_refresh_frequency] = 100
  opts.on('-n', '--refresh-file-number NUMBER', Integer, 'Specify the number of files to parse before each refresh of the displayed infos.',
          'Default is 100.') do |count|
    options[:display_refresh_frequency] = count
  end

  options[:recursive] = false
  opts.on('-r', '--recursive', 'Search recursively in the subdirs of the given dir.',\
          'Ignored if a file is given.') do
    options[:recursive] = true
  end

  options[:timing] = false
  opts.on('-t', '--timing', 'Output timing information.') do
    options[:timing] = true
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

# Display help if args are missing
if ARGV.size < 1
  puts optparser
  exit
end

#-------------------------------------------------------------------------------
# Parse the args
corpus = ARGV[0]

#-------------------------------------------------------------------------------
# Initialize the config
begin
  config = Restad::ConfigParser.new(options[:configfile])

  db = config.database_connection
  puts "Database connection successful" if options[:verbose]

rescue Restad::RestadException => e
  db.finish unless db.nil?
  $stderr.puts e
  exit
end

#-------------------------------------------------------------------------------
# Parse the documents
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
  parser = Restad::Preparser.new(db)
  puts "Parser initialized in #{Time.elapsed(time).to_s}s" if options[:timing]

  # Process the files
  time = Time.now
  refreshing_count = options[:display_refresh_frequency] + 1 # Forces the refresh at first loop
  files.each do |filename|
    next if File.directory?(filename) # Ignore directories

    # Parse the file
    if parser.parse(filename)
      done_files_count += 1
    else
      failed_files_count += 1
    end

    if refreshing_count > options[:display_refresh_frequency] and (options[:verbose] or options[:timing])
      output = ""
      output << "#{done_files_count} / #{files.size} (#{((done_files_count.to_f/total_files_count)*100).round}%)    " if options[:verbose]
      output << "Time elapsed: #{Time.elapsed(time)}s" if options[:timing]
      print "\r#{output}                                "
    end
  end

  parser.commit # Commit the data
  puts "\r#{done_files_count} / #{files.size} file(s) done (#{failed_files_count} failed)    #{'Time elapsed: ' + Time.elapsed(time).to_s + 's' if options[:timing]}" if options[:verbose] or options[:timing]

rescue Restad::RestadException, PGError => e
  db.finish
  $stderr.puts "\n#{done_files_count} file(s) on #{total_files_count} have been processed (#{failed_files_count} have failed), in #{Time.elapsed(time)}s..."
  $stderr.puts "Error: #{e}"
  $stderr.puts "Warnings:\n#{parser.error_log}" unless parser.error_log.empty?
  exit
end
$stderr.puts "Warnings:\n#{parser.error_log}" unless parser.error_log.empty?

db.finish


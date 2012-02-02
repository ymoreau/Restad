#!/usr/bin/env ruby
# Document generator command

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
require './doc_generator.rb'
require 'optparse'

VERSION = '0.1'
#-------------------------------------------------------------------------------
# Parse the options
options = Hash.new
optparser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options] document-name [output-file]\n       #{$0} [options] -d document-id [output-file]"
  opts.banner += "\nIf no output-file is specified, document name in database will be used, in ./ directory."

  opts.separator ""
  opts.separator "Specific options:"

  options[:configfile] = Restad::ConfigParser::DEFAULT_FILE
  opts.on('-c', '--config FILE', String, 'Specify the config file path') do |file|
    options[:configfile] = file
  end

  options[:doc_id] = nil
  opts.on('-d', '--docid ID', Integer, 'Specify the document id. Do not specify a document-name with this option.') do |doc_id|
    options[:doc_id] = doc_id
  end

  options[:exactpath] = false
  opts.on('-e', '--exact-path', 'Search for the exact given full filename path in the database', \
          '  Search for */FILENAME by default') do
    options[:exactpath] = true
  end

  options[:indentlevel] = 2
  opts.on('-i', '--indent K', Integer, 'Set the indent level to K spaces',\
          '  2 by default (ignored if no-newline is set)') do |indentlevel|
    options[:indentlevel] = indentlevel unless indentlevel < 0
  end

  options[:use_newline] = true
  opts.on('-n', '--no-newline', 'Produce the xml document without newlines') do
    options[:use_newline] = false
  end

  options[:timing] = false
  opts.on('-t', '--timing', 'Output timing information') do
    options[:timing] = true
  end

  options[:verbose] = false
  opts.on('-v', '--verbose', 'Output more information') do
    options[:verbose] = true
  end

  options[:excluded] = ""
  opts.on('-x', '--excluded TAGS', String, 'Does not do newline for these tags. Separate with comma.') do |excluded|
    options[:excluded] = excluded
  end

  opts.separator ""
  opts.separator "Common options:"

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end

  opts.on_tail("--version", "Show version") do
    puts "Restad document generator #{VERSION}"
    exit
  end
end
optparser.parse! # Clear the options from ARGV list

# Disable indenting if no newline option is set
unless options[:use_newline]
  options[:indentlevel] = 0
end

# Display help if args are missing
if ARGV.size < 1 and options[:doc_id].nil?
  puts optparser
  exit
end

#-------------------------------------------------------------------------------
# Parse the args
document_name = ARGV[0]
output_file = nil
output_file = ARGV[0] unless options[:doc_id].nil?
output_file = ARGV[1] if ARGV.size > 1

#-------------------------------------------------------------------------------
# Generates the document file
begin
  config = Restad::ConfigParser.new(options[:configfile])
  db = config.database_connection
  puts "Database connection successful" if options[:verbose]

  excluded_tags = options[:excluded].split(",")

  generator = Restad::DocGenerator.new(db, output_file, excluded_tags, options[:doc_id])
  # Search for the document id
  if generator.doc_id.nil?
    time = Time.now
    if generator.find_doc(document_name, (not options[:exactpath]))
      puts "Document found in #{Time.elapsed(time)}s" if options[:timing]
      puts "Document id: #{generator.doc_id}" if options[:verbose]
    else
      raise Restad::RestadException, "Doc '#{document_name}' not found..."
    end
  end

  # Set the output file
  if generator.output_path.nil?
    doc_name = generator.find_doc_name
    generator.output_path = File.basename(doc_name)
    puts "Using '#{generator.output_path}' as output file" if options[:verbose]
  end

  # Generate the xml file
  time = Time.now
  generator.generate_file(options[:indentlevel], options[:use_newline], options[:verbose], options[:timing])
  puts "Document generated in #{Time.elapsed(time)}s" if options[:timing]
rescue Restad::RestadException, PGError => e
  $stderr.puts e
end
